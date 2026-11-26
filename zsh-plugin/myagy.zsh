# Open agy in the Orb machine at the current host directory.
myagy() {
    emulate -L zsh

    if [[ $# == 1 && ( "$1" == --help || "$1" == -h ) ]]; then
        print 'Usage: myagy'
        print 'Connect to SSH host agy, enter the current host directory, and run agy.'
        return 0
    fi
    if (( $# )); then
        print -u2 'Usage: myagy'
        return 64
    fi

    local remote_dir="/mnt/mac${PWD:A}"
    command ssh -t agy "cd -- ${(qq)remote_dir} && agy"
}
