jenv() {
    local db_file="$HOME/.config/.jenv_store"
    [[ -f "$db_file" ]] || touch "$db_file"

    # 1. 极速读取数据库到局部字典 (用完即毁，零常驻)
    local -A db
    while read -r k v; do
        [[ -n "$k" ]] && db[$k]="$v"
    done < "$db_file"

    local action="$1"
    local key="$2"
    local val="$3"
    local need_write=0

    # 2. 核心路由与校验
    case "$action" in
        list)
            echo "📦 当前记录的 Java 环境:"
            # 过滤掉特殊的 default 键，按首字母排序打印
            for k v in ${(kv)db}; do
                [[ "$k" != "default" ]] && echo "  🔸 $k -> $v"
            done | sort
            return 0
            ;;

        add)
            if [[ -z "$key" || -z "$val" ]]; then
                echo "❌ 用法: jenv add <key> <path>"
                return 1
            fi
            if [[ -n "${db[$key]}" || "$key" == "default" ]]; then
                echo "❌ 键名 [$key] 已存在或为保留字，禁止重复添加！"
                return 1
            fi
            
            db[$key]="$val"
            need_write=1
            echo "✅ 已添加: $key -> $val"
            ;;

        rm)
            if [[ -z "$key" || -z "${db[$key]}" ]]; then
                echo "❌ 键名 [$key] 不存在！"
                return 1
            fi
            # 核心防御：正在被设为 default 或正在被系统使用的版本，绝对不准删
            if [[ "${db[default]}" == "$key" || "$JAVA_HOME" == "${db[$key]}" ]]; then
                echo "❌ 禁止删除！"
                echo "   原因: [$key] 正被设为 default 或当前终端正在使用。"
                return 1
            fi
            
            unset "db[$key]"
            need_write=1
            echo "🗑️ 已删除: [$key]"
            ;;

        set)
            if [[ -z "$key" || -z "${db[$key]}" ]]; then
                echo "❌ 键名 [$key] 不存在！请先使用 jenv list 查看。"
                return 1
            fi

            # 内存中更新 default 值，并标记需要刷盘
            db[default]="$key"
            need_write=1

            # 动态剔除旧路径，置顶新路径，保持 PATH 极致干净
            if [[ -n "$JAVA_HOME" ]]; then
                path=(${path:#$JAVA_HOME/bin})
            fi
            export JAVA_HOME="${db[$key]}"
            path=("$JAVA_HOME/bin" $path)
            ;;

        info)
            echo "ℹ️  当前状态:"
            echo "  👉 default 键值: ${db[default]:-未设置}"
            echo "  👉 JAVA_HOME 路径: ${JAVA_HOME:-未设置}"
            echo "----------------------------------------"
            command -v java >/dev/null 2>&1 && java -version || echo "❌ 当前 PATH 中找不到 java 命令"
            return 0
            ;;

        *)
            echo "用法: jenv [list|add|rm|set|info] ..."
            return 0
            ;;
    esac

    # 3. 终极无痕刷盘保护 (Zsh always 魔法块)
    if [[ $need_write -eq 1 ]]; then
        local lock_dir="$HOME/.config/zsh-plugin/.jenv_write.lock.d"

        # 尝试抢占原子锁
        if ! mkdir "$lock_dir" 2>/dev/null; then
            echo "⏳ 写入冲突！另一个进程正在刷盘，请稍后重试。"
            return 1
        fi

        {
            # try 块：绝对安全地全量覆写数据库文件
            (
                for k v in ${(kv)db}; do
                    echo "$k $v"
                done
            ) > "$db_file"
            
        } always {
            # finally 块：无论刷盘是否成功、是否被打断，必然执行目录销毁
            # 绝不留一丝垃圾，无需配置 .gitignore
            rmdir "$lock_dir" 2>/dev/null
        }
    fi

    # 4. set 命令专属的最终核验打印
    if [[ "$action" == "set" ]]; then
        echo "✅ 切换成功！"
        echo "ℹ️  当前状态:"
        echo "  👉 default 键值: ${db[default]:-未设置}"
        echo "  👉 JAVA_HOME 路径: ${JAVA_HOME:-未设置}"
        echo "----------------------------------------"
        command -v java >/dev/null 2>&1 && java -version || echo "❌ 当前 PATH 中找不到 java 命令"
    fi
}

# ==========================================
# 🏠 获取默认 JAVA_HOME 路径 (供脚本调用)
# ==========================================
default_java_home() {
    local db_file="$HOME/.config/.jenv_store"
    [[ ! -f "$db_file" ]] && return 1

    local def_key def_path

    # 找 default 的 key
    while read -r k v; do
        [[ "$k" == "default" ]] && def_key="$v" && break
    done < "$db_file"

    [[ -z "$def_key" ]] && return 1

    # 根据 key 找真实路径
    while read -r k v; do
        [[ "$k" == "$def_key" ]] && def_path="$v" && break
    done < "$db_file"

    [[ -n "$def_path" ]] && echo "$def_path"
}
