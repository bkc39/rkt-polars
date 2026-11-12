#!/usr/bin/env bash
# shellcheck disable=SC2329
set -euo pipefail
export LC_ALL=C

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=scripts/release/pins.sh
. "$here/pins.sh"
root=$(cd "$here/../.." && pwd)

usage() {
  echo "usage: gates.sh PLATFORM LIBRARY [GATE...] (platforms: $RELEASE_PLATFORMS)" >&2
  exit 2
}
[ $# -ge 2 ] || usage
platform=$1
lib=$2
shift 2
case $platform in
  x86_64-linux) gate_names="file runpath store-paths home-paths glibc needed size exports" ;;
  aarch64-macosx) gate_names="file runpath store-paths home-paths needed size exports" ;;
  *) usage ;;
esac
gates=${*:-$gate_names}
scratch=$(mktemp -d)
trap 'rm -rf "$scratch"' EXIT

failed=0
gate_failed=0
# shellcheck disable=SC2016
origin='$ORIGIN'
ok() { [ "$gate_failed" -eq 1 ] || printf 'ok   %s: %s\n' "$1" "$2"; }
escape() {
  local s=${1//%/%25}
  s=${s//$'\r'/%0D}
  printf '%s' "${s//$'\n'/%0A}"
}
fail() {
  local message="$1 gate: $2"
  echo "$lib: $message"
  [ -z "${GITHUB_ACTIONS:-}" ] || printf '::error title=%s::%s\n' "$(escape "${lib##*/}")" "$(escape "$message")"
  gate_failed=1
  failed=1
}
warn() {
  echo "$lib: $1 gate: warning: $2"
  [ -z "${GITHUB_ACTIONS:-}" ] || printf '::warning title=%s::%s\n' "$(escape "${lib##*/}")" "$(escape "$1 gate: $2")"
}
line() { tr '\n' ' ' <<<"$1" | sed 's/ $//'; }
words() { tr ' ' '\n' <<<"$1" | sed '/^$/d' | sort -u; }

macho() {
  if command -v otool >/dev/null 2>&1; then
    otool "$@"
  else
    case $1 in
      -L) llvm-objdump --macho --dylibs-used "$2" ;;
      -l) llvm-objdump --macho --private-headers "$2" ;;
    esac
  fi
}
dynamic() { { readelf -d "$lib" 2>/dev/null || true; } | sed -n "s/.*($1).*\[\(.*\)\]\$/\1/p"; }
load_command() {
  { macho -l "$lib" 2>/dev/null || true; } | awk -v want="$1" '
    $1 == "cmd" { take = ($2 == want); next }
    take && ($1 == "path" || $1 == "name") { print $2 }'
}
version_le() { [ "$(printf '%s\n%s\n' "$1" "$2" | sort -V | tail -n1)" = "$2" ]; }

gate_file() {
  local header segments kind
  if [ ! -f "$lib" ]; then
    fail file "missing"
    return
  fi
  case $platform in
    x86_64-linux)
      header=$(readelf -h "$lib" 2>/dev/null) || true
      segments=$(readelf -l "$lib" 2>/dev/null) || true
      if ! grep -q '^ *Class: *ELF64$' <<<"$header" || ! grep -q '^ *Type: *DYN ' <<<"$header" ||
        ! grep -q '^ *Machine: *Advanced Micro Devices X86-64$' <<<"$header"; then
        fail file "not an x86-64 ELF64 shared object"
      elif grep -q '^ *INTERP ' <<<"$segments"; then
        fail file "has a PT_INTERP: an executable, not a shared object"
      fi
      ok file "x86-64 ELF64 shared object"
      ;;
    aarch64-macosx)
      kind=$(file -b "$lib")
      if [[ $kind != *Mach-O\ 64-bit* || $kind != *arm64* || $kind != *"dynamically linked shared library"* ]]; then
        fail file "not an arm64 Mach-O dylib: $kind"
      elif command -v codesign >/dev/null 2>&1 && ! codesign --verify "$lib" 2>"$scratch/codesign"; then
        fail file "its code signature does not verify: $(line "$(cat "$scratch/codesign")")"
      fi
      ok file "arm64 Mach-O dylib"
      ;;
  esac
}

