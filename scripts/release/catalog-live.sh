#!/usr/bin/env bash
set -euo pipefail

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=scripts/release/pins.sh
. "$here/pins.sh"

if [ $# -lt 1 ]; then
  echo "usage: catalog-live.sh PLATFORM [CATALOG...] (default catalog: https://pkgs.racket-lang.org)" >&2
  exit 2
fi
platform=$1
shift
[ $# -gt 0 ] || set -- https://pkgs.racket-lang.org
release_platform "$platform"
package=$RELEASE_PACKAGE
downloads=${CATALOG_LIVE_DOWNLOADS:-$RELEASE_DOWNLOADS}
check="$here/catalog-check.rkt"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
unset RKT_POLARS_COMPAT_LIB_PATH PLTCOLLECTS
export PLTUSERHOME="$work/user"

host=$(racket "$check" host)
echo "catalog live: Racket $(racket "$check" racket-version) on $host, polars and $package from $*"
[ "$(release_host_platform "$host")" = "$platform" ] || {
  echo "catalog live: $package is for $platform, and this host is $host" >&2
  exit 1
}

racket "$check" catalog "$package" "$downloads" "$@"
raco pkg config --set --scope user catalogs "$@"
raco pkg install --batch --auto --scope user polars 2>&1 | tee "$work/install.log"
release_check_install_log "$work/install.log"

polars=$(racket "$check" pkg-directory polars)
native=$(racket "$here/catalog.rkt" info "$polars" native-version)
zip="$downloads/v$native/$package.zip"
echo "catalog live: the published $zip"
fetched=$(release_fetch "$zip" unchecked "$work")
unzip -q "$fetched" -d "$work/release"
racket "$check" installed "$package" "$work/release"
echo "catalog live: passed"
