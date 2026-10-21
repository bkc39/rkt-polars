#!/usr/bin/env bash
#
# The docs gate: builds the manual with raco setup and fails on an undefined
# tag or on information collected for a key multiple times (a duplicated
# defproc).  raco setup reports both as warnings and exits 0, and it reports
# them only for a document it renders, so the rendered HTML is also searched
# for Scribble's badlink, which a run with nothing to rebuild leaves in place.
#
# Usage: scripts/docs-check.sh [DOC-DIR]
#   DOC-DIR is the rendered manual (default: polars/doc/polars under the
#   installed polars collection).  Extra raco setup flags go in
#   DOCS_CHECK_SETUP_FLAGS, e.g. "-j 4".
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

log=$(mktemp "${TMPDIR:-/tmp}/docs-check.XXXXXX")
trap 'rm -f "$log"' EXIT

status=0
# shellcheck disable=SC2086
if ! raco setup ${DOCS_CHECK_SETUP_FLAGS:-} --check-pkg-deps --unused-pkg-deps \
       --pkgs rkt-polars 2>&1 | tee "$log"; then
  echo "docs-check: raco setup failed" >&2
  status=1
fi

doc_dir=${1:-$(racket -e '(display (build-path (collection-path "polars") "doc" "polars"))')}

# Each undefined tag follows its warning on a line of its own, indented.
warnings=$(awk '/undefined tag|multiple times/ { keys = 1; print; next }
                keys && /^raco setup:  / { print; next }
                { keys = 0 }' "$log")
badlinks=""
if [ -d "$doc_dir" ]; then
  badlinks=$(grep -rnoE --include='*.html' '<font class="badlink">.{0,160}' "$doc_dir" || true)
else
  echo "docs-check: no rendered manual at $doc_dir" >&2
  status=1
fi

report() {
  local message=$1
  echo "docs-check: $message" >&2
  if [ -n "${GITHUB_ACTIONS:-}" ]; then
    echo "::error::docs-check: $message"
  fi
}

if [ -n "$warnings" ]; then
  status=1
  report "raco setup warned (it exits 0 on these):"
  printf '%s\n' "$warnings" >&2
fi
if [ -n "$badlinks" ]; then
  status=1
  report "the rendered manual has undefined links (badlink):"
  printf '%s\n' "$badlinks" >&2
fi
if printf '%s\n%s\n' "$warnings" "$badlinks" | grep -qE 'threading|~>|~&gt;'; then
  report "the threading docs are not rendered; run: raco setup --pkgs threading-doc"
fi

if [ "$status" -eq 0 ]; then
  echo "docs-check: no undefined tags, duplicate keys or badlinks in $doc_dir"
fi
exit "$status"
