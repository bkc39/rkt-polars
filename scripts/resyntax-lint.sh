#!/usr/bin/env bash
#
# The resyntax gate: the project's suite (lint/, module path `lint`) over
# the Racket sources, red on any suggestion.  `resyntax analyze` exits 0
# whether or not it suggests anything, so its output is matched against the
# line that starts each suggestion.  Files are analyzed one per process,
# RESYNTAX_JOBS (default: every core) at a time.  Runs in the dev shell,
# which installs Resyntax.
#
# Usage: scripts/resyntax-lint.sh          report, exit 1 on any suggestion
#        scripts/resyntax-lint.sh fix      apply the suggestions in place
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

dirs=(polars examples bench)
suite=(--refactoring-suite lint polars-style --analyzer-timeout 30000)

case "${1:-}" in
  --one)
    resyntax "$2" --file "$4" "${suite[@]}" > "$3/$(printf '%s' "$4" | tr / _).log" 2>&1
    exit
    ;;
  "") command=analyze ;;
  fix) command=fix ;;
  *)
    echo "usage: scripts/resyntax-lint.sh [fix]" >&2
    exit 2
    ;;
esac

jobs=${RESYNTAX_JOBS:-$(nproc)}
out_dir=$(mktemp -d)
trap 'rm -rf "$out_dir"' EXIT

# Stale or foreign bytecode would be recompiled in memory by every process.
find "${dirs[@]}" -name '*.rkt' -not -path '*/compiled/*' -print0 \
  | xargs -0 raco make -j "$jobs" lint/main.rkt

# Largest first, so that the longest analyses do not start last.
status=0
find "${dirs[@]}" -name '*.rkt' -not -path '*/compiled/*' -print0 \
  | xargs -0 ls -S \
  | xargs -n 1 -P "$jobs" \
      bash "$PWD/scripts/resyntax-lint.sh" --one "$command" "$out_dir" \
  || status=$?

out=$(cat "$out_dir"/*.log)
printf '%s\n' "$out"
if [ "$status" -ne 0 ]; then
  echo "resyntax-lint: resyntax $command failed on at least one file (xargs exit $status)" >&2
  exit "$status"
fi
if [ "$command" = fix ]; then
  exit 0
fi

timeouts=$(grep -c "timed out" <<< "$out" || true)
if [ "$timeouts" -gt 0 ]; then
  echo "resyntax-lint: an analyzer timed out on $timeouts file(s); those files were analyzed in part" >&2
fi

if grep -qE 'resyntax: .*\.rkt:[0-9]+:[0-9]+ \[' <<< "$out"; then
  echo "resyntax-lint: suggestions above; apply them with scripts/resyntax-lint.sh fix" >&2
  exit 1
fi
echo "resyntax-lint: no suggestions"
