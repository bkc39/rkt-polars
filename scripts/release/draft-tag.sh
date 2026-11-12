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
{
  read -r native
  read -r polars
} < <(racket "$here/catalog.rkt" info "$root/polars" native-version version)
for platform in $RELEASE_PLATFORMS; do
  release_platform "$platform"
  version=$(racket "$here/catalog.rkt" info "$root/native/$RELEASE_PACKAGE" version)
  if [ "$version" != "$native" ]; then
    echo "draft-tag: native/$RELEASE_PACKAGE/info.rkt is version $version, but polars/info.rkt's native-version is $native" >&2
    exit 1
  fi
done

published_tree() {
  local dir manifest status=0
  dir=$(mktemp -d)
  release_platform x86_64-linux
  manifest="$RELEASE_PACKAGE.manifest.json"
  if ! gh release download "v$native" -p "$manifest" -D "$dir" 2>"$dir/err"; then
    if [[ $(cat "$dir/err") == *"release not found"* ]]; then
      echo "draft-tag: $tag ships polars for native version $native, which has no published release: publish v$native first" >&2
    else
      echo "draft-tag: gh release download v$native $manifest failed: $(cat "$dir/err")" >&2
    fi
    rm -rf "$dir"
    exit 1
  fi
  racket "$here/catalog.rkt" manifest "$dir/$manifest" rust_tree || status=$?
  rm -rf "$dir"
  return "$status"
}

case $tag in
  "v$native")
    echo "tag=$tag"
    echo "draft-tag: $tag drafts the native release $native" >&2
    ;;
  "v$polars")
    released=$(published_tree)
    head=$(git -C "$root" rev-parse HEAD:rust)
    if [ "$released" != "$head" ]; then
      echo "draft-tag: rust/ changed since the published v$native (tree $released, HEAD's $head): bump native-version and tag that instead" >&2
      exit 1
    fi
    echo "tag="
    echo "draft-tag: $tag ships polars against the native release v$native, whose published rust/ tree is HEAD's, so no native release is drafted" >&2
    ;;
  "")
    echo "tag="
    echo "draft-tag: no tag, so no native release is drafted" >&2
    ;;
  *)
    echo "draft-tag: $tag names neither the native version (v$native) nor polars' (v$polars)" >&2
    exit 1
    ;;
esac
