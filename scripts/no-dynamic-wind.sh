#!/usr/bin/env bash
#
# The no-dynamic-wind gate (#302): fails on dynamic-wind under polars/private
# and polars/tests outside polars/private/resource.rkt, whose with-release,
# with-releases, with-raw-buffer and with-release-pool pair every scoped
# resource, polars/tests/resource.rkt, whose audit plants sites, and the
# files polars/tests/dynamic-wind-sites.rktd lists.  A grep, so a form split
# across lines escapes it and a listed file may hold any site; the read-based
# audit in polars/tests/resource.rkt is the exact one, which holds each site
# to an entry for its definition and each entry to a site.  A name prefixed
# with a `:` (base:dynamic-wind) is a hit, but not the keyword #:dynamic-wind;
# any other prefix (rkt-dynamic-wind) or a rename-in or only-in rename is the
# audit's.
#
# Usage: scripts/no-dynamic-wind.sh
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

dirs=(polars/private polars/tests)
sites=polars/tests/dynamic-wind-sites.rktd
before='(^|[^-[:alnum:]!?*<>=/+:.$%&^~_]|(^|[^#]):)'
after='([^-[:alnum:]!?*<>=/+:.$%&^~_]|$)'

found=0
listed=$(sed -nE 's/^[[:space:](]*"([^"]+)".*/polars\/\1/p' "$sites") || found=$?
if [ "$found" -ne 0 ]; then
  echo "no-dynamic-wind: cannot read the listed sites in $sites (sed exit $found)" >&2
  exit 2
fi
exempt=$(printf '%s\n' polars/private/resource.rkt polars/tests/resource.rkt "$listed")

status=0
flag() {
  local form=$1 message=$2 hits found=0
  hits=$(grep -rnE --include='*.rkt' "$before$form$after" "${dirs[@]}") || found=$?
  if [ "$found" -gt 1 ]; then
    echo "no-dynamic-wind: grep failed (exit $found) on ${dirs[*]}" >&2
    status=2
    return 0
  fi
  hits=$(grep -vE '^[^:]+:[0-9]+:[[:space:]]*;' <<< "$hits" || true)
  [ -n "$hits" ] || return 0
  while IFS=: read -r file line _; do
    if grep -qxF -- "$file" <<< "$exempt"; then
      continue
    fi
    status=1
    echo "$file:$line: $message"
    if [ -n "${GITHUB_ACTIONS:-}" ]; then
      echo "::error file=$file,line=$line::$message"
    fi
  done <<< "$hits"
}

flag 'dynamic-wind' \
     "pair the resource with with-release, with-releases, with-raw-buffer or with-release-pool, or list the site in $sites"

if [ "$status" -eq 0 ]; then
  echo "no-dynamic-wind: none in ${dirs[*]} outside the resource.rkt files and $sites"
fi
exit "$status"
