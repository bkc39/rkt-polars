#!/usr/bin/env bash
#
# Reproduce the pkgs.rkt-lang.org catalog build locally, against a libcompat
# built for this platform: the dev shell's staged copy
# (polars/native-libs/libcompat.*) or scripts/build-so.sh's output.  The
# catalog publishes the `polars` collection (its source is the repo with
# ?path=polars), so install exactly the tracked files of that subdirectory as
# the package `polars` -- not the repo root -- with no Rust toolchain and no
# env-var override.  LIBCOMPAT is first staged as the native package
# polars-<platform> (scripts/stage-native-package.rkt: the rust-tree and
# commit recorded beside it, else HEAD's clean rust/) and put in a file://
# catalog that also holds a copy of the release catalog and
# pkgs.racket-lang.org (scripts/dependency-catalogs.sh), so `raco pkg install
# --auto` resolves polars' #:platform dependency on it as the catalog will;
# the install must load the library from that package.  Then every module is
# instantiated against it, and the docs and tests are run the way
# pkg-build.racket-lang.org runs them.  Run it in a fresh PLTUSERHOME: it
# removes any installed polars and polars-<platform> first.
#
# Usage: scripts/test-local.sh LIBCOMPAT
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "usage: scripts/test-local.sh LIBCOMPAT" >&2
  exit 2
fi

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
library=$(cd "$(dirname "$1")" && pwd)/$(basename "$1")
cd "$ROOT"

# Make sure no override leaks in from the dev shell / Nix.
unset RKT_POLARS_COMPAT_LIB_PATH || true

platform=$(racket -e '(display (system-library-subpath #f))')
case "$platform" in
  x86_64-linux*)  stage=x86_64-linux   pkg=polars-x86_64-linux ;;
  aarch64-macosx) stage=aarch64-macosx pkg=polars-aarch64-macosx ;;
  *) echo "test-local: no native package for $platform" >&2; exit 1 ;;
esac

scratch=$(mktemp -d)
trap 'rm -rf "$scratch"' EXIT
built="$scratch/built"
catalog="$scratch/catalog"
mkdir -p "$built" "$scratch/src"
cp "$library" "$built/"
for record in rust-tree commit; do
  if [[ -f "$(dirname "$library")/$record" ]]; then
    cp "$(dirname "$library")/$record" "$built/"
  fi
done

echo ">> removing any previously installed polars and $pkg"
raco pkg remove polars 2>/dev/null || true
raco pkg remove "$pkg" 2>/dev/null || true

echo ">> staging $pkg from $library"
# The staging script reads polars' native-location module, which needs
# threading, before polars is installed.
raco pkg install --batch --auto --skip-installed threading-lib
racket -S "$ROOT" scripts/stage-native-package.rkt --head \
  "$stage" "$built/$(basename "$library")" "$scratch/$pkg"
raco pkg create --format zip --dest "$scratch" "$scratch/$pkg"

echo ">> a file:// catalog of the dependencies' catalogs and $pkg"
listed=$(scripts/dependency-catalogs.sh)
sources=()
while IFS= read -r source; do sources+=("$source"); done <<< "$listed"
raco pkg catalog-copy "${sources[@]}" "$catalog"
racket scripts/release/catalog.rkt entry "$pkg" "$scratch/$pkg" "$scratch/$pkg.zip" \
  "file://$scratch/$pkg.zip" > "$catalog/pkg/$pkg"

echo ">> installing the polars collection (pulls deps: $pkg, gregor-lib, etc.)"
# Tracked files only, so the staged copy in polars/native-libs stays behind.
git -C "$ROOT" ls-files -z -- polars | tar -C "$ROOT" --null -T - -cf - | tar -C "$scratch/src" -xf -
raco pkg install --batch --auto --copy --no-docs --catalog "file://$catalog" \
  --name polars "$scratch/src/polars"

echo ">> polars loads libcompat from $pkg, and staged no library"
racket "$ROOT/scripts/check-native-install.rkt" "$pkg"

echo ">> instantiating every module against $pkg's libcompat"
racket "$ROOT/scripts/check-bindings.rkt"

echo ">> building docs + checking declared deps (as the package server does)"
# --no-docs above skipped threading-doc too; the manual's `~>` links need it.
raco setup --check-pkg-deps --pkgs threading-doc
DOCS_CHECK_PKG=polars scripts/docs-check.sh

echo ">> running tests"
raco test -x --timeout 600 -c polars
