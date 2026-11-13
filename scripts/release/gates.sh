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
release_platform "$platform" || usage
gates=${*:-$RELEASE_GATES}
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
# reader GATE OUT COMMAND...: COMMAND's output in $scratch/OUT, or GATE fails with its error.
reader() {
  local gate=$1 out=$scratch/$2
  shift 2
  "$@" >"$out" 2>"$scratch/reader.err" && return 0
  fail "$gate" "$1 cannot read it: $(line "$(cat "$scratch/reader.err")")"
  return 1
}
dynamic() { sed -n "s/.*($1).*\[\(.*\)\]\$/\1/p" "$scratch/dynamic"; }
load_command() {
  awk -v want="$1" '
    $1 == "cmd" { take = ($2 == want); next }
    take && ($1 == "path" || $1 == "name") { print $2 }' "$scratch/load"
}
version_le() { [ "$(printf '%s\n%s\n' "$1" "$2" | sort -V | tail -n1)" = "$2" ]; }

gate_file() {
  local kind
  if [ ! -f "$lib" ]; then
    fail file "missing"
    return
  fi
  case $RELEASE_FORMAT in
    elf)
      reader file header readelf -h "$lib" || return 0
      reader file segments readelf -l "$lib" || return 0
      if ! release_grep -q '^ *Class: *ELF64$' "$scratch/header" ||
        ! release_grep -q '^ *Type: *DYN ' "$scratch/header" ||
        ! release_grep -qx " *Machine: *$RELEASE_MACHINE" "$scratch/header"; then
        fail file "not an $RELEASE_MACHINE ELF64 shared object"
      elif release_grep -q '^ *INTERP ' "$scratch/segments"; then
        fail file "has a PT_INTERP: an executable, not a shared object"
      fi
      ok file "$RELEASE_MACHINE ELF64 shared object"
      ;;
    macho)
      kind=$(file -b "$lib")
      if [[ $kind != *Mach-O\ 64-bit* || $kind != *"$RELEASE_MACHINE"* || $kind != *"dynamically linked shared library"* ]]; then
        fail file "not an $RELEASE_MACHINE Mach-O dylib: $kind"
      elif command -v codesign >/dev/null 2>&1 && ! codesign --verify "$lib" 2>"$scratch/codesign"; then
        fail file "its code signature does not verify: $(line "$(cat "$scratch/codesign")")"
      fi
      ok file "$RELEASE_MACHINE Mach-O dylib"
      ;;
  esac
}

gate_runpath() {
  local runpath rpath id bad
  case $RELEASE_FORMAT in
    elf)
      reader runpath dynamic readelf -d "$lib" || return 0
      runpath=$(dynamic RUNPATH)
      rpath=$(dynamic RPATH)
      { [ -z "$runpath" ] || [ "$runpath" = "$origin" ]; } && [ -z "$rpath" ] ||
        fail runpath "RUNPATH [$runpath] RPATH [$rpath], want none or RUNPATH \$ORIGIN"
      ok runpath "none outside \$ORIGIN"
      ;;
    macho)
      reader runpath load macho -l "$lib" || return 0
      id=$(load_command LC_ID_DYLIB)
      bad=$(load_command LC_RPATH | sed '/^@loader_path/d')
      [ "$id" = "@rpath/libcompat.dylib" ] || fail runpath "install name [$id], want @rpath/libcompat.dylib"
      [ -z "$bad" ] || fail runpath "LC_RPATH [$(line "$bad")] outside @loader_path"
      ok runpath "none outside @loader_path"
      ;;
  esac
}

first_paths() {
  release_matches -aoE "$1" "$lib" >"$scratch/paths"
  sort -u "$scratch/paths" | sed -n 1,3p
}

gate_store_paths() {
  local found
  found=$(first_paths '/nix/store/[A-Za-z0-9._+-]+')
  [ -z "$found" ] || fail store-paths "names $(line "$found")"
  ok store-paths "no /nix/store path"
}

gate_home_paths() {
  local found
  found=$(first_paths '/(home|Users|root)/[A-Za-z0-9._-]+')
  [ -z "$found" ] || fail home-paths "names $(line "$found"), a builder's home"
  ok home-paths "no /home, /Users or /root path"
}

gate_glibc() {
  local highest
  reader glibc symbols objdump -T "$lib" || return 0
  release_matches -oE 'GLIBC_[0-9]+(\.[0-9]+)+' "$scratch/symbols" >"$scratch/glibc"
  highest=$(sed 's/^GLIBC_//' "$scratch/glibc" | sort -V | tail -n1)
  if [ -z "$highest" ]; then
    fail glibc "no GLIBC_ symbol versions"
  elif ! version_le "$highest" "$RELEASE_GLIBC_MAX"; then
    fail glibc "GLIBC_$highest > $RELEASE_GLIBC_MAX"
  fi
  ok glibc "GLIBC_$highest <= $RELEASE_GLIBC_MAX"
}

gate_needed() {
  local actual allowed extra id
  case $RELEASE_FORMAT in
    elf)
      reader needed dynamic readelf -d "$lib" || return 0
      actual=$(dynamic NEEDED | sort -u)
      ;;
    macho)
      reader needed load macho -l "$lib" || return 0
      reader needed dylibs macho -L "$lib" || return 0
      id=$(load_command LC_ID_DYLIB)
      actual=$(sed -n '2,$s/^[[:space:]]*\([^ ]*\) (.*/\1/p' "$scratch/dylibs" |
        awk -v id="${id:-@rpath/libcompat.dylib}" '$0 != id' | sort -u)
      ;;
  esac
  allowed=$(sort -u <<<"$RELEASE_NEEDED")
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
  local host status=0 out=$scratch/exports.out why=$scratch/exports.why
  host=$(racket -e '(display (system-library-subpath #f))')
  if [[ $host != "$platform"* ]]; then
    fail exports "loads only on $platform, and this host is $host"
    return
  fi
  mkdir -p "$scratch/exports/lib"
  cp "$lib" "$scratch/exports/lib/$RELEASE_LIBRARY"
  RKT_POLARS_COMPAT_LIB_PATH="$scratch/exports" PLTCOLLECTS="$root:${PLTCOLLECTS:-}" \
    racket "$root/scripts/check-bindings.rkt" >"$out" 2>&1 || status=$?
  if [ "$status" -ne 0 ]; then
    release_matches -E '^(MISSING|FAILED)' "$out" >"$why"
    [ -s "$why" ] || sed -n 1,3p "$out" >"$why"
    fail exports "check-bindings.rkt exited $status: $(line "$(sed -n 1,5p "$why")")"
    return
  fi
  release_matches 'modules under polars/private instantiate' "$out" >"$why"
  ok exports "$(cat "$why")"
}

for gate in $gates; do
  if ! [[ " $RELEASE_GATES " == *" $gate "* ]]; then
    echo "gates.sh: no gate $gate for $platform (gates: $RELEASE_GATES)" >&2
    exit 2
  fi
  gate_failed=0
  "gate_${gate//-/_}"
done
exit "$failed"
