#!/usr/bin/env bash
# Usage: scripts/shell-lint.sh
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

status=0
hit() {
  local file=$1 line=$2 message=$3
  [ "$status" -eq 2 ] || status=1
  echo "$file:$line: $message"
  if [ -n "${GITHUB_ACTIONS:-}" ]; then
    echo "::error file=$file,line=$line::$message"
  fi
}

listed=0
files=$(find scripts -type f | LC_ALL=C sort) || listed=$?
if [ "$listed" -ne 0 ] || [ -z "$files" ]; then
  echo "shell-lint: cannot list scripts/ (find exited $listed)" >&2
  exit 2
fi

shells=()
while IFS= read -r file; do
  if [ ! -r "$file" ]; then
    echo "shell-lint: cannot read $file" >&2
    status=2
    continue
  fi
  start=$(head -c 2 "$file")
  if [ "$start" = '#!' ] && [ ! -x "$file" ]; then
    hit "$file" 1 "has a shebang but is not executable: chmod +x, and git add it"
  fi
  case $file in
    *.sh) shells+=("$file") ;;
    *) [ "$start" != '#!' ] || shells+=("$file") ;;
  esac
done <<< "$files"

scanned=0
# shellcheck disable=SC2016
negated=$(awk '
  BEGIN { OUTSIDE = "outside"; CONTINUED = "continued"; ENDED = "ended"; OPENED = "opened" }
  function strip(s) { sub(/^[ \t]+/, "", s); sub(/[ \t]+$/, "", s); return s }
  function scan(s,   i, c, t, quote, previous) {
    code = ""; bare = ""; quote = ""; previous = " "
    for (i = 1; i <= length(s); i++) {
      c = substr(s, i, 1)
      if (quote == "\047") {
        if (c == "\047") quote = ""
        code = code " "; bare = bare " "
      } else if (c == "\\") {
        t = substr(s, i, 2); i++
        code = code t; bare = bare (length(t) == 2 ? "  " : " ")
        previous = "\\"
      } else if (quote == "\"") {
        if (c == "\"") quote = ""
        code = code c; bare = bare " "
      } else if (c == "\047") {
        quote = c; code = code " "; bare = bare " "
      } else if (c == "\"") {
        quote = c; code = code c; bare = bare " "
      } else if (c == "#" && previous ~ /[ \t;]/) {
        break
      } else {
        code = code c; bare = bare c; previous = c
      }
    }
  }
  function report() { printf "%s:%d\n", FILENAME, FNR }
  function body(from,   rest) {
    rest = strip(substr(code, from))
    sub(/^;/, "", rest)
    rest = strip(rest)
    if (rest == "") state = OPENED
    else if (index(rest, "$?") > 0) report()
  }
  function condition(   at) {
    if (match(bare, /(^|;)[ \t]*(then|do)([ \t;]|$)/)) {
      at = RSTART + RLENGTH - 1
      if (substr(bare, at, 1) ~ /[ \t;]/) at--
      state = OUTSIDE
      body(at + 1)
    } else if (strip(code) ~ /(\\|\|\||&&|\|)$/) state = CONTINUED
    else state = ENDED
  }
  FNR == 1 { state = OUTSIDE }
  {
    scan($0)
    if (strip(code) == "") next
    if (state == OPENED) {
      state = OUTSIDE
      if (index(code, "$?") > 0) report()
      next
    }
    if (state == CONTINUED) { condition(); next }
    if (state == ENDED) {
      state = OUTSIDE
      if (bare ~ /^[ \t]*(then|do)([ \t;]|$)/) { condition(); next }
    }
    if (bare ~ /^[ \t]*(if|elif|while|until)[ \t]+![ \t]/) condition()
  }
' "${shells[@]}") || scanned=$?
if [ "$scanned" -ne 0 ]; then
  echo "shell-lint: awk failed (exit $scanned) on scripts/" >&2
  exit 2
fi
if [ -n "$negated" ]; then
  while IFS=: read -r file line; do
    hit "$file" "$line" "\$? here is the negated condition's status, not the command's: capture it first (cmd || st=\$?)"
  done <<< "$negated"
fi

if [ "$status" -eq 0 ]; then
  echo "shell-lint: none in scripts/ (${#shells[@]} shell scripts)"
fi
exit "$status"
