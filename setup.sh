#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_SOURCE="${BASH_SOURCE[0]-$0}"
CONFIG_DIR="$(cd -- "$(dirname -- "$SCRIPT_SOURCE")" && pwd)"
WEAVE_SCRIPT="$CONFIG_DIR/zsh/weave/zshrc-weave.zsh"
MACOS_PACKAGES_FILE="$CONFIG_DIR/macos.txt"
DEBIAN_PACKAGES_FILE="$CONFIG_DIR/debian.txt"
DEFAULT_REPO_SSH_URL='git@github.com:marlinl/config.git'
REPO_SSH_URL="${CONFIG_REPO_SSH_URL:-$DEFAULT_REPO_SSH_URL}"
CONFIG_TARGET_DIR="$HOME/.config"
DRY_RUN=0

usage() {
    cat <<'EOF'
Usage:
  ./setup.sh
  ./setup.sh --dry-run
  ./setup.sh --test <directory>

Without arguments, install the platform dependencies, render ~/.zshrc, create
the standard ~/.zprofile and ~/.vimrc links, and enable zshrc-weave.

--dry-run prints the selected installation plan without changing
the filesystem, installing packages, changing Git settings, or enabling a
service.

--test writes a standalone .zshrc into <directory> and the fixed, ignored
~/.config/zsh/weave/.status file. It does not install packages, create links,
configure Git, or enable a service.
EOF
}

die() {
    printf 'setup: %s\n' "$*" >&2
    exit 1
}

detect_os() {
    if [[ "$OSTYPE" == darwin* ]]; then
        printf 'macos\n'
    elif [[ -f /etc/debian_version ]]; then
        printf 'debian\n'
    else
        die "unsupported operating system: $OSTYPE"
    fi
}

confirm() {
    local prompt="$1"
    local answer=''
    if ! read -r -p "$prompt [y/N] " answer; then
        return 1
    fi
    [[ "$answer" == 'y' || "$answer" == 'Y' ]]
}

print_command() {
    printf '[dry-run]'
    printf ' %q' "$@"
    printf '\n'
}

directory_has_entries() {
    local target_dir="$1"
    [[ -n "$(find "$target_dir" -mindepth 1 -maxdepth 1 -print -quit)" ]]
}

is_config_checkout() {
    [[ -r "$CONFIG_DIR/setup.sh" && -r "$WEAVE_SCRIPT" ]]
}

is_config_target_checkout() {
    local remote_url

    [[ -d "$CONFIG_TARGET_DIR/.git" && -r "$CONFIG_TARGET_DIR/setup.sh" && -r "$CONFIG_TARGET_DIR/zsh/weave/zshrc-weave.zsh" ]] || return 1
    command -v git >/dev/null 2>&1 || return 1
    remote_url="$(git -C "$CONFIG_TARGET_DIR" config --get remote.origin.url 2>/dev/null || true)"
    [[ "$remote_url" == "$REPO_SSH_URL" ]]
}

require_weave() {
    [[ -r "$WEAVE_SCRIPT" ]] || die "missing zshrc-weave script: $WEAVE_SCRIPT"
    command -v zsh >/dev/null 2>&1 || die 'zsh is required before rendering .zshrc'
}

render_zshrc() {
    local platform="$1"
    local output_file="$2"
    local adopt="${3:-0}"

    ZSH_WEAVE_CONFIG_DIR="$CONFIG_DIR/zsh" \
    ZSH_WEAVE_OUTPUT_FILE="$output_file" \
    ZSH_WEAVE_ADOPT="$adopt" \
    zsh -f "$WEAVE_SCRIPT" render "$platform"

    zsh -n "$output_file"
}

run_test() {
    local platform="$1"
    local requested_dir="$2"
    local target_dir home_dir output_file adopt=0

    mkdir -p "$requested_dir"
    target_dir="$(cd -- "$requested_dir" && pwd -P)"
    home_dir="$(cd -- "$HOME" && pwd -P)"
    [[ "$target_dir" != "$home_dir" ]] || die '--test directory must not be your home directory'

    if directory_has_entries "$target_dir"; then
        if ! confirm "测试目录 $target_dir 非空；仅写入或替换 $target_dir/.zshrc，继续吗？"; then
            printf '已放弃测试写入。\n'
            return 0
        fi
        adopt=1
    fi

    require_weave
    output_file="$target_dir/.zshrc"
    render_zshrc "$platform" "$output_file" "$adopt"

    printf '✅ 测试输出已生成: %s\n' "$output_file"
    printf '   未安装依赖、未创建符号链接、未修改线上配置、未启用服务；状态仅写入 ~/.config/zsh/weave/.status。\n'
}

