#!/usr/bin/env zsh
# zshrc-weave renders three fixed blocks into ~/.zshrc and maps edited blocks
# back to their files below ~/.config. It never invokes Git.

emulate -LR zsh
setopt pipefail

SCRIPT_DIR="${0:A:h}"
CONFIG_DIR="${ZSH_WEAVE_CONFIG_DIR:-${SCRIPT_DIR:h}}"
CONFIG_ROOT="${CONFIG_DIR:h}"
OUTPUT_FILE="${ZSH_WEAVE_OUTPUT_FILE:-$HOME/.zshrc}"
WEAVE_DIR="$CONFIG_DIR/weave"
STATUS_FILE="$WEAVE_DIR/.status"
LOG_DIR="${ZSH_WEAVE_LOG_DIR:-$CONFIG_ROOT/logs}"
ERROR_LOG="$LOG_DIR/zshrc-weave.error.log"
POLL_INTERVAL="${ZSH_WEAVE_POLL_INTERVAL:-1}"

typeset -ga PLATFORM_PATHS

usage() {
    print 'Usage: zshrc-weave.zsh <render|sync|daemon|status> [macos|debian|auto]'
    print 'Environment: ZSH_WEAVE_CONFIG_DIR, ZSH_WEAVE_OUTPUT_FILE'
}

fail() {
    local message="$*"
    command mkdir -p "$LOG_DIR" 2>/dev/null || true
    command chmod 700 "$LOG_DIR" 2>/dev/null || true
    print -r -- "$(now) ERROR ${message}" >> "$ERROR_LOG" 2>/dev/null || true
    command chmod 600 "$ERROR_LOG" 2>/dev/null || true
    print -u2 -- "zshrc-weave: $message"
    return 1
}

now() {
    command date -u '+%Y-%m-%dT%H:%M:%SZ'
}

write_status() {
    local state="$1"
    local platform="$2"
    local detail="${3:-}"
    command mkdir -p "$WEAVE_DIR" || return 1
    {
        print -r -- "state=${state}"
        print -r -- "platform=${platform}"
        print -r -- "updated_at=$(now)"
        print -r -- "detail=${detail}"
    } > "$STATUS_FILE"
    command chmod 600 "$STATUS_FILE" 2>/dev/null || true
}

file_hash() {
    local target_file="$1"
    [[ -f "$target_file" ]] || return 0
    if (( $+commands[shasum] )); then
        command shasum -a 256 "$target_file" | command awk '{print $1}'
    elif (( $+commands[sha256sum] )); then
        command sha256sum "$target_file" | command awk '{print $1}'
    else
        command cksum "$target_file" | command awk '{print $1 ":" $2}'
    fi
}

file_mode() {
    local target_file="$1"
    if [[ "$OSTYPE" == darwin* ]]; then
        command stat -f '%Lp' "$target_file"
    else
        command stat -c '%a' "$target_file"
    fi
}

resolve_platform() {
    local requested="${1:-auto}"
    case "$requested" in
        macos|debian)
            print -r -- "$requested"
            ;;
        auto)
            if [[ "${ZSH_WEAVE_PLATFORM:-}" == macos || "${ZSH_WEAVE_PLATFORM:-}" == debian ]]; then
                print -r -- "$ZSH_WEAVE_PLATFORM"
            elif [[ "$OSTYPE" == darwin* ]]; then
                print -r -- macos
            elif [[ -f /etc/debian_version ]]; then
                print -r -- debian
            else
                fail "unsupported platform: $OSTYPE"
            fi
            ;;
        *)
            fail "unknown platform: $requested"
            ;;
    esac
}

load_platform_paths() {
    local platform="$1"
    local source_path

    case "$platform" in
        macos|debian)
            PLATFORM_PATHS=(
                'zsh/before.zshrc'
                "zsh/zshrc.${platform}"
                'zsh/after.zshrc'
            )
            ;;
        *)
            fail "unknown platform: $platform"
            return 1
            ;;
    esac

    for source_path in "${PLATFORM_PATHS[@]}"; do
        [[ -r "$CONFIG_ROOT/$source_path" ]] || fail "missing source block: $CONFIG_ROOT/$source_path" || return 1
    done
}

is_managed_output() {
    [[ -f "$OUTPUT_FILE" ]] && command grep -q '^# ===== BEGIN zsh/before\.zshrc =====$' "$OUTPUT_FILE"
}

prepare_output_target() {
    local output_dir="${OUTPUT_FILE:h}"
    command mkdir -p "$output_dir" || return 1

    if [[ -e "$OUTPUT_FILE" ]] && ! is_managed_output; then
        [[ "${ZSH_WEAVE_ADOPT:-0}" == 1 ]] || {
            fail "refusing to overwrite unmanaged $OUTPUT_FILE; set ZSH_WEAVE_ADOPT=1 after backing it up"
            return 1
        }
        local backup="${OUTPUT_FILE}.zshrc-weave-backup-$(command date '+%Y%m%d%H%M%S')"
        command cp -p "$OUTPUT_FILE" "$backup" || return 1
    fi
}

