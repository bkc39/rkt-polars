#!/usr/bin/env bash
set -euo pipefail

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
root=$(cd "$here/../.." && pwd)

if [ $# -ne 1 ]; then
  echo "usage: notices.sh OUT (needs nix, and the network for the crates cargo-about reads)" >&2
  exit 2
fi
mkdir -p "$(dirname "$1")"
nix run --inputs-from "$root" nixpkgs#cargo-about -- generate --locked \
  --manifest-path "$root/rust/Cargo.toml" -c "$here/about.toml" -o "$1" "$here/about.hbs"
grep -q '^Apache License 2.0 (Apache-2.0), used by:$' "$1" || {
  echo "notices: $1 lists no Apache-2.0 crate" >&2
  exit 1
}
echo "notices: $1, $(grep -c '^  [^ ].* [0-9][^ ]*\( http\| *$\)' "$1") crate lines"
