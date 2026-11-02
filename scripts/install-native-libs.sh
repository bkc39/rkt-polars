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
# Beside each library it writes a marker, .<name>.dev, holding the
# installed library's sha256 as 64 lowercase hex digits and a newline, also
# by rename and left alone when it already holds that hash. The source is
# hashed before anything is written, so a kill leaves a new library behind
# an old marker only between the two renames. The pre-installer (polars/private/install-compat.rkt)
# keeps a library whose marker matches it instead of copying the committed
# candidate over it (#306).
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

install_by_rename() {
  local from=$1 target=$2 mode=$3 base
  base=${target##*/}
  tmp=$(mktemp "${target%/*}/.${base#.}.XXXXXX")
  cp "$from" "$tmp"
  chmod "$mode" "$tmp"
  mv -f "$tmp" "$target"
  tmp=
}

mkdir -p "$dest"
for lib in "${libs[@]}"; do
  name=${lib##*/}
  target=$dest/$name
  marker=$dest/.$name.dev
  sum=$(sha256sum "$lib")
  sum=${sum%% *}
  if ! { [ -f "$target" ] && cmp -s "$lib" "$target"; }; then
    install_by_rename "$lib" "$target" 0755
  fi
  if [ "$(cat "$marker" 2> /dev/null)" != "$sum" ]; then
    install_by_rename /dev/stdin "$marker" 0644 <<< "$sum"
  fi
done
