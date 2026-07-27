load_config_env() {
    (( $# == 1 )) || return 1

    local env_file="$1"

    [[ -f "$env_file" && -r "$env_file" ]] || return 0

    setopt local_options allexport
    source "$env_file"
}
