#!/usr/bin/env bash
#
# Reproduce the pkgs.rkt-lang.org catalog build locally.  The catalog
# publishes the `polars` collection (its source is the repo with
# ?path=polars), so install exactly that subdirectory as the package
# `polars` -- not the repo root -- with no Rust toolchain and no env-var
# override.  The committed candidate for this platform is first staged as the
# native package polars-<platform> (scripts/stage-native-package.rkt) and
# installed, as the catalog will install the release's, so polars loads it from
# there; then every module is instantiated against it, and the docs and tests
# are run the way pkg-build.racket-lang.org runs them.
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

echo ">> staging and installing $pkg from ${libs[0]}"
racket scripts/stage-native-package.rkt "$stage" "${libs[0]}" "$scratch/$pkg"
raco pkg install --batch --copy --no-docs --name "$pkg" "$scratch/$pkg"

echo ">> installing the polars collection (pulls deps: gregor-lib, etc.)"
raco pkg install --batch --auto --copy --no-docs --name polars "$ROOT/polars"

echo ">> instantiating every module against $pkg's libcompat"
racket "$ROOT/scripts/check-bindings.rkt"

echo ">> building docs + checking declared deps (as the package server does)"
# --no-docs above skipped threading-doc too; the manual's `~>` links need it.
raco setup --check-pkg-deps --pkgs threading-doc
DOCS_CHECK_PKG=polars scripts/docs-check.sh

echo ">> running tests"
raco test -x --timeout 600 -c polars