install_macos_packages() {
    if ! command -v brew >/dev/null 2>&1; then
        printf '🍺 未检测到 Homebrew，开始安装...\n'
        /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
        if [[ -x /opt/homebrew/bin/brew ]]; then
            eval "$(/opt/homebrew/bin/brew shellenv)"
        fi
    fi

    [[ -r "$MACOS_PACKAGES_FILE" ]] || die "missing package list: $MACOS_PACKAGES_FILE"

    local line package install_mode extra
    while IFS= read -r line || [[ -n "$line" ]]; do
        [[ -n "$line" ]] || continue
        IFS=$' \t' read -r package install_mode extra <<< "$line"
        [[ -z "$extra" ]] || die "invalid package entry in $MACOS_PACKAGES_FILE: $line"

        case "$install_mode" in
            '')
                if ! brew ls --versions "$package" >/dev/null 2>&1; then
                    brew install "$package"
                fi
                ;;
            --cask)
                if ! brew ls --cask --versions "$package" >/dev/null 2>&1; then
                    brew install --cask "$package"
                fi
                ;;
            *)
                die "invalid package entry in $MACOS_PACKAGES_FILE: $line"
                ;;
        esac
    done < "$MACOS_PACKAGES_FILE"
}

install_debian_packages() {
    [[ -r "$DEBIAN_PACKAGES_FILE" ]] || die "missing package list: $DEBIAN_PACKAGES_FILE"

    local package
    local -a packages=()
    while IFS= read -r package || [[ -n "$package" ]]; do
        [[ -n "$package" ]] && packages+=("$package")
    done < "$DEBIAN_PACKAGES_FILE"
    (( ${#packages[@]} > 0 )) || die "empty package list: $DEBIAN_PACKAGES_FILE"

    sudo apt-get update
    sudo apt-get install -y "${packages[@]}"
}

plan_macos_packages() {
    [[ -r "$MACOS_PACKAGES_FILE" ]] || die "missing package list: $MACOS_PACKAGES_FILE"

    if ! command -v brew >/dev/null 2>&1; then
        printf '[dry-run] install Homebrew from https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh\n'
    fi

    local line package install_mode extra
    while IFS= read -r line || [[ -n "$line" ]]; do
        [[ -n "$line" ]] || continue
        IFS=$' \t' read -r package install_mode extra <<< "$line"
        [[ -z "$extra" ]] || die "invalid package entry in $MACOS_PACKAGES_FILE: $line"

        case "$install_mode" in
            '')
                print_command brew install "$package"
                ;;
            --cask)
                print_command brew install --cask "$package"
                ;;
            *)
                die "invalid package entry in $MACOS_PACKAGES_FILE: $line"
                ;;
        esac
    done < "$MACOS_PACKAGES_FILE"
}

