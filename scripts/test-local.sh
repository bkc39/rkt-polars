#!/usr/bin/env bash
#
# Reproduce the pkgs.rkt-lang.org catalog build locally.  The catalog
# publishes the `polars` collection (its source is the repo with
# ?path=polars), so install exactly that subdirectory as the package
# `polars` -- not the repo root -- with no Rust toolchain and no env-var
# override.  This forces the pre-installer (polars/private/install-compat.rkt)
# to copy the prebuilt shared object out of
# polars/native-libs/candidates/<platform>/, then builds docs and runs tests
# the way pkg-build.racket-lang.org does.
#
# Usage: scripts/test-local.sh
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

# Make sure no override leaks in from the dev shell / Nix.
unset RKT_POLARS_COMPAT_LIB_PATH || true

echo ">> removing any previously installed polars"
raco pkg remove polars 2>/dev/null || true

echo ">> clearing staged native libs (force install from candidates/)"
rm -f polars/native-libs/libcompat.* || true

echo ">> installing the polars collection (pulls deps: gregor-lib, etc.)"
raco pkg install --batch --auto --copy --name polars "$ROOT/polars"

echo ">> building docs + checking declared deps (as the package server does)"
raco setup --check-pkg-deps --pkgs polars

echo ">> running tests"
raco test -x -c polars
