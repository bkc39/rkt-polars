#!/usr/bin/env bash
#
# The no-inline-tests gate: fails on a test submodule in a library module
# under polars/private.  Its tests live in the mirrored file under
# polars/tests (#256).  A grep, so a form split across lines escapes it; the
# read-based check in polars/tests/resource.rkt is the exact one.
#
# Usage: scripts/no-inline-tests.sh
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

dirs=(polars/private)
after='([^-[:alnum:]!?*<>=/+:.$%&^~_]|$)'

status=0
flag() {
  local form=$1 message=$2 hits found=0
  hits=$(grep -rnE --include='*.rkt' "$form$after" "${dirs[@]}") || found=$?
  if [ "$found" -gt 1 ]; then
    echo "no-inline-tests: grep failed (exit $found) on ${dirs[*]}" >&2
    status=2
    return 0
  fi
  hits=$(grep -vE '^[^:]+:[0-9]+:[[:space:]]*;' <<< "$hits" || true)
  [ -n "$hits" ] || return 0
  status=1
  while IFS=: read -r file line _; do
    echo "$file:$line: $message"
    if [ -n "${GITHUB_ACTIONS:-}" ]; then
      echo "::error file=$file,line=$line::$message"
    fi
  done <<< "$hits"
}

flag '[[(][[:space:]]*module[+*]?[[:space:]]+test' \
     "move the test submodule to the mirrored file under polars/tests"

if [ "$status" -eq 0 ]; then
  echo "no-inline-tests: none in ${dirs[*]}"
fi
exit "$status"
