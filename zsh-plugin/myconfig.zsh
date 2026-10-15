# Render and reload the current shell, preview, check, or publish the three Zsh blocks.
myconfig() {
    # Isolate command bookkeeping; reload successful default renders in the caller below.
    (
        emulate -LR zsh
        setopt pipefail

        local config_root="${functions_source[myconfig]:A:h:h}"
        local engine="$config_root/zsh/weave/zshrc-weave.zsh"
        local action="${1:---help}" output_file="${ZSH_WEAVE_OUTPUT_FILE:-$HOME/.zshrc}"
        local message='' answer backup branch remote merge_ref upstream source_path commit_id platform
        local -a block_paths changed_paths pending_paths git_command
        git_command=(git -c core.fsmonitor=false -C "$config_root")
        (( $# )) && shift

        case "$action" in
            --help|-h)
                print 'Usage: myconfig render [--print | --output FILE]'
                print '       myconfig check'
                print '       myconfig sync [-m MESSAGE]'
                print 'render: generate and reload ~/.zshrc; confirm and back up an existing file'
                print '        --print previews on stdout; --output FILE writes without reloading'
                print 'check: validate syntax and block boundaries, and report differences'
                print 'sync: check, write back, commit only the Zsh blocks, and push to the upstream'
                return 0
                ;;
            render)
                if [[ $# == 1 && "$1" == --print ]]; then
                    output_file=-
                elif (( $# )); then
                    [[ $# == 2 && "$1" == --output && -n "$2" ]] || {
                        print -u2 'Usage: myconfig render [--print | --output FILE]'
                        return 64
                    }
                    output_file="${2:a}"
                fi
                ;;
            check)
                (( $# == 0 )) || { print -u2 'Usage: myconfig check'; return 64; }
                ;;
            sync)
                if (( $# )); then
                    [[ $# == 2 && "$1" == -m && -n "$2" ]] || {
                        print -u2 'Usage: myconfig sync [-m MESSAGE]'
                        return 64
                    }
                    message="$2"
                fi
                ;;
            *)
                print -u2 -- "myconfig: unknown command: $action"
                return 64
                ;;
        esac

        [[ -r "$engine" ]] || { print -u2 'myconfig: missing rendering engine'; return 1; }
        export ZSH_WEAVE_CONFIG_DIR="$config_root/zsh"
        export ZSH_WEAVE_OUTPUT_FILE="$output_file"
        export ZSH_WEAVE_ADOPT=0

        case "$action" in
            render)
                if [[ "$output_file" == - ]]; then
                    command zsh -f "$engine" render auto
                    return $?
                fi
                [[ ! -d "$output_file" ]] || {
                    print -u2 'myconfig: output must be a file'
                    return 1
                }
                if [[ -e "$output_file" || -L "$output_file" ]]; then
                    command ls -ld -- "$output_file"
                    read -r "answer?备份并重新生成 $output_file？[y/N] " || return 1
                    [[ "$answer" == [yY] ]] || { print '已取消渲染。'; return 1; }
                    backup="${output_file}.myconfig-backup-$(command date '+%Y%m%d%H%M%S')-$$"
                    [[ ! -e "$backup" && ! -L "$backup" ]] || return 1
                    command cp -Pp -- "$output_file" "$backup" || return 1
                    print -r -- "已备份: $backup"
                    export ZSH_WEAVE_ADOPT=1
                fi
                command zsh -f "$engine" render auto || return $?
                print -r -- "已生成: $output_file"
                ;;
            check)
                command zsh -f "$engine" check auto
                ;;
            sync)
                [[ "$(command "${git_command[@]}" rev-parse --show-toplevel 2>/dev/null)" == "$config_root" ]] || {
                    print -u2 'myconfig: plugin must belong to the configuration Git checkout'
                    return 1
                }
                if [[ "$OSTYPE" == darwin* ]]; then
                    platform=macos
                    block_paths=(zsh/before.zshrc zsh/zshrc.macos zsh/after.zshrc)
                elif [[ -f /etc/debian_version ]]; then
                    platform=debian
                    block_paths=(zsh/before.zshrc zsh/zshrc.debian zsh/after.zshrc)
                else
                    print -u2 'myconfig: unsupported platform'
                    return 1
                fi
                command "${git_command[@]}" ls-files --error-unmatch -- "${block_paths[@]}" >/dev/null || return 1
                command "${git_command[@]}" diff --cached --quiet -- "${block_paths[@]}" || {
                    print -u2 'myconfig: Zsh blocks already have staged changes; resolve them before sync'
                    return 1
                }
                branch="$(command "${git_command[@]}" symbolic-ref --quiet --short HEAD)" || return 1
                remote="$(command "${git_command[@]}" config --get "branch.$branch.remote")" || return 1
                merge_ref="$(command "${git_command[@]}" config --get "branch.$branch.merge")" || return 1
                upstream="$(command "${git_command[@]}" rev-parse --symbolic-full-name '@{upstream}')" || {
                    print -u2 'myconfig: configure an upstream branch before sync'
                    return 1
                }
                [[ "$remote" != . && "$merge_ref" == refs/heads/* ]] || return 1

                # A push includes earlier local commits; refuse unrelated outgoing changes.
                for commit_id in ${(f)"$(command "${git_command[@]}" rev-list "$upstream..HEAD")"}; do
                    pending_paths=("${(@f)$(command "${git_command[@]}" diff-tree --root -m --no-commit-id --name-only -r "$commit_id")}")
                    for source_path in "${pending_paths[@]}"; do
                        [[ -z "$source_path" || ${block_paths[(Ie)$source_path]} != 0 ]] || {
                            print -u2 'myconfig: unpushed commits contain other files; publish them separately first'
                            return 1
                        }
                    done
                done

                command zsh -f "$engine" sync "$platform" || return $?
                changed_paths=("${(@f)$(command "${git_command[@]}" diff --name-only HEAD -- "${block_paths[@]}")}")
                changed_paths=("${(@)changed_paths:#}")
                if (( ${#changed_paths} )); then
                    [[ -n "$message" ]] || message="Sync Zsh configuration: $(command date '+%Y-%m-%d %H:%M:%S')"
                    command "${git_command[@]}" commit --only -m "$message" -- "${changed_paths[@]}" || {
                        print -u2 'myconfig: commit failed; write-back is retained, and nothing was pushed'
                        return 1
                    }
                else
                    print '没有需要提交的配置块变更。'
                fi
                command "${git_command[@]}" push "$remote" "HEAD:$merge_ref" || {
                    print -u2 'myconfig: push failed; local commits are retained; rerun sync to retry'
                    return 1
                }
                print '配置块已同步到远端。'
                ;;
        esac
    ) || return $?

    if [[ "${1:-}" == render && $# == 1 ]]; then
        builtin source "${ZSH_WEAVE_OUTPUT_FILE:-$HOME/.zshrc}"
    fi
}
