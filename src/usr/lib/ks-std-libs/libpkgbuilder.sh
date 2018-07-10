#!/bin/bash

# This library is intended to be included in a package builder environment that defines the following functions:
#
# * setup_env -- Should set global buildir, pkgsrcdir, and pkgtype variables and do sanity checks
# * place_files $pkgname $targdir -- Should handle building files for $pkgname from source and placing them in hierarchy at $targdir
# * build_package $targdir $builddir -- Should build a finished binary package given the prepared hierarchy at $targdir and place it in $builddir
#

function build() {
    if [ ! -e "./VERSION" ]; then
        >&2 echo
        >&2 echo "E: Can't find VERSION file. You should make sure to run this from the repo root (and"
        >&2 echo "   make sure you've got a VERSION file there)."
        >&2 echo
        exit 4
    fi

    setup_env

    if [ -z "$builddir" ]; then
        >&2 echo
        >&2 echo "E: Your setup_env function must set the global builddir variable to your build directory."
        >&2 echo
        exit 4
    fi
    mkdir -p "$builddir"

    if [ -z "$pkgsrcdir" ]; then
        >&2 echo
        >&2 echo "E: Your setup_env function must set the global pkgsrcdir variable to the directory containing your"
        >&2 echo "   package sources"
        >&2 echo
        exit 5
    fi

    if [ -z "$pkgtype" ]; then
        >&2 echo
        >&2 echo "E: Your setup_env function must set the global pkgtype variable to a value that corresponds with"
        >&2 echo "   the names of subdirectories of $pkgsrcdir"
        >&2 echo
        exit 6
    fi

    if [ ! -d "$pkgsrcdir" ]; then
        >&2 echo
        >&2 echo "E: \$pkgsrcdir ($pkgsrcdir) doesn't appear to exist. Are you sure you're running this from your repo root?"
        >&2 echo
        exit 7
    fi

    local pkgcount=0
    for pkgdir in "$pkgsrcdir/$pkgtype"/*; do
        if [ ! -e "$pkgdir" ]; then
            continue;
        fi

        !((pkgcount++))

        local pkgname="$(basename "$pkgdir")"
        local targdir="$builddir/$pkgname"

        rm -Rf "$targdir" 2>/dev/null
        cp -R --preserve=mode "$pkgdir" "$targdir"

        # Place generic files
        if [ -e "$pkgsrcdir/generic/$pkgname" ]; then
            cp -R "$pkgsrcdir/generic/$pkgname"/* "$targdir/"
        fi

        # Call project-specific place_files function
        place_files "$pkgname" "$targdir" "$pkgsrcdir"

        # Replace version with current version (Making sure to escape the special VERSION selector so it doesn't get subbed out itself)
        sed -i "s/::""VERSION""::/$(cat VERSION)/g" $(grep -Frl "::""VERSION""::" "$targdir" | sed '/\.sw[op]$/d')


        # Build deb package
        build_package "$targdir" "$builddir"

        rm -Rf "$targdir"
    done

    if [ "$pkgcount" -eq 0 ]; then
        >&2 echo
        >&2 echo "W: No packages found. Please make sure that "$pkgsrcdir/$pkgtype" exists and has package template folders in it."
        >&2 echo
    fi

    echo "Done."
    echo
}



# Debian specific

function setup_deb_env() {
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

function build_deb_package() {
    local targdir="$1"
    local builddir="$2"
    ksdpkg_clear_extra_files "$targdir"
    ksdpkg_update_pkg_size "$targdir"
    ksdpkg_update_md5s "$targdir"
    ksdpkg_change_ownership "$targdir" root
    dpkg --build "$targdir" "$builddir"
    ksdpkg_restore_extra_files "$targdir"
    ksdpkg_change_ownership "$targdir"
}

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

    declare -ag ksdpkg_extrafiles
    ksdpkg_filestore=/tmp/ks-extra-filestore

    # for each glob of file patterns...
    while [ "$#" -gt 1 ]; do
        local files="$(find "$PKGDIR" -name "$1")"
        if [ -n "$files" ]; then
            for f in $files; do
                f="$(echo "$f" | sed "s#$PKGDIR/\?##")"
                ksdpkg_extrafiles[${#ksdpkg_extrafiles[@]}]="$f"
                mkdir -p "$ksdpkg_filestore/$(dirname "$f")"
                mv "$PKGDIR/$f" "$ksdpkg_filestore/$f"
            done
        fi
    done
}

function ksdpkg_restore_extra_files() {
    local PKGDIR=
    if ! PKGDIR="$(ksdpkg_require_pkg_dir "$1")"; then
        return 1
    fi

    if [ "${#ksdpkg_extrafiles[@]}" -gt 0 ]; then
        for f in ${ksdpkg_extrafiles[@]}; do
            mv "$ksdpkg_filestore/$f" "$PKGDIR/$f"
        done
    fi

    rm -Rf "$ksdpkg_filestore"
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
    if grep -q 'Installed-Size:' "$PKGDIR/DEBIAN/control"; then
        sed -i 's/^Installed-Size:.*/Installed-Size: '"$PKGSIZE"'/' "$PKGDIR/DEBIAN/control"
    else
        echo "Installed-Size: $PKGSIZE" >> "$PKGDIR/DEBIAN/control"
    fi
}

function ksdpkg_update_md5s() {
    local PKGDIR=
    if ! PKGDIR="$(ksdpkg_require_pkg_dir "$1")"; then
        return 1
    fi

    local files=$(find "$PKGDIR" -not -type d -not -path "*DEBIAN*")
    if [ -n "$files" ]; then
        md5sum $files > "$PKGDIR/DEBIAN/md5sums"
        local repl=$(echo "$PKGDIR/" | sed 's/\//\\\//g') # escape slashes in pathnam
        sed -i "s/$repl//g" "$PKGDIR/DEBIAN/md5sums" # make files in md5sums relative to package root
    else
        echo > "$PKGDIR/DEBIAN/md5sums"
    fi
}

function ksdpkg_change_ownership() {
    local PKGDIR=
    if ! PKGDIR="$(ksdpkg_require_pkg_dir "$1")"; then
        return 1
    fi
    shift

    local files=$(find "$PKGDIR" ! -path '*DEBIAN*')
    if [ ! -z "$files" ]; then
        if [ ! -z "$SUDO_USER" ]; then
            local u="$SUDO_USER"
        else
            local u="$USER"
        fi
        if [ "$1" == 'root' ]; then
            local targ='root'
            local from="$u"
        else
            local targ="$u"
            local from="root"
        fi
        for f in $files; do
            local owner=
            if [ "$(stat -c '%U' "$f")" == "$from" ]; then
                owner="$targ"
            fi
            if [ "$(stat -c '%G' "$f")" == "$from" ]; then
                owner="$owner:$targ"
            fi
            sudo chown "$owner" "$f"
        done
    fi
}


