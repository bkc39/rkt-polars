#!/usr/bin/env bash
#
# The no-dynamic-wind gate (#302): fails on dynamic-wind under polars/private
# and polars/tests outside polars/private/resource.rkt, whose with-release,
# with-releases, with-raw-buffer and with-release-pool pair every scoped
# resource.  A file may hold as many as polars/tests/dynamic-wind-sites.rktd
# lists for it, each a definition with its reason.  A grep, so a form split
# across lines escapes it; the read-based check in polars/tests/resource.rkt
# is the exact one, and holds each site to its definition.
#
# Usage: scripts/no-dynamic-wind.sh
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

dirs=(polars/private polars/tests)
exempt=polars/private/resource.rkt
sites=polars/tests/dynamic-wind-sites.rktd
after='([^-[:alnum:]!?*<>=/+:.$%&^~_]|$)'
message="pair the resource with with-release, with-releases, with-raw-buffer or with-release-pool, or list the site in $sites"

found=0
allowed=$(sed -nE 's/^[[:space:](]*"([^"]+)".*/polars\/\1/p' "$sites") || found=$?
if [ "$found" -ne 0 ]; then
  echo "no-dynamic-wind: cannot read the allowed sites in $sites (sed exit $found)" >&2
  exit 2
fi

found=0
hits=$(grep -rnE --include='*.rkt' "[[(][[:space:]]*dynamic-wind$after" "${dirs[@]}") || found=$?
if [ "$found" -gt 1 ]; then
  echo "no-dynamic-wind: grep failed (exit $found) on ${dirs[*]}" >&2
  exit 2
fi

offenders=$(awk -F: -v exempt="$exempt" '
  FILENAME == ARGV[1] { if ($0 != "") allowed[$0]++; next }
  $1 == "" || $1 == exempt { next }
  { text = $0; sub(/^[^:]+:[0-9]+:/, "", text) }
  text ~ /^[[:space:]]*;/ { next }
  { count[$1]++; at[$1] = at[$1] $1 ":" $2 "\n" }
  END { for (file in count) if (count[file] > allowed[file]) printf "%s", at[file] }
' <(printf '%s\n' "$allowed") <(printf '%s\n' "$hits") | sort -t: -k1,1 -k2,2n)

if [ -z "$offenders" ]; then
  echo "no-dynamic-wind: none in ${dirs[*]} but $exempt and the sites in $sites"
  exit 0
fi
while IFS=: read -r file line; do
  echo "$file:$line: $message"
  if [ -n "${GITHUB_ACTIONS:-}" ]; then
    echo "::error file=$file,line=$line::$message"
  fi
done <<< "$offenders"
exit 1
