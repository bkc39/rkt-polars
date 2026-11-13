#!/usr/bin/env bash
#
# Removes polars-x86_64-linux/ and polars-aarch64-macosx/ at the root of the
# checkout ROOT when git tracks nothing under one and it holds nothing but
# compiled/: what a raco setup left before the native skeletons moved to
# native/ (#254). The root's 'multi package makes such a directory a
# collection, so collection-file-path finds its main.rkt or stale
# compiled/main_rkt.zo as the installed native package. A symbolic link, a
# directory holding anything else, and a ROOT git cannot read are left alone,
# with one line naming the directory and why it was kept when it holds a
# main.rkt or a compiled/, so it still shadows the package. Prints one line
# per directory removed. The dev shell's hook runs it.
#
# Usage: scripts/remove-stale-skeletons.sh ROOT
set -euo pipefail

root=$1
for name in polars-x86_64-linux polars-aarch64-macosx; do
  dir=$root/$name
  if [ ! -d "$dir" ]; then
    continue
  fi
  if ! tracked=$(git -C "$root" ls-files -- "$name" 2> /dev/null); then
    reason="git cannot list what $root tracks"
  elif [ -n "$tracked" ]; then
    continue
  elif [ -L "$dir" ]; then
    reason="git tracks nothing in it, but it is a symbolic link"
  elif [ -L "$dir/compiled" ]; then
    reason="git tracks nothing in it, but its compiled/ is a symbolic link"
  else
    entries=$(ls -A "$dir")
    if [ -z "$entries" ] || [ "$entries" = compiled ]; then
      rm -rf -- "$dir"
      echo "Removed $dir: the native skeletons are under native/ (#254)"
      continue
    fi
    reason="git tracks nothing in it, but it holds more than compiled/"
  fi
  if [ -e "$dir/main.rkt" ] || [ -d "$dir/compiled" ]; then
    echo "Kept $dir: $reason; collection-file-path finds its main.rkt or" \
      "compiled/main_rkt.zo as the native package, so delete it unless something in it is yours (#254)"
  fi
done
