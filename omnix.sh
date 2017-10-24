#!/bin/sh

# This is a wrapper for Omnix.

if [ $# -lt 4 ]; then
    cat <<EOF >&2
This is a wrapper script for Omnix that is not mean to be run on its own.
Please see Omnix documentation for more info.
EOF
    exit 1
fi

if [ -z "$OMNIX_AUTO_INSTALL" ]; then
    OMNIX_AUTO_INSTALL=0
fi

# Args structure

# -------------+-----------+------+-----------------+---------------------------
# $1           | $2        | $3   | $4              | $n
# nixpkgs url  | attribute | path | execute command | extra args
# -------------+-----------+------+-----------------+---------------------------

nixpkgs="$1"; shift
attr="$1"; shift
path="$1"; shift
cmd="$1"; shift

expr="(import $nixpkgs {}).$attr"
drv=$(nix-instantiate --no-gc-warning -E "$expr")

if [ -z "$drv" ]; then
    cat <<EOF >&2
Nix cannot evaluate $expr.
EOF
    exit 1
fi

out=$(nix-store --no-gc-warning -r "$drv" | head -1)

if ! [ -d "$out" ]; then
    cat <<EOF >&2
Nix cannot build $attr.
EOF
    exit 1
fi

$(printf "$cmd" "$out/$path" "$@")

if [ "$OMNIX_AUTO_INSTALL" -eq 1 ]; then
    nix-env -i "$out"
fi
