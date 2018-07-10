#!/bin/bash

inc="src/usr/lib/ks-std-libs/librexec.sh"
if [ ! -e "$inc" ]; then
    inc="../$inc"
    if [ ! -e "$inc" ]; then
        >&2 echo
        >&2 echo "E: Can't find library \`librexec.sh\`. Please run this command from repo root"
        >&2 echo
        exit 1
    fi
fi

. "$inc"

# Set config variables, then override if possible

TT_TEST_REMOTE_HOST=kaelshipman.me
TT_TEST_REMOTE_PATH_IN_HOME=.profile

test_path_is_remote_handles_normal_paths() {
    local path

    # local path
    path="/some/crazy:delim/localpath"
    assert_status_code 1 'path_is_remote "'$path'"' "Local path '$path' should be identified as local"

    # remote path
    path="kael@kaelshipman.me:/some/path"
    assert_status_code 0 'path_is_remote "'$path'"' "Remote path '$path' should be identified as remote"
}

test_path_is_remote_handles_paths_with_spaces() {
    local path
    local cmd

    # local path
    path="/some/crazy:delim/localpath/with spaces"
    cmd="path_is_remote '"$path"'"
    assert_status_code 1 'path_is_remote "'$path'"' "Local path '$path' should be identified as local"

    # remote path
    path="kael@kaelshipman.me:/some/path with spaces"
    cmd="path_is_remote '"$path"'"
    assert_status_code 0 "$cmd" "Remote path '$path' should be identified as remote"
}

todo_test_path_is_remote_handles_paths_with_special_chars() {
    local path
    local cmd

    # local
    path="/some/path with spaces/& some/'special!' "'"'"chars"'"'"/path"
    cmd="path_is_remote '"$(echo "$path" | sed "s/'/'"'"'"'"'"'"'/g")"'"
    assert_status_code 1 "$cmd" "Local path '$path' should be identified as local"

    # remote
    path="kael@kaelshipman.me:/some/path with spaces/& some/'special!' "'"'"chars"'"'"/path"
    cmd="path_is_remote '"$(echo "$path" | sed "s/'/'"'"'"'"'"'"'/g")"'"
    assert_status_code 0 "$cmd" "Remote path '$path' should be identified as remote"
}

test_path_is_remote_complains_with_bad_arguments() {
    assert_status_code 26 "path_is_remote '/this is a/path/with/spaces' 'but this is just a string'" "Should have complained for multiple arguments"
    assert_status_code 26 "path_is_remote" "Should have complained with no arguments"
}

test_path_exists_with_valid_paths() {
    assert_status_code 0 "path_exists '/tmp'"
    assert_status_code 0 "path_exists '$TT_TEST_REMOTE_HOST:/tmp'"
    assert_status_code 0 "path_exists '$TT_TEST_REMOTE_HOST:$TT_TEST_REMOTE_PATH_IN_HOME'"
}

test_path_exists_with_nonexistent_paths() {
    assert_status_code 1 "path_exists '/bunk'"
    assert_status_code 1 "path_exists '$TT_TEST_REMOTE_HOST:/bunk'"
    assert_status_code 1 "path_exists '$TT_TEST_REMOTE_HOST:bunk'"
}

test_path_exists_with_paths_with_spaces() {
    local path="/tmp/path with spaces/here"

    mkdir -p "$path"
    assert_status_code 0 "path_exists '$path'"
    rm -Rf "$path"

    ssh "$TT_TEST_REMOTE_HOST" 'mkdir -p "'$path'"'
    assert_status_code 0 "path_exists '$TT_TEST_REMOTE_HOST:$path'"
    ssh "$TT_TEST_REMOTE_HOST" 'rm -Rf "'$path'"'
}

test_path_exists_with_bad_arguments() {
    assert_status_code 26 "path_exists '/this is a/path/with/spaces' 'but this is just a string'" "Should have complained for multiple arguments"
    assert_status_code 26 "path_exists" "Should have complained with no arguments"
}