gate_runpath() {
  local runpath rpath id bad
  case $platform in
    x86_64-linux)
      runpath=$(dynamic RUNPATH)
      rpath=$(dynamic RPATH)
      { [ -z "$runpath" ] || [ "$runpath" = "$origin" ]; } && [ -z "$rpath" ] ||
        fail runpath "RUNPATH [$runpath] RPATH [$rpath], want none or RUNPATH \$ORIGIN"
      ok runpath "none outside \$ORIGIN"
      ;;
    aarch64-macosx)
      id=$(load_command LC_ID_DYLIB)
      bad=$(load_command LC_RPATH | grep -v '^@loader_path' || true)
      [ "$id" = "@rpath/libcompat.dylib" ] || fail runpath "install name [$id], want @rpath/libcompat.dylib"
      [ -z "$bad" ] || fail runpath "LC_RPATH [$(line "$bad")] outside @loader_path"
      ok runpath "none outside @loader_path"
      ;;
  esac
}

gate_store_paths() {
  local found
  found=$(grep -aoE '/nix/store/[A-Za-z0-9._+-]+' "$lib" | sort -u | head -n 3 || true)
  [ -z "$found" ] || fail store-paths "names $(line "$found")"
  ok store-paths "no /nix/store path"
}

gate_home_paths() {
  local found
  found=$(grep -aoE '/(home|Users|root)/[A-Za-z0-9._-]+' "$lib" | sort -u | head -n 3 || true)
  [ -z "$found" ] || fail home-paths "names $(line "$found"), a builder's home"
  ok home-paths "no /home, /Users or /root path"
}

gate_glibc() {
  local highest
  highest=$({ objdump -T "$lib" 2>/dev/null || true; } | grep -oE 'GLIBC_[0-9]+(\.[0-9]+)+' |
    sed 's/^GLIBC_//' | sort -V | tail -n1)
  if [ -z "$highest" ]; then
    fail glibc "no GLIBC_ symbol versions"
  elif ! version_le "$highest" "$RELEASE_GLIBC_MAX"; then
    fail glibc "GLIBC_$highest > $RELEASE_GLIBC_MAX"
  fi
  ok glibc "GLIBC_$highest <= $RELEASE_GLIBC_MAX"
}

gate_needed() {
  local actual allowed extra id
  case $platform in
    x86_64-linux)
      actual=$(dynamic NEEDED | sort -u)
      allowed=$(words "$RELEASE_LINUX_NEEDED")
      ;;
    aarch64-macosx)
      id=$(load_command LC_ID_DYLIB)
      actual=$({ macho -L "$lib" 2>/dev/null || true; } | sed -n '2,$s/^[[:space:]]*\([^ ]*\) (.*/\1/p' |
        grep -vxF "${id:-@rpath/libcompat.dylib}" | sort -u || true)
      allowed=$(sort -u <<<"$RELEASE_DARWIN_NEEDED")
      ;;
  esac
  extra=$(comm -23 <(printf '%s\n' "$actual") <(printf '%s\n' "$allowed") | sed '/^$/d')
  [ -n "$actual" ] || fail needed "links no library"
  [ -z "$extra" ] || fail needed "links $(line "$extra"), outside the allow-list (scripts/release/pins.sh)"
  ok needed "$(line "$actual")"
}

gate_size() {
  local size
  size=$(wc -c <"$lib" | tr -d ' ')
  if [ "$size" -ge "$RELEASE_SIZE_LIMIT" ]; then
    fail size "$size bytes, at or over GitHub's $RELEASE_SIZE_LIMIT-byte file limit"
  elif [ "$size" -ge "$RELEASE_SIZE_WARN" ]; then
    warn size "$size bytes, within $((RELEASE_SIZE_LIMIT - size)) bytes of GitHub's $RELEASE_SIZE_LIMIT-byte file limit"
  fi
  ok size "$size bytes < $RELEASE_SIZE_LIMIT"
}

gate_exports() {
  local host out status=0
  host=$(racket -e '(display (system-library-subpath #f))')
  if [[ $host != "$platform"* ]]; then
    fail exports "loads only on $platform, and this host is $host"
    return
  fi
  mkdir -p "$scratch/exports/lib"
  cp "$lib" "$scratch/exports/lib/$(release_library "$platform")"
  out=$(RKT_POLARS_COMPAT_LIB_PATH="$scratch/exports" PLTCOLLECTS="$root:${PLTCOLLECTS:-}" \
    racket "$root/scripts/check-bindings.rkt" 2>&1) || status=$?
  [ "$status" -eq 0 ] ||
    fail exports "$(line "$(grep -E '^(MISSING|FAILED)' <<<"$out" | head -n 5 || echo "$out" | tail -n 3)")"
  ok exports "$(grep -E 'modules under polars/private instantiate' <<<"$out" || true)"
}

for gate in $gates; do
  if ! [[ " $gate_names " == *" $gate "* ]]; then
    echo "gates.sh: no gate $gate for $platform (gates: $gate_names)" >&2
    exit 2
  fi
  gate_failed=0
  "gate_${gate//-/_}"
done
exit "$failed"
