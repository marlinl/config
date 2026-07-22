var() {
    local mode="export" # 默认模式：导出为环境变量 (-gx)
    local is_func=false  # 是否将 value 作为函数执行

    # 1. 解析参数，支持组合如 -fg, -gf, -fl, -lf
    while [[ "$1" == -* ]]; do
        case "$1" in
            *f*) is_func=true ;;
        esac
        case "$1" in
            *g*) mode="global" ;;
            *l*) mode="local" ;;
        esac
        shift
    done

    # 2. 参数校验
    if [[ $# -lt 2 ]]; then
        echo "用法: var [-f] [-g | -l] 变量名 变量值"
        echo "  -f: 将变量值作为函数/命令执行，取其返回值"
        echo "  -g: 全局变量（不导出）"
        echo "  -l: 局部变量"
        echo "示例: var -fg PATH get_bin_dir"
        return 1
    fi

    local var_name="$1"
    shift
    local var_value="$*"

    # 3. 如果 -f，执行函数获取返回值
    if [[ "$is_func" == true ]]; then
        if ! type "$var_value" &>/dev/null; then
            echo "错误: '$var_value' 不是有效的函数或命令"
            return 1
        fi
        var_value=$("$var_value")
    fi

    # 4. 核心赋值逻辑
    case "$mode" in
        export)
            # 默认：导出到操作系统环境变量表，子进程可见
            export "${var_name}=${var_value}"
            ;;
        global)
            # -g：仅当前 Zsh 进程的全局变量，子进程不可见
            typeset -g "${var_name}=${var_value}"
            ;;
        local)
            # -l：当前函数内部的局部变量
            typeset "${var_name}=${var_value}"
            ;;
    esac
}
