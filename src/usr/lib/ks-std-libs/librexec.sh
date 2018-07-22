##
# librexec defines a few functions that are useful in running a command EITHER locally
# or remotely, where the actual host on which the command is run is not known at the time
# of the call.
#
# This situation arises, for example, when creating filesystem backups whose targets or sources
# may either be local or remote, depending on some user-defined runtime configuration.
#
# librexec works by defining a "path" as a combination of hostname and filesystem path. For local
# paths, the hostname will not be present. For remote paths, the hostname will be separated
# from the path by a colon, as is common in ssh-related utilities like rsync and scp. rexec can
# then determine from a single "path" string 1) whether the command is local or remote; 2)
# how to log into the host, if necessary; and 3) the desired path location.
#
# Important to note is that librexec requires proper SSH configuration, since it uses
# ssh for its underlying implementation. This is considered a feature, since it moves complicated
# permissioning setup to the well-known domain of ssh and the unix filesystem at large.
#
# To use librexec, you'll typically do things like this:
#
# mysrc=my-host.com:/home/me/my-files/new-path
# mydest=/home/me/my-files/new-path
# rexec "$mysrc" "mkdir -p '::path::'"
# rexec "$mydest" "mkdir -p '::path::'"
#
# In this case, we've just ensured that the path '/home/me/my-files/new-path' exists both
# locally and at the remote 'my-host.com'. This is a common use-case for rexec, though is by
# no means the only use-case.
#
# Read individual function documentation for more information on each.
##




# Utility functions

##
# Utility function for echoing a consistent ssh error
#
# (no params)
#
function exit_error_ssh() {
    >&2 echo
    >&2 echo "E: Can't connect to ssh via host: $1"
    >&2 echo
    exit 22
}

##
# Utility function for ensuring that 'path' is the only parameter passed to a given function
#
# This function simply serves to save on copy/pasted code.
#
# @params "$@" All that were params passed to the calling function
# @return 0|26 0 if the arguments contained a single argument, path; 26 if they contained more
# or fewer arguments
##
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





# Shortcut functions

##
# Determines wether the given path is remote by checking to see if it has a colon in it
#
# @param string $path The path to check
# @return 0|1
# @output 0|1
##
function path_is_remote() {
    require_param_path "$@"
    local path="$1"
    echo "$path" | egrep -c "^[^/]+:.+$" &>/dev/null
}

##
# Determines whether the given path exists
#
# @param string $path The path to check
# @return 0|1
##
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

##
# Executes $cmd on whatever host is determined from $path, optionally substituting variables '::host::' and
# '::path::' for their respective values as parsed from $path.
#
# For example, if `msg="Hello from host ::host:: and path ::path::!"`, then
# `rexec my-host.com:/home/me "echo '$msg'"` would result in 'Hello from host my-host.com and path /home/me!'
# being printed to stdout, while `rexec /home/me "echo '$msg'"` would result in 'Hello from host  and path /home/me!'
# being printed to stdout.
#
# @param string $path The full path with host prefix (if applicable) to use as a foundation for the command to be executed.
# @param string $cmd The command to be executed, with optional ::host:: and ::path:: variable substitutions.
# @return mixted Whatever $cmd returns
##
function rexec() {
    # Get options first (accepts several passthrough options for SSH)
    OPTIND=0
    local SSHOPTS=()
    local opt=
    while getopts "tni:o:" opt; do
        SSHOPTS+=("-$opt")
        if [ "$OPTARG" ]; then
            SSHOPTS+=("$OPTARG")
        fi
    done
    shift $((OPTIND-1))
    OPTIND=0

    # Now assign and validate parameters
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
        if ssh ${SSHOPTS[@]} "$host" "$cmd"; then
            return
        else
            RET="$?"
            if [ "$RET" == 255 ]; then
                exit_error_ssh "$host"
            else
                return "$RET"
            fi
        fi
    else
        cmd="$(echo "$cmd" | sed "s^::path::^$path^g")"
        eval $cmd
    fi
}

