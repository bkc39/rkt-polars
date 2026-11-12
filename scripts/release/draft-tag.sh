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

native_tag_tree() {
  local ref="refs/tags/v$native" status=0
  if ! git -C "$root" rev-parse -q --verify "$ref" >/dev/null; then
    git -C "$root" ls-remote --exit-code --tags origin "$ref" >/dev/null || status=$?
    case $status in
      0) git -C "$root" fetch -q --depth 1 --no-tags origin "+$ref:$ref" ;;
      2)
        echo "draft-tag: $tag ships polars for native version $native, but origin has no tag v$native: tag v$native first" >&2
        exit 1
        ;;
      *)
        echo "draft-tag: cannot list origin's tags (git ls-remote exited $status)" >&2
        exit 1
        ;;
    esac
  fi
  git -C "$root" rev-parse "v$native^{commit}:rust"
}

case $tag in
  "v$native")
    echo "tag=$tag"
    echo "draft-tag: $tag drafts the native release $native" >&2
    ;;
  "v$polars")
    released=$(native_tag_tree)
    head=$(git -C "$root" rev-parse HEAD:rust)
    if [ "$released" != "$head" ]; then
      echo "draft-tag: rust/ changed since v$native (tree $released, HEAD's $head): bump native-version and tag that instead" >&2
      exit 1
    fi
    echo "tag="
    echo "draft-tag: $tag ships polars against the native release v$native, whose rust/ tree is HEAD's, so no native release is drafted" >&2
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
