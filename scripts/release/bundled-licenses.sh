#!/usr/bin/env bash
set -euo pipefail

if [ $# -ne 2 ]; then
  echo "usage: bundled-licenses.sh CARGO.LOCK REGISTRY-SRC" >&2
  exit 2
fi
lock=$1
registry=$2

# crate, the C library it bundles, and that library's licence file in the crate.
bundled="zstd-sys zstd zstd/LICENSE
lz4-sys liblz4 liblz4/lib/LICENSE"

printf '\n%s\n\n%s\n' "================================================================================" \
  "C libraries compiled into libcompat by the crates that bundle them, with their licences:"
while read -r crate library file; do
  version=$(awk -v name="\"$crate\"" '
    $1 == "name" && $3 == name { found = 1; next }
    found && $1 == "version" { gsub(/"/, "", $3); print $3; exit }' "$lock")
  if [ -z "$version" ]; then
    echo "bundled-licenses: $lock has no $crate, which bundles $library" >&2
    exit 1
  fi
  text=""
  for dir in "$registry"/*/"$crate-$version"; do
    if [ -f "$dir/$file" ]; then text="$dir/$file"; fi
  done
  if [ -z "$text" ]; then
    echo "bundled-licenses: no $crate-$version/$file under $registry, the licence of the $library it bundles" >&2
    exit 1
  fi
  printf '\n%s, bundled by %s %s (%s):\n\n' "$library" "$crate" "$version" "$file"
  cat "$text"
done <<<"$bundled"
