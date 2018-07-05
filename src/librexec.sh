# Error functions

function exit_error_ssh() {
    >&2 echo
    >&2 echo "E: Can't connect to ssh via host: $1"
    >&2 echo
    exit 22
}





# Path functions

function require_param_path() {
    local err=
    if [ -z "$1" ]; then
        err="You must pass a path as the only argument to this function."
    elif [ -n "$2" ]; then
        err="This function expects exactly ONE argument, which is the path to check."
    fi
    if [ -n "$err" ]; then
        >&2 echo
        >&2 echo "E: $err"
        >&2 echo
        exit 26
    fi
}

function path_is_remote() {
    require_param_path "$@"
    local path="$1"
    echo "$path" | egrep -c "^[^/]+:.+$" &>/dev/null
}

function path_exists() {
    require_param_path "$@"
    local path="$1"

    if path_is_remote "$path"; then
        local host="$(echo "$path" | sed -r "s/^([^:]+).*$/\1/")"
        path="$(echo "$path" | sed -r "s/^[^:]+:(.+)$/\1/")"
        # TODO: Handle tildes here
        if ssh "$host" 'test -e "'$path'"'; then
            return 0
        else
            # If it exited 255, that's a connection error
            if [ "$?" -eq 255 ]; then
                exit_error_ssh "$host"

            # Otherwise, the path doesn't exist
            else
                return 1
            fi
        fi
    else
        test -e "$path"
    fi
}






# Command delegater

function rexec() {
    local path="$1"
    local cmd="$2"
    if [ -z "$path" ]; then
        >&2 echo
        >&2 echo "E: You must supply a path to analyze as the first argument to this function."
        >&2 echo
        exit 27
    fi
    if [ -z "$cmd" ]; then
        >&2 echo
        >&2 echo "E: You must supply a command to run as the second argument to this function."
        >&2 echo "   You may enter '::path::' anywhere in this command and that will be substituted"
        >&2 echo "   with the final path (local or remote) as derived by the first argument. '::host::'"
        >&2 echo "   is also available."
        >&2 echo
        exit 28
    fi
    if [ -n "$3" ]; then
        >&2 echo
        >&2 echo "E: You've supplied too many arguments to this function."
        >&2 echo
        exit 29
    fi

    if path_is_remote "$path"; then
        local host="$(echo "$path" | sed -r "s/^([^:]+).*$/\1/")"
        path="$(echo "$path" | sed -r "s/^[^:]+:(.+)$/\1/")"
        # TODO: Handle tildes here
        cmd="$(echo "$cmd" | sed "s^::path::^$path^g" | sed "s^::host::^$host^g")"
        if ! ssh "$host" "$cmd"; then
            if [ "$?" == 255 ]; then
                exit_error_ssh "$host"
            else
                >&2 echo
                >&2 echo "E: Couldn't execute command '$cmd' on host '$host'"
                >&2 echo
                exit 30
            fi
        fi
    else
        cmd="$(echo "$cmd" | sed "s^::path::^$path^g")"
        eval $cmd
    fi
}