plan_debian_packages() {
    [[ -r "$DEBIAN_PACKAGES_FILE" ]] || die "missing package list: $DEBIAN_PACKAGES_FILE"

    local package
    local -a packages=()
    while IFS= read -r package || [[ -n "$package" ]]; do
        [[ -n "$package" ]] && packages+=("$package")
    done < "$DEBIAN_PACKAGES_FILE"
    (( ${#packages[@]} > 0 )) || die "empty package list: $DEBIAN_PACKAGES_FILE"

    print_command sudo apt-get update
    print_command sudo apt-get install -y "${packages[@]}"
}

link_file() {
    local source_file="$1"
    local target_file="$2"
    local backup_file

    [[ -e "$source_file" ]] || die "missing link source: $source_file"
    if [[ -L "$target_file" && "$(readlink "$target_file")" == "$source_file" ]]; then
        return 0
    fi

    if [[ -e "$target_file" || -L "$target_file" ]]; then
        if ! confirm "$target_file 已存在，是否备份后替换？"; then
            die "保留已有文件，停止安装"
        fi
        backup_file="${target_file}.setup-backup-$(date '+%Y%m%d%H%M%S')"
        mv "$target_file" "$backup_file"
        printf '已备份: %s\n' "$backup_file"
    fi

    ln -s "$source_file" "$target_file"
}

render_live_zshrc() {
    local platform="$1"
    local output_file="$HOME/.zshrc"
    local adopt=0

    if [[ -e "$output_file" || -L "$output_file" ]]; then
        if ! grep -q '^# ===== BEGIN zsh/before\.zshrc =====$' "$output_file" 2>/dev/null; then
            if ! confirm "$output_file 不是 zshrc-weave 生成文件，是否备份后替换？"; then
                die '保留已有 ~/.zshrc，停止安装'
            fi
            adopt=1
        fi
    fi

    render_zshrc "$platform" "$output_file" "$adopt"
}

install_macos_service() {
    local template="$CONFIG_DIR/zsh/weave/com.marlinl.zshrc-weave.plist"
    local agent_dir="$HOME/Library/LaunchAgents"
    local agent_file="$agent_dir/com.marlinl.zshrc-weave.plist"
    local temporary_file

    [[ -r "$template" ]] || die "missing weave service template: $template"
    mkdir -p "$agent_dir"
    if [[ -e "$agent_file" || -L "$agent_file" ]]; then
        if ! confirm "$agent_file 已存在，是否覆盖 weave 服务？"; then
            printf '保留已有 weave 服务文件，跳过 macOS 服务安装。\n'
            return 0
        fi
    fi
    temporary_file="$(mktemp "$agent_dir/.zshrc-weave.XXXXXX")"
    sed "s|__HOME__|$HOME|g" "$template" > "$temporary_file"
    mv "$temporary_file" "$agent_file"

    launchctl bootout "gui/$UID/com.marlinl.zshrc-weave" 2>/dev/null || true
    launchctl bootstrap "gui/$UID" "$agent_file"
}

install_debian_service() {
    local unit_dir="$HOME/.config/systemd/user"
    local unit_file="$unit_dir/zshrc-weave.service"

    [[ -r "$CONFIG_DIR/zsh/weave/zshrc-weave.service" ]] \
        || die "missing weave service template: $CONFIG_DIR/zsh/weave/zshrc-weave.service"
    mkdir -p "$unit_dir"
    if [[ -e "$unit_file" || -L "$unit_file" ]]; then
        if ! confirm "$unit_file 已存在，是否覆盖 weave 服务？"; then
            printf '保留已有 weave 服务文件，跳过 Debian 服务安装。\n'
            return 0
        fi
    fi
    cp "$CONFIG_DIR/zsh/weave/zshrc-weave.service" "$unit_file"
    systemctl --user daemon-reload
    systemctl --user enable --now zshrc-weave.service
}

plan_install() {
    local platform="$1"

    printf '[dry-run] platform=%s\n' "$platform"
    if [[ "$platform" == macos ]]; then
        plan_macos_packages
    else
        plan_debian_packages
    fi

    print_command ln -s "$CONFIG_DIR/zsh/zprofile" "$HOME/.zprofile"
    print_command ln -s "$CONFIG_DIR/.vimrc" "$HOME/.vimrc"
    printf '[dry-run] render ~/.zshrc from zsh/before.zshrc, zsh/zshrc.%s, and zsh/after.zshrc\n' "$platform"

    if [[ "$platform" == macos ]]; then
        printf '[dry-run] install and bootstrap ~/Library/LaunchAgents/com.marlinl.zshrc-weave.plist (prompt before replacing an existing file)\n'
    else
        printf '[dry-run] install, daemon-reload, and enable ~/.config/systemd/user/zshrc-weave.service (prompt before replacing an existing file)\n'
    fi
    printf '[dry-run] complete a missing global Git identity and configure defaults when user.name is unset\n'
}

ensure_git_for_clone() {
    local platform="$1"

    command -v git >/dev/null 2>&1 && return 0
    if (( DRY_RUN )); then
        if [[ "$platform" == debian ]]; then
            print_command sudo apt-get update
            print_command sudo apt-get install -y git
        else
            printf '[dry-run] install macOS Command Line Tools to provide git\n'
        fi
        return 0
    fi

    if [[ "$platform" == debian ]]; then
        sudo apt-get update
        sudo apt-get install -y git
        return 0
    fi

    command -v xcode-select >/dev/null 2>&1 || die 'git is required to bootstrap this repository'
    xcode-select --install >/dev/null 2>&1 || true
    die 'macOS Command Line Tools installation was requested; run this command again after it finishes'
}

clone_and_install() {
    local platform="$1"
    local child_setup="$CONFIG_TARGET_DIR/setup.sh"

    if [[ -e "$CONFIG_TARGET_DIR" && ! -d "$CONFIG_TARGET_DIR" ]]; then
        die "config target is not a directory: $CONFIG_TARGET_DIR"
    fi

    if is_config_target_checkout; then
        if (( DRY_RUN )); then
            printf '[dry-run] reuse existing checkout: %s\n' "$CONFIG_TARGET_DIR"
            exec /usr/bin/env bash "$child_setup" --dry-run
        fi
        exec /usr/bin/env bash "$child_setup"
    fi

    if [[ -d "$CONFIG_TARGET_DIR" ]] && directory_has_entries "$CONFIG_TARGET_DIR"; then
        die "refusing to clone into non-empty non-checkout directory: $CONFIG_TARGET_DIR"
    fi

    ensure_git_for_clone "$platform"
    if (( DRY_RUN )); then
        print_command git clone "$REPO_SSH_URL" "$CONFIG_TARGET_DIR"
        print_command /usr/bin/env bash "$child_setup" --dry-run
        return 0
    fi

    git clone "$REPO_SSH_URL" "$CONFIG_TARGET_DIR"
    [[ -r "$child_setup" ]] || die "clone did not contain setup.sh: $child_setup"
    exec /usr/bin/env bash "$child_setup"
}

init_git_info() {
    local git_name git_email configure_defaults=0
    git_name="$(git config --global --get user.name 2>/dev/null || true)"
    git_email="$(git config --global --get user.email 2>/dev/null || true)"

    if [[ -z "$git_name" ]]; then
        read -r -p '请输入 Git 用户名 [默认: MarlinL]: ' git_name
        git_name="${git_name:-MarlinL}"
        git config --global user.name "$git_name"
        configure_defaults=1
    fi

    if [[ -z "$git_email" ]]; then
        read -r -p '请输入 Git 邮箱: ' git_email
        [[ -n "$git_email" ]] || die 'Git 邮箱不能为空'
        git config --global user.email "$git_email"
    fi

    (( configure_defaults )) || return 0
    git config --global init.defaultBranch master
    git config --global core.quotepath false
    git config --global core.autocrlf input
    git config --global pull.rebase true
    git config --global core.fsmonitor true
}

run_install() {
    local platform="$1"

    if (( DRY_RUN )); then
        plan_install "$platform"
        return 0
    fi

    if [[ "$platform" == macos ]]; then
        install_macos_packages
    else
        install_debian_packages
    fi

    require_weave
    link_file "$CONFIG_DIR/zsh/zprofile" "$HOME/.zprofile"
    link_file "$CONFIG_DIR/.vimrc" "$HOME/.vimrc"
    render_live_zshrc "$platform"

    if [[ "$platform" == macos ]]; then
        install_macos_service
    else
        install_debian_service
    fi

    init_git_info
    printf '✅ 初始化完成。请重新打开终端以加载新的 ~/.zshrc。\n'
}

main() {
    local platform test_dir=''

    if (( $# == 0 )) && [[ "$0" == '--dry-run' ]]; then
        set -- --dry-run
    fi

    while (( $# > 0 )); do
        case "$1" in
            --dry-run)
                DRY_RUN=1
                ;;
            --test)
                [[ -z "$test_dir" && $# -ge 2 ]] || die 'Usage: ./setup.sh --test <directory>'
                test_dir="$2"
                shift
                ;;
            --help|-h)
                usage
                return 0
                ;;
            *)
                die "unknown option: $1"
                ;;
        esac
        shift
    done

    [[ "$DRY_RUN" == 0 || -z "$test_dir" ]] || die '--dry-run cannot be combined with --test'
    platform="$(detect_os)"

    if ! is_config_checkout; then
        [[ -z "$test_dir" ]] || die '--test requires an existing ~/.config checkout'
        clone_and_install "$platform"
    elif [[ -n "$test_dir" ]]; then
        run_test "$platform" "$test_dir"
    else
        run_install "$platform"
    fi
}

main "$@"
