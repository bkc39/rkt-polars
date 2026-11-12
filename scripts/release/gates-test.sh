#!/usr/bin/env bash
set -euo pipefail

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=scripts/release/pins.sh
. "$here/pins.sh"
root=$(cd "$here/../.." && pwd)
if [ $# -ne 1 ]; then
  echo "usage: gates-test.sh LIBCOMPAT (a libcompat for this host that exports every binding)" >&2
  exit 2
fi
exporting=$(cd "$(dirname "$1")" && pwd)/$(basename "$1")
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
export NIX_DONT_SET_RPATH=1
for v in "${!NIX_LDFLAGS@}"; do
  [[ ! $v =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] || unset -v "$v"
done

failures=0
problem() {
  echo "gates-test: $*" >&2
  failures=1
}

gates() {
  local name=$1 platform=$2 lib=$3 status=0
  shift 3
  bash "$here/gates.sh" "$platform" "$lib" "$@" >"$work/$name.out" 2>&1 || status=$?
  echo "$status" >"$work/$name.status"
  sed "s|$work/||; s|^|$name: |" "$work/$name.out"
}
want_ok() {
  local name=$1 gate=$2
  grep -q "^ok *$gate: " "$work/$name.out" || problem "$name: want ok $gate"
}
want_fail() {
  local name=$1 gate=$2 reason=$3
  grep -F ": $gate gate: " "$work/$name.out" | grep -F -- "$reason" >/dev/null ||
    problem "$name: want $gate gate: ...$reason..."
  [ "$(cat "$work/$name.status")" = 1 ] || problem "$name: gates.sh exited $(cat "$work/$name.status"), want 1"
}
want_status() {
  [ "$(cat "$work/$1.status")" = "$2" ] || problem "$1: gates.sh exited $(cat "$work/$1.status"), want $2"
}

cat >"$work/stub.c" <<'EOF'
#include <stdlib.h>
void *rkt_stub(size_t n) { return malloc(n); }
EOF
cat >"$work/paths.c" <<'EOF'
const char *rkt_paths[] = {"/nix/store/0000-glibc/lib", "/home/runner/.cargo/registry",
                           "/Users/runner/.cargo/git", "/root/.cargo/registry", 0};
EOF
cat >"$work/random.c" <<'EOF'
#include <sys/random.h>
long rkt_random(void *b, unsigned long n) { return getrandom(b, n, 0); }
EOF
cc_shared() { "${CC:-cc}" -shared -fPIC -o "$@"; }

case $(uname -s) in
  Linux)
    p=x86_64-linux
    cc_shared "$work/plain.so" "$work/stub.c"
    gates plain "$p" "$work/plain.so"
    for gate in file runpath store-paths home-paths glibc needed size; do want_ok plain "$gate"; done
    want_fail plain exports "MISSING "

    gates exporting "$p" "$exporting" exports
    want_ok exporting exports
    want_status exporting 0

    cc_shared "$work/origin.so" "$work/stub.c" "-Wl,-rpath,\$ORIGIN"
    gates origin "$p" "$work/origin.so" runpath
    want_ok origin runpath
    cc_shared "$work/rpath.so" "$work/stub.c" -Wl,-rpath,/opt/lib
    gates rpath "$p" "$work/rpath.so" runpath
    want_fail rpath runpath "[/opt/lib]"

    cc_shared "$work/libother.so" "$work/stub.c"
    cc_shared "$work/needs.so" "$work/stub.c" -L"$work" -lother
    gates needs "$p" "$work/needs.so" needed
    want_fail needs needed "links libother.so, outside the allow-list"

    cc_shared "$work/random.so" "$work/random.c"
    gates random "$p" "$work/random.so" glibc
    want_fail random glibc "GLIBC_2.25 > $RELEASE_GLIBC_MAX"

    cc_shared "$work/paths.so" "$work/paths.c"
    gates paths "$p" "$work/paths.so" store-paths home-paths
    want_fail paths store-paths "names /nix/store/0000-glibc"
    want_fail paths home-paths "names /Users/runner /home/runner /root/.cargo"

    echo "not a library" >"$work/text.so"
    gates text "$p" "$work/text.so" file
    want_fail text file "not an x86-64 ELF64 shared object"
    "${CC:-cc}" -fPIE -pie -o "$work/exe.so" -x c - <<<'int main(void) { return 0; }'
    gates exe "$p" "$work/exe.so" file
    want_fail exe file "has a PT_INTERP"
    patch_byte() { printf '%b' "\\x$3" | dd of="$1" bs=1 seek="$2" conv=notrunc status=none; }
    cp "$work/plain.so" "$work/elf32.so"
    patch_byte "$work/elf32.so" 4 01
    gates elf32 "$p" "$work/elf32.so" file
    want_fail elf32 file "not an x86-64 ELF64 shared object"
    cp "$work/plain.so" "$work/aarch64.so"
    patch_byte "$work/aarch64.so" 18 b7
    gates aarch64 "$p" "$work/aarch64.so" file
    want_fail aarch64 file "not an x86-64 ELF64 shared object"
    gates absent "$p" "$work/absent.so" file
    want_fail absent file "missing"

    cp "$work/plain.so" "$work/big.so"
    truncate -s "$RELEASE_SIZE_LIMIT" "$work/big.so"
    gates big "$p" "$work/big.so" size
    want_fail big size "$RELEASE_SIZE_LIMIT bytes, at or over GitHub's"
    cp "$work/plain.so" "$work/near.so"
    truncate -s "$RELEASE_SIZE_WARN" "$work/near.so"
    gates near "$p" "$work/near.so" size
    want_ok near size
    want_status near 0
    grep -qF "size gate: warning: $RELEASE_SIZE_WARN bytes, within" "$work/near.out" || problem "near: want a size warning"

    gates on-linux aarch64-macosx "$work/plain.so" file exports
    want_fail on-linux file "not an arm64 Mach-O dylib"
    want_fail on-linux exports "loads only on aarch64-macosx"
    GITHUB_ACTIONS=true gates annotated "$p" "$work/rpath.so" runpath
    grep -qF "::error title=rpath.so::runpath gate: RUNPATH [/opt/lib]" "$work/annotated.out" ||
      problem "annotated: want a ::error annotation"
    ;;
  Darwin)
    p=aarch64-macosx
    dylib() { "${CC:-cc}" -dynamiclib -arch arm64 -o "$@"; }
    dylib "$work/plain.dylib" "$work/stub.c" -install_name @rpath/libcompat.dylib
    gates plain "$p" "$work/plain.dylib"
    for gate in file runpath store-paths home-paths needed size; do want_ok plain "$gate"; done
    want_fail plain exports "MISSING "
    gates exporting "$p" "$exporting" exports
    want_ok exporting exports
    dylib "$work/named.dylib" "$work/stub.c"
    gates named "$p" "$work/named.dylib" runpath
    want_fail named runpath "want @rpath/libcompat.dylib"
    dylib "$work/rpath.dylib" "$work/stub.c" -install_name @rpath/libcompat.dylib -Wl,-rpath,/opt/lib
    gates rpath "$p" "$work/rpath.dylib" runpath
    want_fail rpath runpath "LC_RPATH [/opt/lib]"
    dylib "$work/loader.dylib" "$work/stub.c" -install_name @rpath/libcompat.dylib -Wl,-rpath,@loader_path
    gates loader "$p" "$work/loader.dylib" runpath
    want_ok loader runpath
    dylib "$work/cocoa.dylib" "$work/stub.c" -install_name @rpath/libcompat.dylib -framework Cocoa
    gates cocoa "$p" "$work/cocoa.dylib" needed
    want_fail cocoa needed "Cocoa.framework"
    "${CC:-cc}" -dynamiclib -arch x86_64 -o "$work/x86.dylib" "$work/stub.c" -install_name @rpath/libcompat.dylib
    gates x86 "$p" "$work/x86.dylib" file
    want_fail x86 file "not an arm64 Mach-O dylib"
    cp "$work/plain.dylib" "$work/unsigned.dylib"
    codesign --remove-signature "$work/unsigned.dylib"
    gates unsigned "$p" "$work/unsigned.dylib" file
    want_fail unsigned file "code signature does not verify"
    ;;
  *) problem "no gate fixtures for $(uname -s)" ;;
