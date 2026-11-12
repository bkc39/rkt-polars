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
    cc_shared "$work/needs.so" "$work/stub.c" -L"$work" -Wl,--no-as-needed -lother
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
    gates text "$p" "$work/text.so" file runpath glibc needed
    want_fail text file "readelf cannot read it: readelf: Error: "
    for gate in runpath glibc needed; do want_fail text "$gate" "cannot read it"; done
    gates garbage "$p" "$work/text.so" exports
    want_fail garbage exports "check-bindings.rkt exited 1: "
    grep -qE 'exports gate: check-bindings.rkt exited 1: .+' "$work/garbage.out" ||
      problem "garbage: the exports gate gave no reason"
    cp "$work/plain.so" "$work/unreadable.so"
    chmod 000 "$work/unreadable.so"
    if [ ! -r "$work/unreadable.so" ]; then
      gates unreadable "$p" "$work/unreadable.so" store-paths
      want_status unreadable 2
      grep -qF "release: grep -aoE" "$work/unreadable.out" || problem "unreadable: want grep's failure named"
    fi
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

mkdir -p "$work/stub-bin"
cat >"$work/stub-bin/raco" <<'EOF'
#!/usr/bin/env bash
cat "$CATALOGS"
EOF
cat >"$work/stub-bin/gh" <<'EOF'
#!/usr/bin/env bash
echo "gh $*" >>"$GH_LOG"
case $1 in
  api) echo "$GH_TAGGED" ;;
  release)
    case $2 in
      view)
        case $GH_VIEW in
          missing) echo "release not found" >&2; exit 1 ;;
          present) echo "title: v0.3" ;;
          *) echo "HTTP 502" >&2; exit 1 ;;
        esac
        ;;
      download)
        case $GH_PUBLISHED in
          missing) echo "release not found" >&2; exit 1 ;;
          error) echo "HTTP 502" >&2; exit 1 ;;
          *) printf '{"native_version":"0.3","rust_tree":"%s"}\n' "$GH_PUBLISHED" >"$7/$5" ;;
        esac
        ;;
      create) ;;
    esac
    ;;
esac
EOF
chmod +x "$work/stub-bin/raco" "$work/stub-bin/gh"

tree="$work/tree"
g() {
  git -C "$tree" -c user.name=gates-test -c user.email=gates-test@localhost -c commit.gpgsign=false \
    -c core.hooksPath=/dev/null "$@"
}
mkdir -p "$tree/polars" "$tree/native/polars-x86_64-linux" "$tree/native/polars-aarch64-macosx" "$tree/rust"
git init -q "$tree"
info() {
  printf '#lang info\n(define version "%s")\n' "$2" >"$tree/native/polars-$1/info.rkt"
}
printf '#lang setup/infotab\n(define native-version "0.3")\n(define version "0.3.1")\n' >"$tree/polars/info.rkt"
info x86_64-linux 0.3
info aarch64-macosx 0.3
echo 1 >"$tree/rust/lib.rs"
g add -A
g commit -q -m native
released=$(g rev-parse HEAD:rust)
draft_case() {
  local tag=$1 want=$2 published=${3:-$released} got
  : >"$work/draft.gh"
  got=$(PATH="$work/stub-bin:$PATH" GH_LOG="$work/draft.gh" GH_PUBLISHED=$published RELEASE_ROOT=$tree \
    bash "$here/draft-tag.sh" "$tag" 2>"$work/draft.err") || got="exit $?"
  [ "$got" = "$want" ] || problem "draft-tag: ${tag:-no tag} said $got, want $want: $(cat "$work/draft.err")"
}
draft_said() {
  [[ $(cat "$work/draft.err") == *"$1"* ]] || problem "draft-tag: want ...$1..., got $(cat "$work/draft.err")"
}
draft_case v0.3 tag=v0.3
echo docs >"$tree/polars/README"
g add -A
g commit -q -m racket
draft_case v0.3.1 tag=
grep -qF "gh release download v0.3 -p polars-x86_64-linux.manifest.json -D " "$work/draft.gh" ||
  problem "draft-tag: v0.3.1 did not read v0.3's published manifest: $(cat "$work/draft.gh")"
draft_case "" tag=
draft_case v0.3.0 "exit 1"
draft_case v0.4 "exit 1"
draft_case v0.3.1 "exit 1" 0000000000000000000000000000000000000000
draft_said "rust/ changed since the published v0.3 (tree 0000000000000000000000000000000000000000"
echo 2 >"$tree/rust/lib.rs"
g commit -q -am rust
draft_case v0.3.1 "exit 1"
draft_said "rust/ changed since the published v0.3"
draft_case "" tag=
draft_case v0.3.1 "exit 1" missing
draft_said "which has no published release: publish v0.3 first"
draft_case v0.3.1 "exit 1" error
draft_said "gh release download v0.3 polars-x86_64-linux.manifest.json failed: HTTP 502"
info aarch64-macosx 0.2
draft_case v0.3 "exit 1"
draft_said "native/polars-aarch64-macosx/info.rkt is version 0.2, but polars/info.rkt's native-version is 0.3"
draft_case "" "exit 1"

