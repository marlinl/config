# Parse machine defaults as configuration data before loading shared settings.
if [[ -r "$HOME/config/.env" ]]; then
    # Read single-line dotenv assignments without executing or expanding values.
    () {
        local _dotenv_line _dotenv_key _dotenv_value MATCH MBEGIN MEND
        local -a match mbegin mend
        local _dotenv_newline=$'\n' _dotenv_carriage_return=$'\r'
        while IFS= read -r _dotenv_line || [[ -n "$_dotenv_line" ]]; do
            _dotenv_line="${_dotenv_line%$'\r'}"
            [[ "$_dotenv_line" == *=* ]] || continue
            _dotenv_key="${_dotenv_line%%=*}"
            _dotenv_key="${_dotenv_key#"${_dotenv_key%%[![:space:]]*}"}"
            _dotenv_key="${_dotenv_key%"${_dotenv_key##*[![:space:]]}"}"
            [[ "$_dotenv_key" == [A-Za-z_]* && "$_dotenv_key" != *[^A-Za-z0-9_]* ]] || continue
            _dotenv_value="${_dotenv_line#*=}"
            _dotenv_value="${_dotenv_value#"${_dotenv_value%%[![:space:]]*}"}"
            _dotenv_value="${_dotenv_value%"${_dotenv_value##*[![:space:]]}"}"
            if [[ "$_dotenv_value" == \"* ]]; then
                [[ "$_dotenv_value" =~ '^"((\\"|[^"])*)"[[:space:]]*(#.*)?$' ]] || continue
                _dotenv_value="${match[1]}"
                _dotenv_value="${_dotenv_value//\\n/$_dotenv_newline}"
                _dotenv_value="${_dotenv_value//\\r/$_dotenv_carriage_return}"
            elif [[ "$_dotenv_value" == \'* ]]; then
                [[ "$_dotenv_value" =~ "^'((\\\\'|[^'])*)'[[:space:]]*(#.*)?$" ]] || continue
                _dotenv_value="${match[1]}"
            else
                _dotenv_value="${_dotenv_value%%\#*}"
                _dotenv_value="${_dotenv_value%"${_dotenv_value##*[![:space:]]}"}"
            fi
            typeset -gx -- "$_dotenv_key=$_dotenv_value"
        done < "$HOME/config/.env"
    }
fi

echo "Keep simple. Keep stupid. Keep hungry."

# 补全
autoload -Uz compinit && compinit
# 自动加载所有插件
for f in ~/.config/zsh-plugin/*.zsh(N); do source "$f"; done