esac

gates unknown x86_64-linux "$exporting" glibcxx
want_status unknown 2

tree="$work/tree"
mkdir -p "$tree/polars" "$tree/native/polars-x86_64-linux" "$tree/native/polars-aarch64-macosx"
info() {
  printf '#lang info\n(define version "%s")\n' "$2" >"$tree/native/polars-$1/info.rkt"
}
printf '#lang setup/infotab\n(define native-version "0.3")\n(define version "0.3.1")\n' >"$tree/polars/info.rkt"
info x86_64-linux 0.3
info aarch64-macosx 0.3
draft_case() {
  local tag=$1 want=$2 got
  got=$(RELEASE_ROOT=$tree bash "$here/draft-tag.sh" "$tag" 2>/dev/null) || got="exit $?"
  [ "$got" = "$want" ] || problem "draft-tag: ${tag:-no tag} said $got, want $want"
}
draft_case v0.3 tag=v0.3
draft_case v0.3.1 tag=
draft_case "" tag=
draft_case v0.3.0 "exit 1"
draft_case v0.4 "exit 1"
info aarch64-macosx 0.2
draft_case v0.3 "exit 1"
msg=$(RELEASE_ROOT=$tree bash "$here/draft-tag.sh" v0.3 2>&1) || true
[[ $msg == *"native/polars-aarch64-macosx/info.rkt is version 0.2, but polars/info.rkt's native-version is 0.3"* ]] ||
  problem "draft-tag: a native skeleton behind native-version said $msg"
