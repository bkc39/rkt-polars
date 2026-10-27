#!/usr/bin/env bash
#
# Copies every libcompat.* in SRC into DEST without writing over a file in
# place (#265). Each copy goes to a temporary file in DEST and is renamed onto
# its target, so a racket that has the old library mapped keeps the old inode;
# `cp -f` truncated and rewrote it, and that racket died with "invalid memory
# reference". A target whose bytes already match is left alone, inode and
# mtime. On any failure the temporary file is removed and the target is as it
# was.
#
# Called by the dev shell's hook (flake.nix's devSetup) and by
# `nix run .#copy-native-libs`; tested by scripts/install-native-libs-test.sh.
#
# Usage: scripts/install-native-libs.sh SRC DEST
set -euo pipefail

if [ $# -ne 2 ]; then
  echo "usage: install-native-libs.sh SRC DEST" >&2
  exit 2
fi
src=$1
dest=$2

tmp=
trap '[ -z "$tmp" ] || rm -f "$tmp"' EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

shopt -s nullglob
libs=("$src"/libcompat.*)
if [ ${#libs[@]} -eq 0 ]; then
  echo "install-native-libs: no libcompat.* in $src" >&2
  exit 1
fi

mkdir -p "$dest"
for lib in "${libs[@]}"; do
  name=${lib##*/}
  target=$dest/$name
  if [ -f "$target" ] && cmp -s "$lib" "$target"; then
    continue
  fi
  tmp=$(mktemp "$dest/.$name.XXXXXX")
  cp "$lib" "$tmp"
  chmod 0755 "$tmp"
  mv -f "$tmp" "$target"
  tmp=
done
