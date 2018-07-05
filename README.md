Rexec Library
===========================================================================

`librexec` is a small bash library whose purpose is to allow transparent execution of commands when the host on which the commands are to be executed may be either local or remote depending on runtime config.

The specific use-case for which it was designed was to handle command execution in my `timetraveler` incremental backup application. Since the user defines the destination of the backup to be either the local host or some remote host (accessible by ssh), I had to use an abstraction to execute commands that would allow me to do something like `rexec $PATH mkdir -p /some/dir` and have it run `mkdir -p /some/dir` either locally or on a remote host via ssh according to an analysis of `$PATH`. `rexec` was the library I came up with to handle a) figuring out whether the given path was local or remote; and b) composing the actual command and running it accordingly.

## API

`librexec` has the following functions:

### Error Functions

`exit_error_ssh [host]` -- Prints a standard SSH connection error and exits

### Path Functions

(These functions are designed to facilitate determining information about a given path, including whether or not the path, presumably defined by the user in a config file.)

`require_param_path [args]` -- checks the given arguments to make sure that there is exactly one parameter given (which is assumed to be a path, but is not verified in any way)

`path_is_remote [path]` -- determines whether or not the given path is remote

`path_exists [path]` -- checks to see whether the given remote or local path exists

### Command Delegater

`rexec [path] [command]` -- Runs command `[command]` either locally or remotely, depending on analysis of `[path]`. `[command]` may be a _pattern_ including the variables `::host::` and `::path::`, which are substituted for the given components of `[path]`.

For example, `rexec $backupPath "mkdir -p ::path::"` would result in the following commands:

* `ssh my-remote.com "mkdir -p /my/backup-dir"` when `$backupPath` is `my-remote.com:/my/backup-dir`
* `mkdir -p /my/backup-dir` when `$backupPath` is `/my/backup-dir`