catalogs_case() {
  local name=$1 want=$2 got
  printf '%s\n' "$3" >"$work/catalogs.txt"
  got=$(PATH="$work/stub-bin:$PATH" CATALOGS="$work/catalogs.txt" release_catalogs 2>"$work/catalogs.err") || got="exit $?"
  [ "$got" = "$want" ] || problem "release_catalogs: $name gave [$got], want [$want]: $(cat "$work/catalogs.err")"
}
release_downloads=https://download.racket-lang.org/releases/9.3/catalog/
catalogs_case both https://pkgs.racket-lang.org "$release_downloads
https://pkgs.racket-lang.org
https://racket.github.io/rhombus-pkgs/catalog/"
catalogs_case pkgs https://pkgs.racket-lang.org https://pkgs.racket-lang.org
catalogs_case downloads-only "exit 1" "$release_downloads"
grep -qF "(#124)" "$work/catalogs.err" || problem "release_catalogs: downloads-only said $(cat "$work/catalogs.err")"

install_log_case() {
  local name=$1 want=$2 status=0
  (release_check_install_log "$work/$name.log") >"$work/$name.out" 2>&1 || status=$?
  [ "$status" = "$want" ] || problem "release_check_install_log: $name exited $status, want $want: $(cat "$work/$name.out")"
}
printf 'raco setup: --- pre-installing collections ---\nraco setup: version: 9.3\n' >"$work/checked.log"
install_log_case checked 0
printf 'raco setup: --- pre-installing collections ---\npre-installer: libcompat is not installed: the package polars-x86_64-linux is missing\n' \
  >"$work/unchecked.log"
install_log_case unchecked 1
grep -qF "the pre-installer found no native package" "$work/unchecked.out" ||
  problem "release_check_install_log: an unchecked install said $(cat "$work/unchecked.out")"
install_log_case absent 2
for script in catalog-test.sh pkg-build-test.sh; do
  grep -qE '^ *release_check_install_log "?[$/a-z]+/install\.log"?$' "$here/$script" ||
    problem "$script: does not check its install log with release_check_install_log"
done
# shellcheck disable=SC2016
grep -qF 'in the package $package has sha256' "$here/catalog-test.sh" ||
  problem "catalog-test.sh: does not require a tampered manifest to fail the install"
# shellcheck disable=SC2016
grep -qxF 'bash "$ROOT/scripts/release/catalog-test.sh" "$platform" "$scratch/dist" --full' "$root/scripts/test-local.sh" ||
  problem "test-local.sh: does not run catalog-test.sh --full"

registry="$work/registry/index.crates.io-0000"
mkdir -p "$registry/zstd-sys-2.0.13+zstd.1.5.6/zstd" "$registry/lz4-sys-1.10.0/liblz4/lib"
echo "zstd BSD licence" >"$registry/zstd-sys-2.0.13+zstd.1.5.6/zstd/LICENSE"
echo "lz4 BSD-2-Clause licence" >"$registry/lz4-sys-1.10.0/liblz4/lib/LICENSE"
printf '[[package]]\nname = "lz4-sys"\nversion = "1.10.0"\n\n[[package]]\nname = "zstd-sys"\nversion = "2.0.13+zstd.1.5.6"\n' \
  >"$work/Cargo.lock"
bundled_case() {
  local name=$1 want=$2 status=0
  bash "$here/bundled-licenses.sh" "$work/Cargo.lock" "$work/registry" >"$work/$name.out" 2>&1 || status=$?
  [ "$status" = "$want" ] || problem "bundled-licenses: $name exited $status, want $want: $(cat "$work/$name.out")"
}
bundled_case bundled 0
for text in "zstd, bundled by zstd-sys 2.0.13+zstd.1.5.6" "zstd BSD licence" \
  "liblz4, bundled by lz4-sys 1.10.0" "lz4 BSD-2-Clause licence"; do
  grep -qF "$text" "$work/bundled.out" || problem "bundled-licenses: no [$text] in $(cat "$work/bundled.out")"
done
printf '[[package]]\nname = "lz4-sys"\nversion = "1.9.4"\n\n' >>"$work/Cargo.lock"
bundled_case second-version 1
grep -qF "no lz4-sys-1.9.4/liblz4/lib/LICENSE under" "$work/second-version.out" ||
  problem "bundled-licenses: a second lz4-sys version said $(cat "$work/second-version.out")"
mkdir -p "$registry/lz4-sys-1.9.4/liblz4/lib"
echo "lz4 1.9.4 licence" >"$registry/lz4-sys-1.9.4/liblz4/lib/LICENSE"
bundled_case both-versions 0
for text in "liblz4, bundled by lz4-sys 1.10.0" "liblz4, bundled by lz4-sys 1.9.4" "lz4 1.9.4 licence"; do
  grep -qF "$text" "$work/both-versions.out" || problem "bundled-licenses: no [$text] in $(cat "$work/both-versions.out")"
