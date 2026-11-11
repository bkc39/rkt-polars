#!/usr/bin/env bash
#
# Reproduce the pkgs.rkt-lang.org catalog build locally.  The catalog
# publishes the `polars` collection (its source is the repo with
# ?path=polars), so install exactly that subdirectory as the package
# `polars` -- not the repo root -- with no Rust toolchain and no env-var
# override.  The candidate for this platform is first staged as the native
# package polars-<platform> (scripts/stage-native-package.rkt) and put in a
# file:// catalog that also holds a copy of the configured ones, so `raco pkg
# install --auto` resolves polars' #:platform dependency on it as the catalog
# will; the install must load the library from that package.  Then every module
# is instantiated against it, and the docs and tests are run the way
# pkg-build.racket-lang.org runs them.
#
# Usage: scripts/test-local.sh
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

# Make sure no override leaks in from the dev shell / Nix.
unset RKT_POLARS_COMPAT_LIB_PATH || true

platform=$(racket -e '(display (system-library-subpath #f))')
case "$platform" in
  x86_64-linux*)  candidate=linux  stage=x86_64-linux   pkg=polars-x86_64-linux ;;
  aarch64-macosx) candidate=darwin stage=aarch64-macosx pkg=polars-aarch64-macosx ;;
  *) echo "test-local: no native package for $platform" >&2; exit 1 ;;
esac

echo ">> removing any previously installed polars and $pkg"
raco pkg remove polars 2>/dev/null || true
raco pkg remove "$pkg" 2>/dev/null || true

echo ">> clearing staged native libs (load from the native package)"
rm -f polars/native-libs/libcompat.* || true

scratch=$(mktemp -d)
trap 'rm -rf "$scratch"' EXIT
libs=(polars/native-libs/candidates/"$candidate"/libcompat.*)
catalog="$scratch/catalog"

echo ">> staging $pkg from ${libs[0]}"
# The staging script reads polars' native-location module, which needs
# threading, before polars is installed.
raco pkg install --batch --auto --skip-installed threading-lib
racket -S "$ROOT" scripts/stage-native-package.rkt --head "$stage" "${libs[0]}" "$scratch/$pkg"
raco pkg create --format zip --dest "$scratch" "$scratch/$pkg"

echo ">> a file:// catalog of the configured catalogs and $pkg"
raco pkg catalog-copy --from-config "$catalog"
racket scripts/add-catalog-entry.rkt "$catalog" "$pkg" "$scratch/$pkg.zip"

echo ">> installing the polars collection (pulls deps: $pkg, gregor-lib, etc.)"
raco pkg install --batch --auto --copy --no-docs --catalog "file://$catalog" \
  --name polars "$ROOT/polars"

echo ">> polars loads libcompat from $pkg, and staged no candidate"
racket "$ROOT/scripts/check-native-install.rkt" "$pkg"

echo ">> instantiating every module against $pkg's libcompat"
racket "$ROOT/scripts/check-bindings.rkt"

echo ">> building docs + checking declared deps (as the package server does)"
# --no-docs above skipped threading-doc too; the manual's `~>` links need it.
raco setup --check-pkg-deps --pkgs threading-doc
DOCS_CHECK_PKG=polars scripts/docs-check.sh

echo ">> running tests"
raco test -x --timeout 600 -c polars
