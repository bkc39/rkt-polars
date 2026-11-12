# shellcheck shell=bash
# shellcheck disable=SC2034

RELEASE_DOWNLOADS="https://github.com/bkc39/rkt-polars/releases/download"
RELEASE_PLATFORMS="x86_64-linux aarch64-macosx"

RELEASE_RACKET_VERSION=9.3
RELEASE_RACKET_CATALOGS="https://download.racket-lang.org/releases/9.3/catalog/ https://pkgs.racket-lang.org"

RELEASE_PKG_BUILD_IMAGE="racket/pkg-build:deps-x86_64@sha256:5e145ffdc1d1aad1f1f01b1e1de259b3b1fd6550c879b104bbd7372d53f58f34"
RELEASE_NATIPKG_RACKET="https://download.racket-lang.org/releases/9.3/installers/racket-9.3-x86_64-linux-natipkg-cs.sh"
RELEASE_NATIPKG_RACKET_SHA256="399b3926061ab99121586d1c508435fb3351f1d96473791ed99ba139eba54e06"

RELEASE_GLIBC_MAX=2.17
RELEASE_SIZE_LIMIT=104857600
RELEASE_SIZE_WARN=99614720
RELEASE_LINUX_NEEDED="ld-linux-x86-64.so.2 libc.so.6 libdl.so.2 libgcc_s.so.1 libm.so.6 libpthread.so.0 librt.so.1"
RELEASE_DARWIN_NEEDED="/System/Library/Frameworks/CoreFoundation.framework/Versions/A/CoreFoundation
/System/Library/Frameworks/IOKit.framework/Versions/A/IOKit
/System/Library/Frameworks/Security.framework/Versions/A/Security
/usr/lib/libSystem.B.dylib
/usr/lib/libiconv.2.dylib"
RELEASE_NOTICES=THIRD-PARTY-NOTICES.txt

release_package() {
  case $1 in
    x86_64-linux) echo polars-x86_64-linux ;;
    aarch64-macosx) echo polars-aarch64-macosx ;;
    *)
      echo "release: no native package for platform $1 (platforms: $RELEASE_PLATFORMS)" >&2
      return 1
      ;;
  esac
}

release_library() {
  case $1 in
    x86_64-linux) echo libcompat.so ;;
    aarch64-macosx) echo libcompat.dylib ;;
    *) return 1 ;;
  esac
}

release_info_version() {
  local found
  found=$(sed -n "s/^(define $2 \"\\(.*\\)\")\$/\\1/p" "$1")
  if [ -z "$found" ]; then
    echo "release: $1 has no (define $2 \"...\")" >&2
    return 1
  fi
  printf '%s\n' "$found"
}

release_fetch() {
  local url=$1 sha=$2 dir=$3
  local file="$dir/${url##*/}"
  mkdir -p "$dir" || return 1
  if [ -f "$file" ] && echo "$sha  $file" | sha256sum -c --status; then
    printf '%s\n' "$file"
    return 0
  fi
  rm -f "$file"
  curl -fsSL --retry 3 -o "$file.part" "$url" || {
    echo "release_fetch: $url: download failed" >&2
    rm -f "$file.part"
    return 1
  }
  echo "$sha  $file.part" | sha256sum -c --status || {
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
