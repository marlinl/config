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

_mycodex_prepare_home() {
    emulate -L zsh

    local shared="${1:A}" account_home="${2:a}" account_auth="$3"
    local entry source_path destination
    local -a entries directories
    directories=(sessions archived_sessions log skills plugins rules memories memories_v2
                 shell_snapshots generated_images state thread-writer-locks)
    entries=(config.toml .env AGENTS.md history.jsonl session_index.jsonl "${directories[@]}")

    if [[ ! -d "$shared" || "$shared" == "$account_home" ||
          "$shared" == "$account_home/"* || "$account_home" == "$shared/"* ]]; then
        print -u2 -- "共享 Codex 目录不存在或与账户目录重叠: $shared"
        return 1
    fi
    if [[ -L "$account_home" || ( -e "$account_home" && ! -d "$account_home" ) ]]; then
        print -u2 -- "账户运行目录不是普通目录: $account_home"
        return 1
    fi
    if [[ -d "$account_home" && ! -L "$account_home/auth.json" ]]; then
        local -a existing=("$account_home"/*(DN))
        if (( ${#existing} )); then
            print -u2 -- "账户运行目录已有内容且未由 mycodex 管理，请先检查: $account_home"
            return 1
        fi
    fi

    for source_path in "$shared"/*(DN); do
        entry="${source_path:t}"
        case "$entry" in
            auth.json|auth.json.*|*.auth.json|auth.sh|app-server-*|ipc|tmp|.tmp|process_manager|\
            *.sock|*.socket|*.pid|*.sqlite|*.sqlite-*|*.sqlite3|*.sqlite3-*|.DS_Store|*.tmp-*)
                continue ;;
        esac
        [[ -f "$source_path" || -d "$source_path" || -L "$source_path" ]] && entries+=("$entry")
    done
    entries=("${(@u)entries}")

    # Check every destination before making changes; never replace local records.
    for entry in auth.json "${entries[@]}"; do
        source_path="$shared/$entry"
        [[ "$entry" == auth.json ]] && source_path="$account_auth"
        destination="$account_home/$entry"
        if [[ -e "$destination" || -L "$destination" ]]; then
            if [[ ! -L "$destination" || "$(readlink "$destination")" != "$source_path" ]]; then
                print -u2 -- "账户目录条目与共享链接冲突，请先检查: $destination"
                return 1
            fi
        fi
    done
    for entry in "${directories[@]}"; do
        if [[ ( -e "$shared/$entry" || -L "$shared/$entry" ) && ! -d "$shared/$entry" ]]; then
            print -u2 -- "共享条目不是目录: $shared/$entry"
            return 1
        fi
    done

    ( umask 077; mkdir -p -- "$account_home" "${(@)directories/#/$shared/}" ) || return 1
    for entry in auth.json "${entries[@]}"; do
        source_path="$shared/$entry"
        [[ "$entry" == auth.json ]] && source_path="$account_auth"
        destination="$account_home/$entry"
        if [[ ! -L "$destination" ]]; then
            # A concurrent launch may have created the same link after preflight.
            ln -s -- "$source_path" "$destination" 2>/dev/null ||
                [[ -L "$destination" && "$(readlink "$destination")" == "$source_path" ]] || return 1
        fi
    done
}

mycodex() {
    emulate -L zsh

    local store="$HOME/.config/codex"
    local codex_home="${CODEX_HOME:-$HOME/.codex}"
    local auth="$codex_home/auth.json"
    local action="$1" name="$2" target legacy current file backup answer
    local importing=0
    local -a codex_args=()

    if [[ "$action" == --help ]]; then
        if (( $# != 1 )); then
            print -u2 -- '用法: mycodex --help'
            return 2
        fi
        print -r -l -- \
            '用法: mycodex info | set <账户> | new <账户> | delete <账户> | codex [Codex 参数] -auth <账户> | --help' \
            '' \
            '指令:' \
            '  info          显示当前账户、可用账户及运行目录关联' \
            '  set <账户>    切换默认账户' \
            '  new <账户>    新建待登录账户的软链；登录 Codex 后生成 auth 文件' \
            '  delete <账户> 删除指定账户文件；若为当前账户，同时移除软链' \
            '  codex ... -auth <账户>  使用指定账户运行 Codex，其余参数原样转发' \
            '  --help        显示本说明' \
            '' \
            '账户名只允许字母、数字、下划线和短横线，且必须以字母或数字开头。' \
            '账户文件位于 ~/.config/codex/<账户>.auth.json。' \
            '默认账户入口位于 CODEX_HOME/auth.json（默认 ~/.codex/auth.json）。' \
            '' \
            '运行 Codex:' \
            '示例: mycodex codex -auth marlinl；mycodex codex resume <id> -auth marlinl。' \
            '-auth <账户> 可放在 Codex 参数前后；必须在 -- 之前且只能指定一次。' \
            'Codex 自身的配置 profile 可使用 -p 或 --profile；-- 后的参数保持原样。' \
            '指定账户必须已有账户文件；可在不同终端同时运行，不改变默认账户。' \
            '配置、插件和会话记录与原 Codex 目录共享。' \
            '以 --no-daemon 模式运行；agents 和 --remote 与该模式不兼容。' \
            '支持 ChatGPT 和 API key 文件账户；启动时清空认证环境覆盖。' \
            '' \
            '账户管理:' \
            'Codex 需使用文件型凭据存储（cli_auth_credentials_store = "file"）。' \
            'set 可将 CODEX_HOME/<账户>.auth.json 导入账户目录。' \
            '切换未托管的 auth.json 前会询问并备份；改变默认账户后会停止 app-server。' \
            '删除账户前请先退出使用该账户的 CLI 会话。'
        return 0
    fi

    if [[ "$action" == codex ]]; then
        name=''
        shift
        while (( $# )); do
            case "$1" in
                -auth)
                    if [[ -n "$name" ]] || (( $# < 2 )) || [[ ! "$2" =~ '^[A-Za-z0-9][A-Za-z0-9_-]*$' ]]; then
                        print -u2 -- '用法: mycodex codex [Codex 参数] -auth <账户>；账户必须合法且只能指定一次。'
                        return 2
                    fi
                    name="$2"
                    shift 2
                    ;;
                --)
                    codex_args+=("$@")
                    break
                    ;;
                *)
                    codex_args+=("$1")
                    shift
                    ;;
            esac
        done
        if [[ -z "$name" ]]; then
            print -u2 -- '用法: mycodex codex [Codex 参数] -auth <账户>；-auth 必须在 -- 之前。'
            return 2
        fi
    elif (( $# == 0 )) || (( $# > 2 )); then
        print -u2 -- '用法: mycodex info | set <账户> | new <账户> | delete <账户> | codex [Codex 参数] -auth <账户> | --help'
        return 2
    fi

    if [[ -L "$store" || ( -e "$store" && ! -d "$store" ) ]]; then
        print -u2 -- "账户目录不是普通目录: $store"
        return 1
    fi

    case "$action" in
        info)
            if (( $# != 1 )); then
                print -u2 -- '用法: mycodex info'
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
            local -a accounts=()
            for file in "$store"/*.auth.json(N); do
                if [[ -f "$file" && ! -L "$file" ]]; then
                    print -- "  ${file:t:r:r}"
                    accounts+=("${file:t:r:r}")
                    (( count++ ))
                fi
            done
            (( count )) || print -- '  (无)'

            print -r -- "共享目录（启动来源）: ${codex_home:A}"
            print -r -- "数据库目录（CODEX_SQLITE_HOME）: ${CODEX_SQLITE_HOME:-${codex_home:A}}"
            print -- '  若配置了 sqlite_home，以该配置为准。'
            print -- '运行目录关联（现有条目）:'
            local runtime_home entry link_target
            for name in "${accounts[@]}"; do
                runtime_home="$store/$name"
                print -r -- "  $name: $runtime_home"
                if [[ -L "$runtime_home" || ( -e "$runtime_home" && ! -d "$runtime_home" ) ]]; then
                    print -- '    路径冲突：运行目录必须是普通目录'
                    continue
                elif [[ ! -d "$runtime_home" ]]; then
                    print -- '    尚未初始化；首次运行 mycodex codex 时创建关联'
                    continue
                fi
                local -a runtime_entries=("$runtime_home"/*(DN))
                (( ${#runtime_entries} )) || print -- '    (空目录)'
                for entry in "${runtime_entries[@]}"; do
                    if [[ -L "$entry" ]]; then
                        link_target="$(readlink "$entry")"
                        if [[ -e "$entry" ]]; then
                            print -r -- "    ${entry:t} -> $link_target"
                        else
                            print -r -- "    ${entry:t} -> $link_target (目标不存在)"
                        fi
                    elif [[ -d "$entry" ]]; then
                        print -r -- "    ${entry:t}/ (账户本地目录)"
                    else
                        print -r -- "    ${entry:t} (账户本地文件)"
                    fi
                done
            done
            (( ${#accounts} )) || print -- '  (无可用账户)'
            return 0
            ;;
        codex)
            ;;
        set|new|delete)
            if (( $# != 2 )) || [[ ! "$name" =~ '^[A-Za-z0-9][A-Za-z0-9_-]*$' ]]; then
                print -u2 -- "账户名只允许字母、数字、下划线和短横线，且必须以字母或数字开头: $name"
                return 2
            fi
            ;;
        *)
            print -u2 -- '用法: mycodex info | set <账户> | new <账户> | delete <账户> | codex [Codex 参数] -auth <账户> | --help'
            return 2
            ;;
    esac

    target="$store/$name.auth.json"
    if [[ "$action" == codex ]]; then
        if [[ ! -f "$target" || -L "$target" ]]; then
            print -u2 -- "账户文件不存在或不是普通文件: $target"
            return 1
        fi
        if ! command -v codex >/dev/null 2>&1; then
            print -u2 -- '找不到 codex，请先安装 Codex CLI。'
            return 1
        fi

        local account_home="$store/$name"
        _mycodex_prepare_home "$codex_home" "$account_home" "$target" || return 1
        print -u2 -- "使用账户 $name 启动 Codex CLI"
        CODEX_HOME="$account_home" CODEX_SQLITE_HOME="${CODEX_SQLITE_HOME:-${codex_home:A}}" \
            OPENAI_API_KEY='' CODEX_API_KEY='' CODEX_ACCESS_TOKEN='' \
            command codex --no-daemon -c 'cli_auth_credentials_store="file"' "${codex_args[@]}"
        return $?
    fi

    legacy="$codex_home/$name.auth.json"
    if [[ "$action" == new ]]; then
        if [[ -e "$target" || -L "$target" || -e "$legacy" || -L "$legacy" ]]; then
            print -u2 -- "账户已存在: $name"
            return 1
        fi
        if [[ ! -d "$store" ]]; then
            ( umask 077; mkdir -m 700 -p "$store" ) || return 1
        fi
    elif [[ "$action" == set && ! -e "$target" && ! -L "$target" && -f "$legacy" && ! -L "$legacy" ]]; then
        importing=1
        if [[ ! -d "$store" ]]; then
            ( umask 077; mkdir -m 700 -p "$store" ) || return 1
        fi
    elif [[ "$action" == set && ( ! -f "$target" || -L "$target" ) ]] ||
         [[ "$action" == delete && ( -L "$target" || ( -e "$target" && ! -f "$target" ) ) ]]; then
        print -u2 -- "账户文件不存在或不是普通文件: $target"
        return 1
    fi

    if [[ "$action" == delete ]]; then
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
            print -u2 -- "现有 auth.json 未由 mycodex 管理: $auth"
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
