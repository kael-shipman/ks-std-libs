#!/bin/bash

set -e

function place_files() {
    local pkgname="$1"
    local targdir="$2"
    cp -R src/* "$targdir/"
}

# Include the library and go
if [ -z "$KSUTILS_PATH" ]; then 
    KSUTILS_PATH=/usr/lib/ks-std-libs
fi
if [ ! -e "$KSUTILS_PATH/libdebpkgbuilder.sh" ]; then
    >&2 echo
    >&2 echo "E: Your system doesn't appear to have ks-std-libs installed. (Looking for"
    >&2 echo "   library 'libdebpkgbuilder.sh' in $KSUTILS_PATH. To define a different"
    >&2 echo "   place to look for this file, just export the 'KSUTILS_PATH' environment"
    >&2 echo "   variable.)"
    >&2 echo
    exit 4
else
    . "$KSUTILS_PATH/libdebpkgbuilder.sh"
    build
fi

