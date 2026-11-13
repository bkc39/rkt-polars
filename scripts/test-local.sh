#!/usr/bin/env bash
#
# Reproduce the pkgs.racket-lang.org catalog install locally, against a
# libcompat built for this platform: the dev shell's staged copy
# (polars/native-libs/libcompat.*) or scripts/build-so.sh's output.  LIBCOMPAT
# is staged as the native package polars-<platform>
# (scripts/stage-native-package.rkt: the rust-tree and commit recorded beside
# it, else HEAD's clean rust/) and packed as the release's package job packs
# it, a zip, its catalog entry and its manifest; then
# scripts/release/catalog-test.sh --full installs polars' tracked files from a
# file:// catalog holding it, in a fresh PLTUSERHOME, and checks, renders the
# docs and runs the tests as the release build does: the modules pkg-build's
# `raco test --drdr` runs, red on stderr.
#
# Usage: scripts/test-local.sh LIBCOMPAT
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "usage: scripts/test-local.sh LIBCOMPAT" >&2
  exit 2
fi

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
library=$(cd "$(dirname "$1")" && pwd)/$(basename "$1")
unset RKT_POLARS_COMPAT_LIB_PATH || true

# shellcheck source=scripts/release/pins.sh
. "$ROOT/scripts/release/pins.sh"
host=$(racket -e '(display (system-library-subpath #f))')
platform=$(release_host_platform "$host")
if [[ -z "$platform" ]]; then
  echo "test-local: no native package for $host (platforms: $RELEASE_PLATFORMS)" >&2
  exit 1
fi
release_platform "$platform"
pkg=$RELEASE_PACKAGE

scratch=$(mktemp -d)
trap 'rm -rf "$scratch"' EXIT
mkdir -p "$scratch/built" "$scratch/dist"
cp "$library" "$scratch/built/"
for record in rust-tree commit; do
  if [[ -f "$(dirname "$library")/$record" ]]; then
    cp "$(dirname "$library")/$record" "$scratch/built/"
  fi
done

echo ">> staging $pkg from $library"
# The staging script reads polars' native-location module, which needs
# threading, before polars is installed.
raco pkg install --batch --auto --skip-installed threading-lib
racket -S "$ROOT" "$ROOT/scripts/stage-native-package.rkt" --head \
  "$platform" "$scratch/built/$(basename "$library")" "$scratch/$pkg"
raco pkg create --format zip --dest "$scratch/dist" "$scratch/$pkg"
racket "$ROOT/scripts/release/catalog.rkt" entry "$pkg" "$scratch/$pkg" \
  "$scratch/dist/$pkg.zip" "file://$scratch/dist/$pkg.zip" > "$scratch/dist/$pkg.rktd"
cp "$scratch/$pkg/manifest.json" "$scratch/dist/$pkg.manifest.json"

bash "$ROOT/scripts/release/catalog-test.sh" "$platform" "$scratch/dist" --full