done
rm "$registry/lz4-sys-1.10.0/liblz4/lib/LICENSE"
bundled_case unbundled 1
grep -qF "no lz4-sys-1.10.0/liblz4/lib/LICENSE under" "$work/unbundled.out" ||
  problem "bundled-licenses: a missing licence said $(cat "$work/unbundled.out")"
printf '[[package]]\nname = "zstd-sys"\nversion = "2.0.13+zstd.1.5.6"\n' >"$work/Cargo.lock"
bundled_case unlocked 1
grep -qF "has no lz4-sys" "$work/unlocked.out" || problem "bundled-licenses: an absent crate said $(cat "$work/unlocked.out")"

mkdir -p "$work/drafted"
touch "$work/drafted/polars-x86_64-linux.zip" "$work/drafted/polars-aarch64-macosx.zip" \
  "$work/drafted/$RELEASE_NOTICES"
draft_job() {
  local name=$1 tagged=$2 view=$3 want=$4 status=0
  : >"$work/$name.gh"
  PATH="$work/stub-bin:$PATH" GH_LOG="$work/$name.gh" GH_TAGGED=$tagged GH_VIEW=$view GH_REPO=o/r \
    bash "$here/draft.sh" v0.3 aaaa "$work/drafted" >"$work/$name.out" 2>&1 || status=$?
  [ "$status" = "$want" ] || problem "draft.sh: $name exited $status, want $want: $(cat "$work/$name.out")"
}
draft_job drafts aaaa missing 0
grep -qF "gh api repos/o/r/commits/v0.3 --jq .sha" "$work/drafts.gh" || problem "draft.sh: did not read the tag's commit"
grep -qF "release create v0.3 --draft --verify-tag" "$work/drafts.gh" || problem "draft.sh: drafted no release"
grep -qF "Native packages polars-aarch64-macosx polars-x86_64-linux v0.3" "$work/drafts.gh" ||
  problem "draft.sh: the notes do not name dist's packages: $(cat "$work/drafts.gh")"
draft_job moved bbbb missing 1
grep -qF "v0.3 is commit bbbb now, but this run built aaaa" "$work/moved.out" ||
  problem "draft.sh: a moved tag said $(cat "$work/moved.out")"
draft_job released aaaa present 1
grep -qF "v0.3 already has a release" "$work/released.out" ||
  problem "draft.sh: a released tag said $(cat "$work/released.out")"
draft_job unknown aaaa error 1
grep -qF "gh release view v0.3 failed: HTTP 502" "$work/unknown.out" ||
  problem "draft.sh: a failed view said $(cat "$work/unknown.out")"
for name in moved released unknown; do
  if grep -qF "release create" "$work/$name.gh"; then problem "draft.sh: $name drafted a release"; fi
done

bash3_case() {
  local name=$1 want=$2 status=0
  shift 2
  bash "$here/bash3.sh" "$@" >"$work/$name.out" 2>&1 || status=$?
  [ "$status" = "$want" ] || problem "bash3: $name exited $status, want $want: $(cat "$work/$name.out")"
}
bash3_case shipped 0
# shellcheck disable=SC2016
for construct in 'map''file -t deps <<<"$x"' 'read''array -t deps' 'declare -''A seen' 'local -''n ref=$1' \
  'echo "$''{x,,}"' 'echo "$''{x^^}"' 'echo "$''{list[0]^^}"''  a) ;''&' '  a) ;;''&' 'cmd |''& tee' '[[ -''v x ]]' 'cop''roc cat'; do
  printf 'set -e\n%s\n' "$construct" >"$work/bash4.sh"
  bash3_case bash4 1 "$work/bash4.sh"
  grep -qF "bash4.sh:2:" "$work/bash4.out" || problem "bash3: [$construct] was not named: $(cat "$work/bash4.out")"
done
# shellcheck disable=SC2016
printf 'x=${#list[@]} y=${x%%%%,*} z=${x//,/ }\nlocal -a list\necho 2>&1; a || b\n' >"$work/bash3-ok.sh"
bash3_case "bash3 constructs" 0 "$work/bash3-ok.sh"
bash3_case unreadable 2 "$work/absent.sh"

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
  release_platform "$p"
  package=$RELEASE_PACKAGE
  native=$(racket "$here/catalog.rkt" info "$root/polars" native-version)
  artifact="$work/artifact"
  mkdir -p "$artifact"
  cp "$exporting" "$artifact/$RELEASE_LIBRARY"
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
    grep -qF "\"$RELEASE_DOWNLOADS/v$native/$package.zip\"" "$work/dist/$package.rktd" ||
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

for script in "$here"/*.sh; do
  [ -x "$script" ] || problem "mode: $script is not executable, and the workflow runs it directly"
done

[ "$failures" -eq 0 ] && echo "gates-test: ok"
exit "$failures"
