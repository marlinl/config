# Open agy in the Orb machine at the current host directory.
myagy() {
    emulate -L zsh

    if [[ $# == 1 && ( "$1" == --help || "$1" == -h ) ]]; then
        print 'Usage: myagy [agy arguments...]'
        print 'Connect to SSH host agy, enter the current host directory, and run agy.'
        print 'Arguments are forwarded unchanged to the remote agy command.'
        return 0
    fi

    local remote_dir="/mnt/mac${PWD:A}"
    local remote_command="cd -- ${(qq)remote_dir} && agy" arg
    for arg in "$@"; do
        remote_command+=" ${(qq)arg}"
    done
    command ssh -t agy "$remote_command"
}