render() {
    local platform
    platform="$(resolve_platform "${1:-auto}")" || return 1
    load_platform_paths "$platform" || return 1
    prepare_output_target || return 1

    local output_dir="${OUTPUT_FILE:h}"
    local temp_file source_path
    temp_file="$(command mktemp "$output_dir/.zshrc-weave.XXXXXX")" || return 1

    {
        for source_path in "${PLATFORM_PATHS[@]}"; do
            print -r -- "# ===== BEGIN $source_path ====="
            command cat "$CONFIG_ROOT/$source_path"
            print -r -- "# ===== END $source_path ====="
            print -r --
        done
    } > "$temp_file"

    if ! command zsh -n "$temp_file"; then
        command rm -f "$temp_file"
        fail "rendered output has invalid Zsh syntax"
        return 1
    fi

    command chmod 600 "$temp_file"
    command mv "$temp_file" "$OUTPUT_FILE"
    write_status idle "$platform" 'rendered'
}

sync() {
    local platform
    platform="$(resolve_platform "${1:-auto}")" || return 1
    load_platform_paths "$platform" || return 1
    is_managed_output || {
        fail "not a managed output: $OUTPUT_FILE"
        return 1
    }

    local workspace output_content expected_path begin_marker end_marker block_content
    local -i block_index=0
    workspace="$(command mktemp -d "${TMPDIR:-/tmp}/zshrc-weave.XXXXXX")" || return 1

    IFS= read -r -d '' output_content < "$OUTPUT_FILE" || true
    for (( block_index = 1; block_index <= ${#PLATFORM_PATHS}; block_index++ )); do
        expected_path="${PLATFORM_PATHS[$block_index]}"

        if (( block_index > 1 )); then
            [[ "${output_content[1,1]}" == $'\n' ]] || {
                command rm -rf "$workspace"
                fail "missing separator before block: $expected_path"
                return 1
            }
            output_content="${output_content[2,-1]}"
        fi

        begin_marker="# ===== BEGIN $expected_path ====="$'\n'
        [[ "$output_content" == "$begin_marker"* ]] || {
            command rm -rf "$workspace"
            fail "expected block: $expected_path"
            return 1
        }
        output_content="${output_content[$(( ${#begin_marker} + 1 )),-1]}"

        end_marker="# ===== END $expected_path ====="$'\n'
        [[ "$output_content" == *"$end_marker"* ]] || {
            command rm -rf "$workspace"
            fail "missing END marker for: $expected_path"
            return 1
        }
        block_content="${output_content%%"$end_marker"*}"
        output_content="${output_content#*"$end_marker"}"
        print -rn -- "$block_content" > "$workspace/$block_index"
    done

    [[ "$output_content" == $'\n' ]] || {
        command rm -rf "$workspace"
        fail 'unmanaged content outside fixed blocks'
        return 1
    }

    if ! command zsh -n "$OUTPUT_FILE"; then
        command rm -rf "$workspace"
        fail "edited output has invalid Zsh syntax; source blocks were not changed"
        return 1
    fi

    local source_path source_file source_dir temp_file mode changed=0
    for (( block_index = 1; block_index <= ${#PLATFORM_PATHS}; block_index++ )); do
        source_path="${PLATFORM_PATHS[$block_index]}"
        source_file="$CONFIG_ROOT/$source_path"
        command cmp -s "$workspace/$block_index" "$source_file" && continue
        source_dir="${source_file:h}"
        temp_file="$(command mktemp "$source_dir/.${source_file:t}.zshrc-weave.XXXXXX")" || {
            command rm -rf "$workspace"
            return 1
        }
        command cat "$workspace/$block_index" > "$temp_file"
        mode="$(file_mode "$source_file")" && command chmod "$mode" "$temp_file"
        command mv "$temp_file" "$source_file"
        changed=1
    done

    command rm -rf "$workspace"
    write_status idle "$platform" "sync changed=$changed"
}

daemon() {
    local platform
    platform="$(resolve_platform "${1:-auto}")" || return 1

    if [[ ! -e "$OUTPUT_FILE" ]]; then
        fail "cannot watch a missing output: $OUTPUT_FILE"
        write_status error "$platform" 'missing output'
        return 1
    elif ! is_managed_output; then
        fail "cannot watch unmanaged output: $OUTPUT_FILE"
        write_status error "$platform" 'unmanaged output'
        return 1
    fi

    write_status watching "$platform" "output=$OUTPUT_FILE"

    local last_output output_hash
    last_output="$(file_hash "$OUTPUT_FILE")"

    while true; do
        command sleep "$POLL_INTERVAL"
        output_hash="$(file_hash "$OUTPUT_FILE")"

        if [[ "$output_hash" != "$last_output" ]]; then
            if sync "$platform"; then
                :
            else
                write_status error "$platform" 'output sync rejected'
            fi
        fi

        last_output="$output_hash"
    done
}

status() {
    if [[ -r "$STATUS_FILE" ]]; then
        command cat "$STATUS_FILE"
    else
        print 'state=stopped'
    fi
}

case "${1:-}" in
    render)
        render "${2:-auto}"
        ;;
    sync)
        sync "${2:-auto}"
        ;;
    daemon)
        daemon "${2:-auto}"
        ;;
    status)
        status
        ;;
    *)
        usage
        exit 64
        ;;
esac
