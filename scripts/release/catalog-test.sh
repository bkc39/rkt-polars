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
release_platform "$platform"
package=$RELEASE_PACKAGE
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
unset RKT_POLARS_COMPAT_LIB_PATH PLTCOLLECTS
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
racket "$here/catalog.rkt" local-entry "$dist/$package.rktd" "file://$dist/$package.zip" \
  >"$work/catalog/pkg/$package"
listed=$(release_catalogs)
catalogs=()
while IFS= read -r catalog; do catalogs+=("$catalog"); done <<<"$listed"
release_tracked_copy "$root" polars "$work/src"

# install_polars USERHOME CATALOG LOG: the tracked polars from CATALOG, in front of the others.
install_polars() {
  PLTUSERHOME=$1 raco pkg config --set --scope user catalogs "file://$2" "${catalogs[@]}"
  PLTUSERHOME=$1 raco pkg install --batch --auto --no-docs --scope user --copy --name polars \
    "$work/src/polars" 2>&1 | tee "$3"
}

tampered="$work/tampered"
mkdir -p "$tampered/catalog/pkg" "$tampered/dist"
cp -R "$work/native/$package" "$tampered/$package"
zeros=$(printf '%064d' 0)
sed -E "s/\"[0-9a-f]{64}\"/\"$zeros\"/" "$work/native/$package/manifest.json" \
  >"$tampered/$package/manifest.json"
if cmp -s "$work/native/$package/manifest.json" "$tampered/$package/manifest.json"; then
  echo "catalog test: $package's manifest.json lists no sha256 to tamper with" >&2
  exit 1
fi
raco pkg create --format zip --dest "$tampered/dist" "$tampered/$package"
racket "$here/catalog.rkt" entry "$package" "$tampered/$package" "$tampered/dist/$package.zip" \
  "file://$tampered/dist/$package.zip" >"$tampered/catalog/pkg/$package"
echo "catalog test: raco pkg install polars over a $package whose manifest lists another sha256 must fail"
status=0
install_polars "$tampered/user" "$tampered/catalog" "$tampered/install.log" || status=$?
if [ "$status" -eq 0 ]; then
  echo "catalog test: polars installed over a $package whose manifest does not match its library" >&2
  exit 1
fi
release_grep -qF "in the package $package has sha256" "$tampered/install.log" || {
  echo "catalog test: the install over a tampered $package failed (exit $status), but not on its manifest" >&2
  exit 1
}

echo "catalog test: raco pkg install polars, which must pull $package by its #:platform dependency"
install_polars "$PLTUSERHOME" "$work/catalog" "$work/install.log"
release_check_install_log "$work/install.log"

racket "$root/scripts/check-native-install.rkt" "$package"
racket "$here/catalog-check.rkt" installed "$package" "$work/native/$package"
racket "$root/scripts/check-bindings.rkt"

if [ -n "$full" ]; then
  echo "catalog test: docs and tests, as the package server runs them"
  raco pkg install --batch --auto --skip-installed --scope user threading-doc
  raco setup --check-pkg-deps --pkgs polars threading-doc
  DOCS_CHECK_PKG=polars "$root/scripts/docs-check.sh"
  raco test -e --timeout 600 -c polars
fi
echo "catalog test: passed"
