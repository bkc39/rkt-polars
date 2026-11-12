#!/usr/bin/env bash
set -euo pipefail

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=scripts/release/pins.sh
. "$here/pins.sh"
root=$(cd "$here/../.." && pwd)

if [ $# -ne 4 ]; then
  echo "usage: package.sh PLATFORM ARTIFACT NOTICES DIST" >&2
  exit 2
fi
platform=$1
artifact=$(cd "$2" && pwd)
notices=$3
dist=$4
package=$(release_package "$platform")
library=$(release_library "$platform")
mkdir -p "$dist"
dist=$(cd "$dist" && pwd)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

if [ ! -s "$notices" ]; then
  echo "package: $notices is missing or empty; the native package ships the third-party notices" >&2
  exit 1
fi
racket -S "$root" "$root/scripts/stage-native-package.rkt" --notices "$notices" \
  "$platform" "$artifact/$library" "$work/$package"

manifest="$work/$package/manifest.json"
built=$(racket "$here/catalog.rkt" manifest "$manifest" rust_tree)
tree=$(git -C "$root" rev-parse HEAD:rust)
if [ "$built" != "$tree" ]; then
  echo "package: $package was built from rust/ tree $built, but this checkout's HEAD:rust is $tree" >&2
  exit 1
fi
version=$(racket "$here/catalog.rkt" manifest "$manifest" native_version)

rm -f "$dist/$package".*
raco pkg create --format zip --dest "$dist" "$work/$package"
racket "$here/catalog.rkt" entry "$package" "$work/$package" "$dist/$package.zip" \
  "$RELEASE_DOWNLOADS/v$version/$package.zip" >"$dist/$package.rktd"
cp "$manifest" "$dist/$package.manifest.json"
cp "$notices" "$dist/$RELEASE_NOTICES"
(
  cd "$dist"
  release_sha256 "$package.zip" "$package.zip.CHECKSUM" "$package.rktd" "$package.manifest.json" \
    "$RELEASE_NOTICES" >"$package.SHA256SUMS"
)
echo "package: $dist/$package.zip, native version $version, rust/ tree $built"
cat "$dist/$package.rktd"
