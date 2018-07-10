#!/bin/bash

set -e

function setup_env() {
    setup_deb_env "$@"
}

function place_files() {
    local pkgname="$1"
    local targdir="$2"
    local pkgtype="$3"
    cp -R src/* "$targdir/"
}

function build_package() {
    local pkgtype="$1"
    shift

    if [ "$pkgtype" == "deb" ]; then
        build_deb_package "$@"
    else
        >&2 echo
        >&2 echo "E: Don't know how to build packages of type '$pkgtype'"
        >&2 echo
        exit 11
    fi
}

# Include the library and go
if [ -z "$KSSTDLIBS_PATH" ]; then 
    KSSTDLIBS_PATH=/usr/lib/ks-std-libs
fi
if [ ! -e "$KSSTDLIBS_PATH/libpkgbuilder.sh" ]; then
    >&2 echo
    >&2 echo "E: Your system doesn't appear to have ks-std-libs installed. (Looking for"
    >&2 echo "   library 'libpkgbuilder.sh' in $KSSTDLIBS_PATH. To define a different"
    >&2 echo "   place to look for this file, just export the 'KSSTDLIBS_PATH' environment"
    >&2 echo "   variable.)"
    >&2 echo
    exit 4
else
    . "$KSSTDLIBS_PATH/libpkgbuilder.sh"
    build
fi