draft_case "" "exit 1"

workflow="$root/.github/workflows/release.yml"
grep -qF "needs.plan.outputs.tag != ''" "$workflow" ||
  problem "release.yml: the draft job does not wait for a tag draft-tag.sh names"
[ "$(grep -c 'contents: write' "$workflow")" = 1 ] ||
  problem "release.yml: want contents: write in the draft job alone"

host=$(racket -e '(display (system-library-subpath #f))')
case $host in
  x86_64-linux*) p=x86_64-linux ;;
  aarch64-macosx) p=aarch64-macosx ;;
  *) p="" ;;
esac
if [ -n "$p" ]; then
  package=$(release_package "$p")
  artifact="$work/artifact"
  mkdir -p "$artifact"
  cp "$exporting" "$artifact/$(release_library "$p")"
  git -C "$root" rev-parse HEAD:rust >"$artifact/rust-tree"
  git -C "$root" rev-parse HEAD >"$artifact/commit"
  echo "notices" >"$work/notices.txt"
  package_case() {
    local name=$1 status=0
    shift
    bash "$here/package.sh" "$p" "$artifact" "$@" >"$work/$name.out" 2>&1 || status=$?
    echo "$status" >"$work/$name.status"
  }
  package_case packaged "$work/notices.txt" "$work/dist"
  if [ "$(cat "$work/packaged.status")" != 0 ]; then
    problem "package: exited $(cat "$work/packaged.status"): $(tail -n 5 "$work/packaged.out")"
  else
    (cd "$work/dist" && release_sha256 -c --quiet "$package.SHA256SUMS") || problem "package: SHA256SUMS does not check"
    grep -qF "\"$RELEASE_DOWNLOADS/v0.3/$package.zip\"" "$work/dist/$package.rktd" ||
      problem "package: the catalog entry's source is not the release zip: $(cat "$work/dist/$package.rktd")"
    unzip -l "$work/dist/$package.zip" | grep -qF "$RELEASE_NOTICES" || problem "package: the zip lacks $RELEASE_NOTICES"
  fi
  package_case no-notices "$work/absent.txt" "$work/dist-none"
  grep -qF "absent.txt is missing or empty" "$work/no-notices.out" || problem "package: shipped no notices: $(cat "$work/no-notices.out")"
  echo 0000000000000000000000000000000000000000 >"$artifact/rust-tree"
  package_case other-tree "$work/notices.txt" "$work/dist-tree"
  grep -qF "was built from rust/ tree 0000000000000000000000000000000000000000, but this checkout's HEAD:rust is" \
    "$work/other-tree.out" || problem "package: another rust/ tree said $(cat "$work/other-tree.out")"
  [ "$(cat "$work/other-tree.status")" = 1 ] || problem "package: another rust/ tree exited $(cat "$work/other-tree.status")"
fi

[ "$failures" -eq 0 ] && echo "gates-test: ok"
exit "$failures"
