_codex_auth_restart_app_server() {
    if ! command -v pkill >/dev/null 2>&1; then
        print -u2 -- 'auth 已切换，但找不到 pkill；请手动重启 Codex app-server。'
        return 1
    fi

    # The Codex client owns its app-server child and starts it again when needed.
    pkill -u "$EUID" -f '(^|/)codex app-server([[:space:]]|$)' 2>/dev/null
    local result=$?
    if (( result > 1 )); then
        print -u2 -- 'auth 已切换，但停止 app-server 失败；请手动重启 Codex。'
        return 1
    fi
}

_codex_auth_is_managed_link() {
    local name="${1:t:r:r}"
    [[ "$name" =~ '^[A-Za-z0-9][A-Za-z0-9_-]*$' && "$1" == "$2/$name.auth.json" ]]
}

codex-auth() {
    emulate -L zsh

    local store="$HOME/.config/codex"
    local codex_home="${CODEX_HOME:-$HOME/.codex}"
    local auth="$codex_home/auth.json"
    local action="$1" name="$2" target legacy current file backup answer
    local importing=0

    if [[ "$action" == --help ]]; then
        if (( $# != 1 )); then
            print -u2 -- '用法: codex-auth --help'
            return 2
        fi
        print -r -l -- \
            '用法: codex-auth -l | -p <账户> | --new <账户> | -d <账户> | --help' \
            '' \
            '指令:' \
            '  -l            显示当前账户及可用的 auth 文件（包括旧目录中的文件）' \
            '  -p <账户>     切换到指定账户；首次选择时会将同名旧文件移入账户目录' \
            '  --new <账户>  新建待登录账户的软链；登录 Codex 后生成 auth 文件' \
            '  -d <账户>     删除指定账户文件；若为当前账户，同时移除软链' \
            '  --help        显示本说明' \
            '' \
            '账户名只允许字母、数字、下划线和短横线，且必须以字母或数字开头。' \
            '账户文件位于 ~/.config/codex/<账户>.auth.json。' \
            '当前凭据入口位于 CODEX_HOME/auth.json（默认 ~/.codex/auth.json）。' \
            'Codex 需使用文件型凭据存储（cli_auth_credentials_store = "file"）。' \
            '切换未托管的 auth.json 前会询问并备份；改变当前账户后会停止 app-server。'
        return 0
    fi

    if (( $# == 0 )) || (( $# > 2 )); then
        print -u2 -- '用法: codex-auth -l | -p <账户> | --new <账户> | -d <账户> | --help'
        return 2
    fi

    if [[ -L "$store" || ( -e "$store" && ! -d "$store" ) ]]; then
        print -u2 -- "账户目录不是普通目录: $store"
        return 1
    fi

    case "$action" in
        -l)
            if (( $# != 1 )); then
                print -u2 -- '用法: codex-auth -l'
                return 2
            fi
            if [[ -L "$auth" ]]; then
                current="$(readlink "$auth")"
                if _codex_auth_is_managed_link "$current" "$store"; then
                    name="${current:t:r:r}"
                    if [[ -f "$current" ]]; then
                        print -- "当前账户: $name"
                    else
                        print -- "当前账户: $name (待登录或文件缺失)"
                    fi
                else
                    print -- "当前账户: 未托管 (${current:t:r:r}) -> $current"
                fi
            elif [[ -f "$auth" ]]; then
                print -- "当前账户: 未托管 (普通文件: $auth)"
            else
                print -- '当前账户: 无'
            fi
            print -- "账户文件: $store"
            local count=0
            for file in "$store"/*.auth.json(N); do
                if [[ -f "$file" && ! -L "$file" ]]; then
                    print -- "  ${file:t:r:r}"
                    (( count++ ))
                fi
            done
            (( count )) || print -- '  (无)'
            local -a legacy_files
            legacy_files=("$codex_home"/*.auth.json(N))
            if (( ${#legacy_files} )); then
                print -- "旧位置账户文件: $codex_home"
                for file in "${legacy_files[@]}"; do
                    [[ -f "$file" && ! -L "$file" ]] && print -- "  ${file:t:r:r}"
                done
            fi
            return 0
            ;;
        -p|--new|-d)
            if (( $# != 2 )) || [[ ! "$name" =~ '^[A-Za-z0-9][A-Za-z0-9_-]*$' ]]; then
                print -u2 -- "账户名只允许字母、数字、下划线和短横线，且必须以字母或数字开头: $name"
                return 2
            fi
            ;;
        *)
            print -u2 -- '用法: codex-auth -l | -p <账户> | --new <账户> | -d <账户> | --help'
            return 2
            ;;
    esac

    target="$store/$name.auth.json"
    legacy="$codex_home/$name.auth.json"
    if [[ "$action" == --new ]]; then
        if [[ -e "$target" || -L "$target" || -e "$legacy" || -L "$legacy" ]]; then
            print -u2 -- "账户已存在: $name"
            return 1
        fi
        if [[ ! -d "$store" ]]; then
            ( umask 077; mkdir -m 700 -p "$store" ) || return 1
        fi
    elif [[ "$action" == -p && ! -e "$target" && ! -L "$target" && -f "$legacy" && ! -L "$legacy" ]]; then
        importing=1
        if [[ ! -d "$store" ]]; then
            ( umask 077; mkdir -m 700 -p "$store" ) || return 1
        fi
    elif [[ "$action" == -p && ( ! -f "$target" || -L "$target" ) ]] ||
         [[ "$action" == -d && ( -L "$target" || ( -e "$target" && ! -f "$target" ) ) ]]; then
        print -u2 -- "账户文件不存在或不是普通文件: $target"
        return 1
    fi

    if [[ "$action" == -d ]]; then
        if [[ -L "$auth" && "$(readlink "$auth")" == "$target" ]]; then
            rm -- "$auth" || return 1
            if [[ -e "$target" ]] && ! rm -- "$target"; then
                ln -s -- "$target" "$auth"
                return 1
            fi
            print -- "已删除当前账户: $name"
            _codex_auth_restart_app_server
        else
            if [[ ! -e "$target" ]]; then
                print -u2 -- "账户不存在: $name"
                return 1
            fi
            rm -- "$target" || return 1
            print -- "已删除账户: $name"
        fi
        return $?
    fi

    if [[ ! -d "$codex_home" ]]; then
        ( umask 077; mkdir -m 700 -p "$codex_home" ) || return 1
    fi

    if [[ -L "$auth" && "$(readlink "$auth")" == "$target" ]]; then
        print -- "当前已是账户: $name"
        return 0
    fi

    if [[ -e "$auth" || -L "$auth" ]]; then
        if [[ ! -L "$auth" ]] || ! _codex_auth_is_managed_link "$(readlink "$auth")" "$store"; then
            print -u2 -- "现有 auth.json 未由 codex-auth 管理: $auth"
            print -n -u2 -- '将它备份后切换？[y/N] '
            read -r answer || return 1
            if [[ "$answer" != [yY] ]]; then
                print -u2 -- '已取消切换。'
                return 1
            fi
            backup="$auth.backup.$(date +%Y%m%d%H%M%S).$$"
            if [[ -e "$backup" || -L "$backup" ]]; then
                print -u2 -- "备份路径已存在: $backup"
                return 1
            fi
            mv -- "$auth" "$backup" || return 1
        else
            current="$(readlink "$auth")"
            rm -- "$auth" || return 1
        fi
    fi

    if (( importing )); then
        if ! mv -n -- "$legacy" "$target" || [[ -e "$legacy" ]] || ! chmod 600 "$target"; then
            [[ ! -e "$legacy" && -f "$target" ]] && mv -n -- "$target" "$legacy"
            if [[ -n "$backup" ]]; then
                mv -- "$backup" "$auth"
            elif [[ -n "$current" ]]; then
                ln -s -- "$current" "$auth"
            fi
            print -u2 -- "移动旧账户文件失败: $legacy"
            return 1
        fi
    fi

    if ! ln -s -- "$target" "$auth"; then
        (( importing )) && mv -n -- "$target" "$legacy"
        if [[ -n "$backup" ]]; then
            mv -- "$backup" "$auth"
        elif [[ -n "$current" ]]; then
            ln -s -- "$current" "$auth"
        fi
        return 1
    fi

    print -- "已切换到: $name"
    (( importing )) && print -- "旧账户文件已移入: $target"
    [[ -n "$backup" ]] && print -- "原 auth.json 已备份至: $backup"
    _codex_auth_restart_app_server
}
