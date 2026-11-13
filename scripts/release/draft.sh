#!/usr/bin/env bash
set -euo pipefail

if [ $# -ne 3 ]; then
  echo "usage: draft.sh TAG SHA DIST (GH_REPO names the repository)" >&2
  exit 2
fi
tag=$1
sha=$2
dist=$3
err=$(mktemp)
trap 'rm -f "$err"' EXIT

tagged=$(gh api "repos/$GH_REPO/commits/$tag" --jq .sha)
if [ "$tagged" != "$sha" ]; then
  echo "draft: $tag is commit $tagged now, but this run built $sha" >&2
  exit 1
fi
if gh release view "$tag" >/dev/null 2>"$err"; then
  echo "draft: $tag already has a release; a native version is released once" >&2
  exit 1
elif [[ $(cat "$err") != *"release not found"* ]]; then
  echo "draft: gh release view $tag failed: $(cat "$err")" >&2
  exit 1
fi

packages=()
for zip in "$dist"/polars-*.zip; do
  [ -f "$zip" ] || break
  packages+=("$(basename "$zip" .zip)")
done
if [ ${#packages[@]} -eq 0 ]; then
  echo "draft: $dist holds no polars-*.zip" >&2
  exit 1
fi
gh release create "$tag" --draft --verify-tag --title "$tag" \
  --notes "Native packages ${packages[*]} $tag, their catalog entries, manifests and checksums" \
  "$dist"/*
