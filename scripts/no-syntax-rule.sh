#!/usr/bin/env bash
#
# The no-syntax-rule gate: fails on any define-syntax-rule or syntax-rules in
# the Racket sources.  Macros are define-syntax-parse-rule or
# define-syntax-parser, so pattern variables can carry syntax classes;
# lint/ rewrites the uses it can prove equivalent, and this catches the rest.
#
# Usage: scripts/no-syntax-rule.sh
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

dirs=(polars examples user-guide bench scripts)
# A `prefix:` from prefix-in may come before the name.
before='(^|[^-[:alnum:]!?*<>=/+.$%&^~_])'
after='([^-[:alnum:]!?*<>=/+:.$%&^~_]|$)'

status=0
flag() {
  local form=$1 message=$2 hits
  hits=$(grep -rnE --include='*.rkt' --include='*.scrbl' \
           "$before$form$after" "${dirs[@]}" || true)
  [ -n "$hits" ] || return 0
  status=1
  while IFS=: read -r file line _; do
    echo "$file:$line: $message"
    if [ -n "${GITHUB_ACTIONS:-}" ]; then
      echo "::error file=$file,line=$line::$message"
    fi
  done <<< "$hits"
}

flag define-syntax-rule "use define-syntax-parse-rule (require syntax/parse/define)"
flag syntax-rules "use define-syntax-parse-rule or define-syntax-parser (require syntax/parse/define)"

if [ "$status" -eq 0 ]; then
  echo "no-syntax-rule: none in ${dirs[*]}"
fi
exit "$status"
