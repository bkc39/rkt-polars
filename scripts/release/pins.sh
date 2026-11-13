# shellcheck shell=bash
# shellcheck disable=SC2034

RELEASE_DOWNLOADS="https://github.com/bkc39/rkt-polars/releases/download"
RELEASE_PLATFORMS="x86_64-linux aarch64-macosx"

RELEASE_RACKET_VERSION=9.3

RELEASE_PKG_BUILD_IMAGE="racket/pkg-build:deps-x86_64@sha256:5e145ffdc1d1aad1f1f01b1e1de259b3b1fd6550c879b104bbd7372d53f58f34"
RELEASE_NATIPKG_RACKET="https://download.racket-lang.org/releases/$RELEASE_RACKET_VERSION/installers/racket-$RELEASE_RACKET_VERSION-x86_64-linux-natipkg-cs.sh"
RELEASE_NATIPKG_RACKET_SHA256="399b3926061ab99121586d1c508435fb3351f1d96473791ed99ba139eba54e06"

RELEASE_GLIBC_MAX=2.17
RELEASE_SIZE_LIMIT=104857600
RELEASE_SIZE_WARN=99614720
RELEASE_NOTICES=THIRD-PARTY-NOTICES.txt
RELEASE_SCRIPTS=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)

# Sets RELEASE_PACKAGE, RELEASE_LIBRARY, RELEASE_GATES and RELEASE_NEEDED for $1.
release_platform() {
  case $1 in
    x86_64-linux)
      RELEASE_PACKAGE=polars-x86_64-linux
      RELEASE_LIBRARY=libcompat.so
      RELEASE_GATES="file runpath store-paths home-paths glibc needed size exports"
      RELEASE_NEEDED="ld-linux-x86-64.so.2
libc.so.6
libdl.so.2
libgcc_s.so.1
libm.so.6
libpthread.so.0
librt.so.1"
      ;;
    aarch64-macosx)
      RELEASE_PACKAGE=polars-aarch64-macosx
      RELEASE_LIBRARY=libcompat.dylib
      RELEASE_GATES="file runpath store-paths home-paths needed size exports"
      RELEASE_NEEDED="/System/Library/Frameworks/CoreFoundation.framework/Versions/A/CoreFoundation
/System/Library/Frameworks/IOKit.framework/Versions/A/IOKit
/System/Library/Frameworks/Security.framework/Versions/A/Security
/usr/lib/libSystem.B.dylib
/usr/lib/libiconv.2.dylib"
      ;;
    *)
      echo "release: no native package for platform ${1:-(none)} (platforms: $RELEASE_PLATFORMS)" >&2
      return 1
      ;;
  esac
}

# grep over files: 0 on a match, 1 on none, and an error (2) exits the script.
release_grep() {
  local status=0
  grep "$@" || status=$?
  if [ "$status" -gt 1 ]; then
    echo "release: grep $* exited $status" >&2
    exit 2
  fi
  return "$status"
}
release_matches() { release_grep "$@" || return 0; }

# Fails when the install log $1 holds the pre-installer's warning that no
# native package is installed, which leaves its manifest unchecked.
release_check_install_log() {
  if release_grep -qF "libcompat is not installed" "$1"; then
    echo "release: the pre-installer found no native package, so no manifest was checked (log: $1)" >&2
    return 1
  fi
}

release_catalogs() {
  local listed kept status=0
  listed=$(bash "$RELEASE_SCRIPTS/dependency-catalogs.sh") || return 1
  kept=$(grep -vE '^https://download\.racket-lang\.org/' <<<"$listed") || status=$?
  case $status in
    0) printf '%s\n' "$kept" ;;
    1)
      echo "release: the only dependency catalog configured is download.racket-lang.org's [$(tr '\n' ' ' <<<"$listed")], which a release test never reads (#124)" >&2
      return 1
      ;;
    *) return 2 ;;
  esac
}

release_fetch() {
  local url=$1 sha=$2 dir=$3
  local file="$dir/${url##*/}"
  mkdir -p "$dir" || return 1
  if [ -f "$file" ] && echo "$sha  $file" | release_sha256 -c --status; then
    printf '%s\n' "$file"
    return 0
  fi
  rm -f "$file"
  curl -fsSL --retry 3 -o "$file.part" "$url" || {
    echo "release_fetch: $url: download failed" >&2
    rm -f "$file.part"
    return 1
  }
  echo "$sha  $file.part" | release_sha256 -c --status || {
    echo "release_fetch: $url: sha256 is not $sha" >&2
    rm -f "$file.part"
    return 1
  }
  mv "$file.part" "$file"
  printf '%s\n' "$file"
}

release_tracked_copy() {
  local paths
  read -ra paths <<<"$2"
  git -C "$1" ls-files -z -- "${paths[@]}" | tar -C "$1" --null -T - -cf - | tar -C "$3" -xf -
}

release_sha256() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$@"
  else
    shasum -a 256 "$@"
  fi
}
