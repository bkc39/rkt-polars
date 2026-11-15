#!/usr/bin/env bash
# Usage: scripts/shell-lint.sh
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

for tool in shfmt jq; do
  if ! command -v "$tool" > /dev/null; then
    echo "shell-lint: $tool is not on PATH: run it under nix shell --inputs-from . nixpkgs#shfmt nixpkgs#jq" >&2
    exit 2
  fi
done

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

# shfmt gives an elif no Type, so a clause is matched by its shape.
negated='
  [ ..
    | objects
    | select((.Cond | type) == "array" and (.Cond | length) > 0)
    | select(.Cond[-1].Negated == true)
    | (.Then // .Do)
    | select(type == "array" and length > 0)
    | [.[0] | .. | objects | select(.Type == "ParamExp" and .Param.Value == "?")]
    | .[0] // empty
    | .Pos.Line ]
  | unique
  | .[]'

shells=0
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
    *.sh) ;;
    *) [ "$start" = '#!' ] || continue ;;
  esac
  shells=$((shells + 1))
  parsed=0
  # shellcheck disable=SC2094 # --filename only names the input in messages
  tree=$(shfmt -ln bash --filename "$file" --to-json < "$file" 2>&1) || parsed=$?
  if [ "$parsed" -ne 0 ]; then
    reason=${tree#"$file":}
    line=${reason%%:*}
    case $line in
      '' | *[!0-9]*) line=1 ;;
      *) reason=${reason#*:*: } ;;
    esac
    hit "$file" "$line" "shfmt cannot parse it: $reason"
    continue
  fi
  walked=0
  lines=$(jq -r "$negated" <<< "$tree") || walked=$?
  if [ "$walked" -ne 0 ]; then
    echo "shell-lint: jq failed (exit $walked) on $file" >&2
    status=2
    continue
  fi
  for line in $lines; do
    hit "$file" "$line" "\$? here is the negated condition's status, not the command's: capture it first (cmd || st=\$?)"
  done
done <<< "$files"

if [ "$status" -eq 0 ]; then
  echo "shell-lint: none in scripts/ ($shells shell scripts)"
fi
exit "$status"
