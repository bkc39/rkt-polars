#!/usr/bin/env bash
#
# Reproduce the pkgs.rkt-lang.org catalog install locally: install the
# package with no Rust toolchain and no env-var override, so the
# pre-installer (polars/private/install-compat.rkt) is forced to copy the
# prebuilt shared object out of polars/native-libs/candidates/<platform>/.
#
# Usage: scripts/test-local.sh
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

# Make sure no override leaks in from the dev shell / Nix.
unset RKT_POLARS_COMPAT_LIB_PATH || true

echo ">> removing any previously installed rkt-polars"
raco pkg remove rkt-polars 2>/dev/null || true

echo ">> clearing staged native libs (force install from candidates/)"
rm -f polars/native-libs/libcompat.* || true

echo ">> installing from candidates"
raco pkg install --batch --auto --copy --name rkt-polars "$ROOT"

echo ">> running tests"
raco test -x -c polars
