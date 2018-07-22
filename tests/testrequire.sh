#!/bin/bash

set -e

requirepath=src/usr/bin/require
n=0
while [ ! -e "$requirepath" ] && [ "$n" -lt 2 ]; do
    requirepath="../$requirepath"
    !((n++))
done

if [ ! -e "$requirepath" ]; then
    >&2 echo "Couldn't find 'require'"
    exit 1
fi

. "$requirepath" -v SOMEVAR librexec.sh ../src/usr/lib/ks-std-libs src/usr/lib/ks-std-libs

function test_includes_librexec() {
    assert "type -t rexec &>/dev/null"
}

function test_sets_somevar() {
    assert "[ '$(basename "$SOMEVAR")' == 'ks-std-libs' ]"
}
