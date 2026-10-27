#!/usr/bin/env bash
#
# The no-inline-tests gate: fails on a test submodule in a library module
# under polars/private.  Its tests live in the mirrored file under
# polars/tests (#256).
#
# Usage: scripts/no-inline-tests.sh
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

dir=polars/private
message="move the test submodule to the mirrored file under polars/tests"

hits=$(grep -rnE --include='*.rkt' \
         '\(module[+*]?[[:space:]]+test([^-[:alnum:]!?*<>=/+:.$%&^~_]|$)' "$dir" || true)
if [ -z "$hits" ]; then
  echo "no-inline-tests: none in $dir"
  exit 0
fi
while IFS=: read -r file line _; do
  echo "$file:$line: $message"
  if [ -n "${GITHUB_ACTIONS:-}" ]; then
    echo "::error file=$file,line=$line::$message"
  fi
done <<< "$hits"
exit 1
