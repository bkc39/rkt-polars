#!/usr/bin/env bash
set -euo pipefail

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=scripts/release/pins.sh
. "$here/pins.sh"
root=$(cd "$here/../.." && pwd)

usage() {
  echo "usage: catalog-test.sh PLATFORM DIST [--full]" >&2
  exit 2
}
[ $# -ge 2 ] && [ $# -le 3 ] || usage
platform=$1
dist=$(cd "$2" && pwd)
full=${3:-}
[ -z "$full" ] || [ "$full" = --full ] || usage
package=$(release_package "$platform")
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
unset RKT_POLARS_COMPAT_LIB_PATH PLTCOLLECTS || true
export PLTUSERHOME="$work/user"

host=$(racket -e '(display (system-library-subpath #f))')
version=$(racket -e '(display (version))')
echo "catalog test: Racket $version on $host, $package from $dist"
[[ $host == "$platform"* ]] || {
  echo "catalog test: $package is for $platform, and this host is $host" >&2
  exit 1
}

mkdir -p "$work/catalog/pkg" "$work/native" "$work/src"
unzip -q "$dist/$package.zip" -d "$work/native/$package"
cmp "$dist/$package.manifest.json" "$work/native/$package/manifest.json"
racket "$here/catalog.rkt" entry "$package" "$work/native/$package" "$dist/$package.zip" \
  "file://$dist/$package.zip" >"$work/catalog/pkg/$package"
read -ra catalogs <<<"$RELEASE_RACKET_CATALOGS"
raco pkg config --set --scope user catalogs "file://$work/catalog" "${catalogs[@]}"

release_tracked_copy "$root" polars "$work/src"
echo "catalog test: raco pkg install polars, which must pull $package by its #:platform dependency"
raco pkg install --batch --auto --no-docs --scope user --copy --name polars "$work/src/polars"

racket "$root/scripts/check-native-install.rkt" "$package"
racket -l racket/base -l polars -e '
  (define d (filter (dataframe (list (series (list 1 2 3) #:name "v"))) (> (col "v") 1)))
  (unless (equal? (series->list (ref d "v")) (list 2 3))
    (error (quote catalog-test) "filter gave ~a" d))
  (displayln d)'
racket "$root/scripts/check-bindings.rkt"

if [ -n "$full" ]; then
  echo "catalog test: docs and tests, as the package server runs them"
  raco pkg install --batch --auto --skip-installed --scope user threading-doc
  raco setup --check-pkg-deps --pkgs polars threading-doc
  DOCS_CHECK_PKG=polars "$root/scripts/docs-check.sh"
  raco test -x --timeout 600 -c polars
fi
echo "catalog test: passed"
