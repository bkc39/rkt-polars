#!/usr/bin/env bash
#
# Removes polars-x86_64-linux/ and polars-aarch64-macosx/ at the root of the
# checkout ROOT when git tracks nothing under one and it holds nothing but
# compiled/: what a raco setup left before the native skeletons moved to
# native/ (#254). The root's 'multi package makes such a directory a
# collection, so collection-file-path finds its stale main_rkt.zo as the
# installed native package. A symbolic link, a directory holding anything
# else, and a ROOT git cannot read are left alone. Prints one line per
# directory removed. The dev shell's hook runs it.
#
# Usage: scripts/remove-stale-skeletons.sh ROOT
set -euo pipefail

root=$1
for name in polars-x86_64-linux polars-aarch64-macosx; do
  dir=$root/$name
  if [ -L "$dir" ] || [ ! -d "$dir" ]; then
    continue
  fi
  if ! tracked=$(git -C "$root" ls-files -- "$name" 2> /dev/null) || [ -n "$tracked" ]; then
    continue
  fi
  entries=$(ls -A "$dir")
  if [ -n "$entries" ] && [ "$entries" != compiled ]; then
    continue
  fi
  if [ -L "$dir/compiled" ]; then
    continue
  fi
  rm -rf -- "$dir"
  echo "Removed $dir: the native skeletons are under native/ (#254)"
done
