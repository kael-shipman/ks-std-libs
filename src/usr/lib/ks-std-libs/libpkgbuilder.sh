#!/bin/bash

set -e

# This library is intended to be included in a package builder file that provides the following functions:
#
# * setup_env -- Should set global buildir, pkgsrcdir, and pkgtype variables and do sanity checks
# * place_files $pkgname $targdir -- Should handle building files for $pkgname from source and placing them in hierarchy at $targdir
# * build_package $targdir $builddir -- Should build a finished package given the prepared hierarchy at $targdir and place it in $builddir
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

    for pkgdir in "$pkgsrcdir/$pkgtype"/*; do
        if [ ! -e "$pkgdir" ]; then
            continue;
        fi

        pkgname="$(basename "$pkgdir")"
        targdir="$builddir/$pkgname"

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

    echo "Done."
}

