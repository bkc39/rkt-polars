#!/usr/bin/env bash
#
# The no-syntax-rule gate: fails on any define-syntax-rule in the Racket
# sources.  Macros are define-syntax-parse-rule or syntax-parse, so pattern
# variables can carry syntax classes; lint/polars-style rewrites the uses it
# can prove equivalent, and this catches the rest.
#
# Usage: scripts/no-syntax-rule.sh
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

dirs=(polars examples user-guide bench scripts)
not_id='[^-[:alnum:]!?*<>=/+:.$%&^~_]'
hits=$(grep -rnE --include='*.rkt' --include='*.scrbl' \
         "(^|$not_id)define-syntax-rule($not_id|\$)" "${dirs[@]}" || true)

if [ -z "$hits" ]; then
  echo "no-syntax-rule: none in ${dirs[*]}"
  exit 0
fi

message="use define-syntax-parse-rule (require syntax/parse/define)"
while IFS=: read -r file line _; do
  echo "$file:$line: $message"
  if [ -n "${GITHUB_ACTIONS:-}" ]; then
    echo "::error file=$file,line=$line::$message"
  fi
done <<< "$hits"
exit 1
