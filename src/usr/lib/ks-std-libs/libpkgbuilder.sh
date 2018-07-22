#!/bin/bash

# This library implements the "predefined algorithm" pattern by using a series of functions intended to be
# environment-defined  to perform the work of building specific types of packages. It's primary "export" is
# the `build` function, which expects the environment to define a `setup_env` function to set up the build
# environment, a `place_files` function to place files from the source into the $target (provided as an
# argument), and a `build_package` function to build a package of the type passed as the first argument.
#
# These are the full interfaces expected of those functions:
#
# * setup_env -- Sets optional global $builddir and $pkgsrcdir variables and does sanity checks, like
#   making sure certain libraries are loaded, if necessary. ($builddir defaults to 'build' and $pkgsrcdir
#   defaults to 'pkg-src'.)
# * place_files $pkgname $targdir $pkgtype -- Handles building files for $pkgname package from source and
#   placing them in the hierarchy at $targdir ($pkgtype is provided in case special files are required for
#   certain package types, e.g., deb vs rpm vs pacman)
# * build_package $pkgtype $targdir $builddir -- Builds a finished binary package of type $pkgtype given the
#   prepared package source at $targdir and places it in $builddir
##


##
# This is a framework function that depends on the following setup:
#
# * ./VERSION - a file containing the version of the current package.
# * ./$pkgsrcdir/[pkg-type]/[pkg-meta-files] - The per-package meta-files for each package type. For example,
#   this might include ./$pkgsrcdir/deb/DEBIAN/{config,control,postinst,postrm,templates}.
# * ./$pkgsrcdir/generic - (OPTIONAL) Directory containing files (like systemd files or cron files) that should be
#   applied to all packages.
#
# It iterates through all non-generic subdirectories of $pkgsrcdir (for example, `deb`, `rpm`, `pacman`), then
# iterates through each package directory within those (for example, `deb/mypkg1`, `deb/mypkg2`), then does the
# following for each package:
#
# 1. Cleans $builddir of previous attempts to build the package
# 2. Copies $pkgsrcdir/$pkgtype/$pkgname to $builddir/$pkgname.$pkgtype
# 3. Copies files from $pkgsrcdir/generic/$pkgname/ into $builddir/$pkgname.$pkgtype/
# 4. Calls `place_files "$pkgname" "$targdir" "$pkgtype"`
# 5. Replaces the string '::VERSION::' in any of the files in $builddir/$pkgname.$pkgtype/ with the version from ./VERSION
# 6. Calls `build_package "$pkgtype" "$targdir" "$builddir"`
# 7. Cleans up (`rm -Rf "$builddir/$pkgname.$pkgtype"`)
#
# When this is finished, a final binary package file of each type should exist for each package defined.
##
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
        builddir="build"
    fi
    mkdir -p "$builddir"

    if [ -z "$pkgsrcdir" ]; then
        if [ -d "pkg-src" ]; then
            pkgsrcdir="pkg-src"
        else
            >&2 echo
            >&2 echo "E: Your setup_env function must set the global \$pkgsrcdir variable to the directory containing your"
            >&2 echo "   package sources (or you must use the default, 'pkg-src', as your \$pkgsrcdir)"
            >&2 echo
            exit 5
        fi
    fi

    if [ ! -d "$pkgsrcdir" ]; then
        >&2 echo
        >&2 echo "E: \$pkgsrcdir ($pkgsrcdir) doesn't appear to exist. Are you sure you're running this from your repo root?"
        >&2 echo
        exit 7
    fi

    local pkgcount=0
    for pkgtype in "$pkgsrcdir"/*; do
        if [ ! -e "$pkgtype" ]; then
            continue;
        fi
        pkgtype="$(basename "$pkgtype")"

        # Skip special "generic" folder
        if [ "$pkgtype" == "generic" ]; then
            continue
        fi

        for pkgdir in "$pkgsrcdir/$pkgtype"/*; do
            if [ ! -e "$pkgdir" ]; then
                continue;
            fi

            !((pkgcount++))

            local pkgname="$(basename "$pkgdir")"
            local targdir="$builddir/$pkgname.$pkgtype"

            rm -Rf "$targdir" 2>/dev/null
            cp -R --preserve=mode "$pkgdir" "$targdir"

            # Place generic files
            if [ -e "$pkgsrcdir/generic/$pkgname" ]; then
                cp -R "$pkgsrcdir/generic/$pkgname"/* "$targdir/"
            fi

            # Call project-specific place_files function
            place_files "$pkgname" "$targdir" "$pkgtype"

            # Replace version with current version (Making sure to escape the special VERSION selector so it doesn't get subbed out itself)
            sed -i "s/::""VERSION""::/$(cat VERSION)/g" $(grep -Frl "::""VERSION""::" "$targdir" | sed '/\.sw[op]$/d')

            # Build deb package
            build_package "$pkgtype" "$targdir" "$builddir"

            rm -Rf "$targdir"
        done
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

##
# Convenience function that does deb-specific dependency checks
#
# This is usually called from the global "setup_env" when $pkgtype == "deb"
##
function setup_deb_env() {
    if ! command -v dpkg &>/dev/null; then
        >&2 echo
        >&2 echo "E: Your system doesn't appear to have dpkg installed. Dpkg is required"
        >&2 echo "   for creating debian packages."
        >&2 echo
        exit 3
    fi
}

##
# Convenience function that builds dep packages according to standard algorithm
#
# This is usually called from the global "build_package" when $pkgtype == "deb"
##
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

##
# Argument-checking function
#
# @param string $pkgdir The root of the deb package being built
# @return 0|1
# @stdout $pkgdir
##
function ksdpkg_require_pkg_dir() {
    if [ ! -d "$1" ]; then
        >&2 echo "E: First argument should be the root directory of the package you're"
        >&2 echo "   building. You passed '$1', which isn't a valid directory."
        return 1
    fi
    echo "$1"
}

##
# Temporarily clears extra files like .swp files, setting the $ksdpkg_extrafiles environment
# variable to be used later to restore them.
#
# @param string $pkgdir The root of the deb package being built
# @return 0|1
# @stdout void
##
function ksdpkg_clear_extra_files() {
    local PKGDIR=
    if ! PKGDIR="$(ksdpkg_require_pkg_dir "$1")"; then
        return 1
    fi

    shift

    unset ksdpkg_extrafiles
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

##
# Restores files previously cleared by ksdpkg_clear_extra_files
#
# @param string $pkgdir The root of the deb package being built
# @return 0|1
# @stdout void
##
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

##
# Updates the version of the package to that given as the second argument
#
# @deprecated -- Use ::VERSION:: variable substitution now
#
# @param string $pkgdir The root of the deb package being built
# @param string $version The new version of the package
# @return 0|1
# @stdout void
##
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

##
# Combs through all directories under $pkgsrc, excluding "DEBIAN", and calculates the total
# size of the installed package.
#
# @param string $pkgdir The root of the deb package being built
# @return 0|1
# @stdout void
##
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

##
# Combs through all directories under $pkgsrc, excluding "DEBIAN", and calculates the md5 sum
# of every file found, outputting to $pkgsrc/DEBIAN/md5sums.
#
# @param string $pkgdir The root of the deb package being built
# @return 0|1
# @stdout void
##
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
        echo -n > "$PKGDIR/DEBIAN/md5sums"
    fi
}

##
# Combs through all directories under $pkgsrc, excluding "DEBIAN", and, if second argument is "root", for any
# file owned by the current active user, changes ownership to root. If second argument is blank (or otherwise
# not "root"), it changes ownership back to the current active user.
#
# @param string $pkgdir The root of the deb package being built
# @param string "root"|null If changing to root, then "root"; otherwise, null
# @return 0|1
# @stdout void
##
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