todo_test_path_exists_with_special_chars() {
    local path="/some/path with spaces/& some/'special!' "'"'"chars"'"'"/path"
    local cmd

    # local
    mkdir -p "$path"
    cmd="path_exists '"$(echo "$path" | sed "s/'/'"'"'"'"'"'"'/g")"'"
    assert_status_code 0 "$cmd"

    # remote
    ssh "$TT_TEST_REMOTE_HOST" 'mkdir -p "'$path'"'
    assert_status_code 0 "path_exists '$TT_TEST_REMOTE_HOST:$(echo "$path" | sed "s/'/'"'"'"'"'"'"'/g")'"
    ssh "$TT_TEST_REMOTE_HOST" 'rm -Rf "'$path'"'
}

test_rexec_can_make_normal_dirs() {
    local path="/tmp/some/long/path"

    rexec "$path" 'mkdir -p "::path::"'
    assert "test -e '$path'"
    rm -Rf /tmp/some

    local remoteAddr="$TT_TEST_REMOTE_HOST:$path"
    rexec "$remoteAddr" 'mkdir -p "::path::"'
    assert "ssh '$TT_TEST_REMOTE_HOST' 'test -e "'"'"$path"'"'"'"
    ssh "$TT_TEST_REMOTE_HOST" "rm -Rf '/tmp/some'"
}

test_rexec_can_make_dirs_with_spaces() {
    local path="/tmp/some/long path with/some spaces"

    rexec "$path" 'mkdir -p "::path::"'
    assert "test -e '$path'"
    rm -Rf /tmp/some

    local remoteAddr="$TT_TEST_REMOTE_HOST:$path"
    rexec "$remoteAddr" 'mkdir -p "::path::"'
    assert "ssh '$TT_TEST_REMOTE_HOST' 'test -e "'"'"$path"'"'"'"
    ssh "$TT_TEST_REMOTE_HOST" "rm -Rf '/tmp/some'"
}

todo_test_rexec_can_make_dirs_with_special_chars() {
    assert_fail
}

test_rexec_can_move_normal_dirs() {
    local toPath="/tmp/test"
    local fromPath="$toPath.partial"

    # just in case...
    rexec "$toPath" 'rm -Rf "::path::"'

    rexec "$fromPath" 'mkdir -p "::path::"'
    rexec "$fromPath" 'mv "::path::" "'"$toPath"'"'
    assert 'path_exists "'"$toPath"'"'

    rexec "$toPath" 'rm -Rf "::path::"'

    # just in case...
    rexec "$TT_TEST_REMOTE_HOST:$toPath" 'rm -Rf "::path::"'

    rexec "$TT_TEST_REMOTE_HOST:$fromPath" 'mkdir -p "::path::"'
    rexec "$TT_TEST_REMOTE_HOST:$fromPath" 'mv "::path::" "'"$toPath"'"'
    assert 'path_exists "'"$TT_TEST_REMOTE_HOST:$toPath"'"'

    rexec "$TT_TEST_REMOTE_HOST:$toPath" 'rm -Rf "::path::"'
}

test_rexec_can_move_dirs_with_spaces() {
    local toPath="/tmp/test dir with/spaces"
    local fromPath="$toPath.partial"

    # just in case...
    rexec "$toPath" 'rm -Rf "::path::"'

    rexec "$fromPath" 'mkdir -p "::path::"'
    rexec "$fromPath" 'mv "::path::" "'"$toPath"'"'
    assert 'path_exists "'"$toPath"'"'

    rexec "$toPath" 'rm -Rf "::path::"'

    # just in case...
    rexec "$TT_TEST_REMOTE_HOST:$toPath" 'rm -Rf "::path::"'

    rexec "$TT_TEST_REMOTE_HOST:$fromPath" 'mkdir -p "::path::"'
    rexec "$TT_TEST_REMOTE_HOST:$fromPath" 'mv "::path::" "'"$toPath"'"'
    assert 'path_exists "'"$TT_TEST_REMOTE_HOST:$toPath"'"'

    rexec "$TT_TEST_REMOTE_HOST:$toPath" 'rm -Rf "::path::"'
}

todo_test_rexec_can_move_dirs_with_special_chars() {
    assert_fail
}

