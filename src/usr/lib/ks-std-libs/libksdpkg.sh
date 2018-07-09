#!/bin/bash

function ksdpkg_require_pkg_dir() {
    if [ ! -d "$1" ]; then
        >&2 echo "E: First argument should be the root directory of the package you're"
        >&2 echo "   building. You passed '$1', which isn't a valid directory."
        return 1
    fi
    echo "$1"
}

function ksdpkg_clear_extra_files() {
    local PKGDIR=
    if ! PKGDIR="$(ksdpkg_require_pkg_dir "$1")"; then
        return 1
    fi

    shift

    declare -ag extrafiles
    filestore=/tmp/ks-extra-filestore

    # for each glob of file patterns...
    while [ "$#" -gt 1 ]; do
        local files="$(find "$PKGDIR" -name "$1")"
        if [ -n "$files" ]; then
            for f in $files; do
                f="$(echo "$f" | sed "s#$PKGDIR/\?##")"
                extrafiles[${#extrafiles[@]}]="$f"
                mkdir -p "$filestore/$(dirname "$f")"
                mv "$PKGDIR/$f" "$filestore/$f"
            done
        fi
    done
}

function ksdpkg_restore_extra_files() {
    local PKGDIR=
    if ! PKGDIR="$(ksdpkg_require_pkg_dir "$1")"; then
        return 1
    fi

    if [ "${#extrafiles[@]}" -gt 0 ]; then
        for f in ${extrafiles[@]}; do
            mv "$filestore/$f" "$PKGDIR/$f"
        done
    fi

    rm -Rf "$filestore"
}

function ksdpkg_update_pkg_version() {
    local PKGDIR=
    if ! PKGDIR="$(ksdpkg_require_pkg_dir "$1")"; then
        return 1
    fi

    if [ -z "$2" ]; then
        >&2 echo "E: ksdpkg_update_pkg_version: You must provide the version string"
        >&2 echo "   as the second parameter to this function."
        return 2
    fi

    sed -i "s/^Version:.*$/Version: $2/" "$PKGDIR/DEBIAN/control"
}

function ksdpkg_update_pkg_size() {
    local PKGDIR=
    if ! PKGDIR="$(ksdpkg_require_pkg_dir "$1")"; then
        return 1
    fi

    local PKGSIZE=0
    while read -d '' -r f; do
        local sz=$(stat -c%s "$f")
        !((PKGSIZE+=$sz))
    done < <(find "$PKGDIR" -type f -not -path "*DEBIAN*" -print0)
    !((PKGSIZE/=1024))
    sed -i 's/^Installed-Size:.*/Installed-Size: '"$PKGSIZE"'/' "$PKGDIR/DEBIAN/control"
}

function ksdpkg_update_md5s() {
    local PKGDIR=
    if ! PKGDIR="$(ksdpkg_require_pkg_dir "$1")"; then
        return 1
    fi

    local files=$(find "$PKGDIR" -not -type d -not -path "*DEBIAN*")
    if [ -n "$files" ]; then
        md5sum $files > "$PKGDIR/DEBIAN/md5sums"
        repl=$(echo "$PKGDIR/" | sed 's/\//\\\//g') # escape slashes in pathnam
        sed -i "s/$repl//g" "$PKGDIR/DEBIAN/md5sums" # make files in md5sums relative to package root
    else
        echo > "$PKGDIR/DEBIAN/md5sums"
    fi
}

