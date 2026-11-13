#!/usr/bin/env bash
set -euo pipefail

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=scripts/release/pins.sh
. "$here/pins.sh"
root=$(cd "$here/../.." && pwd)

if [ $# -ne 1 ]; then
  echo "usage: notices.sh OUT (needs nix, and the network for the crates cargo-about reads)" >&2
  exit 2
fi
out=$1
mkdir -p "$(dirname "$out")"
nix run --inputs-from "$root" nixpkgs#cargo-about -- generate --locked \
  --manifest-path "$root/rust/Cargo.toml" -c "$here/about.toml" -o "$out" "$here/about.hbs"
release_grep -q '^Apache License 2.0 (Apache-2.0), used by:$' "$out" || {
  echo "notices: $out lists no Apache-2.0 crate" >&2
  exit 1
}
bash "$here/bundled-licenses.sh" "$root/rust/Cargo.lock" "${CARGO_HOME:-$HOME/.cargo}/registry/src" >>"$out"
echo "notices: $out, $(release_matches -c '^  [^ ].* [0-9][^ ]*\( http\| *$\)' "$out") crate lines"
