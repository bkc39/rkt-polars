#!/usr/bin/env bash
# Fails on a bash 4 construct in what the macOS release jobs run, whose
# /bin/bash is 3.2.
set -uo pipefail

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
if [ $# -gt 0 ]; then
  files=("$@")
else
  files=()
  for file in "$root"/scripts/release/*.sh; do
    [ "$file" = "$root/scripts/release/bash3.sh" ] || files+=("$file")
  done
  files+=("$root/scripts/dependency-catalogs.sh" "$root/scripts/docs-check.sh"
    "$root/.github/workflows/release.yml" "$root/.github/actions/install-racket/action.yml")
fi
pattern='\b(mapfile|readarray|coproc)\b|\b(declare|local|typeset) +-[a-zA-Z]*[An]|\$\{[!#]?[A-Za-z_][A-Za-z0-9_]*(\[[^]]*\])?(,,?|\^\^?)|;;?&|\|&|\[\[ +-v '
status=0
grep -HnE -- "$pattern" "${files[@]}" || status=$?
case $status in
  0)
    echo "bash3: the lines above need bash 4; the macOS release jobs run bash 3.2" >&2
    exit 1
    ;;
  1) echo "bash3: ok (${#files[@]} files)" ;;
  *)
    echo "bash3: grep exited $status" >&2
    exit 2
    ;;
esac
