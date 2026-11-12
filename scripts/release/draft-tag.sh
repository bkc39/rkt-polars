#!/usr/bin/env bash
set -euo pipefail

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=scripts/release/pins.sh
. "$here/pins.sh"
root=${RELEASE_ROOT:-$(cd "$here/../.." && pwd)}

if [ $# -ne 1 ]; then
  echo "usage: draft-tag.sh TAG" >&2
  exit 2
fi
tag=$1
native=$(release_info_version "$root/polars/info.rkt" native-version)
polars=$(release_info_version "$root/polars/info.rkt" version)
for platform in $RELEASE_PLATFORMS; do
  package=$(release_package "$platform")
  version=$(release_info_version "$root/native/$package/info.rkt" version)
  if [ "$version" != "$native" ]; then
    echo "draft-tag: native/$package/info.rkt is version $version, but polars/info.rkt's native-version is $native" >&2
    exit 1
  fi
done
case $tag in
  "v$native")
    echo "tag=$tag"
    echo "draft-tag: $tag drafts the native release $native" >&2
    ;;
  "" | "v$polars")
    echo "tag="
    echo "draft-tag: ${tag:-no tag} is not v$native, so no native release is drafted" >&2
    ;;
  *)
    echo "draft-tag: $tag names neither the native version (v$native) nor polars' (v$polars)" >&2
    exit 1
    ;;
esac
