#!/bin/bash

set -e

function setup_env() {
    if [ "$(whoami)" != "root" ]; then
        >&2 echo
        >&2 echo "E: You must run this command with sudo so that package permissions"
        >&2 echo "   may be set accordingly."
        >&2 echo
        exit 1
    fi

    if [ ! -e "$KSUTILS_PATH/libksdpkg.sh" ]; then
        >&2 echo
        >&2 echo "E: Your system doesn't appear to have ks-std-libs installed. (Looking for"
        >&2 echo "   library 'ligksdpkg.sh' in $KSUTILS_PATH. To define a different"
        >&2 echo "   place to look for this file, just export the 'KSUTILS_PATH' environment"
        >&2 echo "   variable.)"
        >&2 echo
        exit 2
    else
        . "$KSUTILS_PATH/libksdpkg.sh"
    fi

    if ! command -v dpkg &>/dev/null; then
        >&2 echo
        >&2 echo "E: Your system doesn't appear to have dpkg installed. Dpkg is required"
        >&2 echo "   for creating debian packages."
        >&2 echo
        exit 3
    fi

    if [ -z "$builddir" ]; then
        builddir="build"
    fi
    if [ -z "$pkgsrcdir" ]; then
        pkgsrcdir="pkg-src"
    fi
    pkgtype=deb
}

function build_package() {
    local targdir="$1"
    local builddir="$2"
    ksdpkg_update_pkg_size "$targdir"
    ksdpkg_update_md5s "$targdir"
    dpkg --build "$targdir" "$builddir"
}


# Include the library and go
if [ -z "$KSUTILS_PATH" ]; then 
    KSUTILS_PATH=/usr/lib/ks-std-libs
fi
if [ ! -e "$KSUTILS_PATH/libpkgbuilder.sh" ]; then
    >&2 echo
    >&2 echo "E: Your system doesn't appear to have ks-std-libs installed. (Looking for"
    >&2 echo "   library 'libpkgbuilder.sh' in $KSUTILS_PATH. To define a different"
    >&2 echo "   place to look for this file, just export the 'KSUTILS_PATH' environment"
    >&2 echo "   variable.)"
    >&2 echo
    exit 4
else
    . "$KSUTILS_PATH/libpkgbuilder.sh"
fi


