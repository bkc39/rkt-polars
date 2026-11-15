#!/usr/bin/env bash
#
# The shell-lint gate (#332): fails on a file under scripts/ that starts with
# a shebang and is not executable, and on a `$?` that a negated condition
# (`if ! cmd; then`, `elif !`, `while !`) hands its body: there `$?` is the
# negation's status, so a failure always reports 0.  Capture the command's
# status first, `cmd || st=$?`.  The status rule reads the first command of
# the body, on the line that opens it or the next.  A file it cannot read
# fails with 2.
#
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

found=0
files=$(find scripts -type f | LC_ALL=C sort) || found=$?
if [ "$found" -ne 0 ] || [ -z "$files" ]; then
  echo "shell-lint: cannot list scripts/ (find exited $found)" >&2
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

# shellcheck disable=SC2016
negated=$(awk '
  function strip(s) { sub(/^[ \t]+/, "", s); sub(/[ \t]+$/, "", s); return s }
  function body(s, pos, rest) {
    rest = strip(substr(s, pos))
    sub(/^;/, "", rest)
    rest = strip(rest)
    if (rest == "") state = 2
    else if (index(rest, "$?") > 0) printf "%s:%d\n", FILENAME, FNR
  }
  function keyword(s, at) { return substr(s, at, 4) == "then" ? 4 : 2 }
  function condition(s) {
    if (match(s, /(^|[; \t])(then|do)([ \t;]|$)/)) {
      if (substr(s, RSTART, 1) ~ /[; \t]/) RSTART++
      state = 0
      body(s, RSTART + keyword(s, RSTART))
    } else if (s ~ /(\\|\|\||&&|\|)$/) state = 1
    else state = 3
  }
  FNR == 1 { state = 0 }
  {
    line = strip($0)
    if (line == "" || substr(line, 1, 1) == "#") next
    if (state == 2) {
      state = 0
      if (index(line, "$?") > 0) printf "%s:%d\n", FILENAME, FNR
      next
    }
    if (state == 1) { condition(line); next }
    if (state == 3) {
      state = 0
      if (line ~ /^(then|do)([ \t;]|$)/) { condition(line); next }
    }
    if (line ~ /^(if|elif|while)[ \t]+![ \t]/) condition(line)
  }
' "${shells[@]}") || found=$?
if [ "$found" -ne 0 ]; then
  echo "shell-lint: awk failed (exit $found) on scripts/" >&2
  exit 2
fi
if [ -n "$negated" ]; then
  while IFS=: read -r file line; do
    hit "$file" "$line" "\$? here is the negated condition's status, always 0: capture it first (cmd || st=\$?)"
  done <<< "$negated"
fi

if [ "$status" -eq 0 ]; then
  echo "shell-lint: none in scripts/ (${#shells[@]} shell scripts)"
fi
exit "$status"
