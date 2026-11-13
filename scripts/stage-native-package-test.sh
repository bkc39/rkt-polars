#!/usr/bin/env bash
#
# The stage-native-package gate (#254). scripts/stage-native-package.rkt is
# run in a scratch checkout. Its manifest.json names the rust/ tree and the
# commit given by --rust-tree and --commit, or else recorded beside the library
# (CI's rust-tree and commit), or else, under --head, this checkout's HEAD,
# refused while rust/ differs from HEAD, tracked or untracked. With none of
# them, half of a pair, or --head without git on PATH, it fails, naming why,
# and stages nothing, as it does for another platform's library, by its name
# or, on Linux, by its ELF machine.
#
# Usage: scripts/stage-native-package-test.sh  (in the dev shell: racket, git)
set -euo pipefail

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)
root=$(cd "$here/.." && pwd -P)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

status=0
fail() {
  status=1
  echo "FAIL: $*" >&2
}

repo=$work/repo
mkdir -p "$repo/scripts" "$repo/native" "$repo/polars" "$repo/rust" "$work/build"
cp "$here/stage-native-package.rkt" "$repo/scripts/"
cp -R "$root/native/polars-x86_64-linux" "$repo/native/"
cp "$root/polars/info.rkt" "$repo/polars/"
cp "$root/LICENSE-APACHE" "$root/LICENSE-MIT" "$repo/"
echo 'pub fn f() {}' > "$repo/rust/lib.rs"
git -C "$repo" init -q
git -C "$repo" add -A
git -C "$repo" -c user.name=test -c user.email=test@example.invalid commit -q -m init
head_tree=$(git -C "$repo" rev-parse HEAD:rust)
head_commit=$(git -C "$repo" rev-parse HEAD)
lib=$work/build/libcompat.so
# elf FILE MACHINE: a little-endian ELF64 header's first 20 bytes, for the
# e_machine whose octal escape is MACHINE (076 x86-64, 267 AArch64), then bytes.
elf() {
  printf '\177ELF\002\001\001\000\000\000\000\000\000\000\000\000\003\000%b\000built bytes' "\\0$2" > "$1"
}
elf "$lib" 076

n=0
# stage NAME ARGS...: stages into $work/out-N, leaving its stderr in $err.
stage() {
  n=$((n + 1))
  out=$work/out-$n
  err=$work/err-$n
  racket "$repo/scripts/stage-native-package.rkt" "$@" x86_64-linux "$lib" "$out" 2> "$err"
}

field() {
  racket -l racket/base -l json \
    -e '(define-values (file key) (apply values (vector->list (current-command-line-arguments))))' \
    -e '(display (hash-ref (call-with-input-file file read-json) (string->symbol key)))' \
    "$1" "$2"
}

staged() { # NAME TREE COMMIT
  if [[ ! -f "$out/manifest.json" ]]; then
    fail "$1: no manifest: $(cat "$err")"
    return
  fi
  [[ "$(field "$out/manifest.json" rust_tree)" == "$2" ]] \
    || fail "$1: rust_tree is $(field "$out/manifest.json" rust_tree), not $2"
  [[ "$(field "$out/manifest.json" commit)" == "$3" ]] \
    || fail "$1: commit is $(field "$out/manifest.json" commit), not $3"
}

refused() { # NAME MESSAGE
  [[ ! -e "$out" ]] || fail "$1: staged $out"
  grep -qF -- "$2" "$err" || fail "$1: stderr lacks [$2]: [$(cat "$err")]"
}

if stage; then fail "no record, no flag: exit 0"; fi
refused "no record, no flag" "nothing names the rust/ tree and commit"

stage --head || true
staged "--head, clean" "$head_tree" "$head_commit"

stage --rust-tree t1 --commit c1 || true
staged "--rust-tree and --commit" t1 c1

if stage --rust-tree t1; then fail "--rust-tree alone: exit 0"; fi
refused "--rust-tree alone" "--rust-tree and --commit go together"

echo 'pub fn g() {}' >> "$repo/rust/lib.rs"
if stage --head; then fail "--head, rust/ modified: exit 0"; fi
refused "--head, rust/ modified" "rust/ differs from HEAD"
git -C "$repo" checkout -q -- rust

echo 'new' > "$repo/rust/new.rs"
if stage --head; then fail "--head, rust/ untracked file: exit 0"; fi
refused "--head, rust/ untracked file" "rust/ differs from HEAD"

echo t2 > "$work/build/rust-tree"
if stage --head; then fail "rust-tree recorded alone: exit 0"; fi
refused "rust-tree recorded alone" "records rust-tree but not commit"

echo c2 > "$work/build/commit"
stage --head || true
staged "records, under --head with rust/ dirty" t2 c2

stage || true
staged "records, no flag" t2 c2

stage --rust-tree t3 --commit c3 || true
staged "flags over records" t3 c3
rm "$work/build/rust-tree" "$work/build/commit" "$repo/rust/new.rs"

cp -R "$root/native/polars-aarch64-linux" "$repo/native/"
# stage_for PLATFORM LIBRARY NAME: stages into $work/out-NAME.
stage_for() {
  out=$work/out-$3
  err=$work/err-$3
  racket "$repo/scripts/stage-native-package.rkt" --rust-tree t4 --commit c4 "$1" "$2" "$out" 2> "$err"
}

if stage_for aarch64-linux "$lib" aarch64-linux-x86-64; then
  fail "aarch64-linux, an x86-64 library: exit 0"
fi
refused "aarch64-linux, an x86-64 library" \
  "is built for ELF machine 62, not aarch64-linux's AArch64 (ELF machine 183)"

elf "$lib" 267
if stage_for x86_64-linux "$lib" x86_64-linux-aarch64; then
  fail "x86_64-linux, an AArch64 library: exit 0"
fi
refused "x86_64-linux, an AArch64 library" \
  "is built for ELF machine 183, not x86_64-linux's x86-64 (ELF machine 62)"

stage_for aarch64-linux "$lib" aarch64-linux || true
staged "aarch64-linux" t4 c4
grep -qF '(define collection "polars-aarch64-linux")' "$out/info.rkt" 2> /dev/null \
  || fail "aarch64-linux: staged no polars-aarch64-linux skeleton: $(cat "$err")"
[[ -f "$out/native-libs/libcompat.so" ]] || fail "aarch64-linux: no native-libs/libcompat.so"
printf 'built bytes' > "$work/build/libcompat.dylib"
if stage_for aarch64-linux "$work/build/libcompat.dylib" aarch64-linux-dylib; then
  fail "aarch64-linux, a dylib: exit 0"
fi
refused "aarch64-linux, a dylib" "is not aarch64-linux's library, libcompat.so"
rm "$work/build/libcompat.dylib"

for bytes in 'built bytes' ''; do
  printf '%s' "$bytes" > "$lib"
  if stage_for aarch64-linux "$lib" "not-elf-${#bytes}"; then
    fail "aarch64-linux, ${#bytes} bytes that are not ELF: exit 0"
  fi
  refused "aarch64-linux, ${#bytes} bytes that are not ELF" \
    "is not an ELF library, not aarch64-linux's AArch64"
done
elf "$lib" 076

mkdir "$work/bin"
ln -s "$(command -v racket)" "$work/bin/racket"
if PATH=$work/bin stage --head; then fail "--head without git: exit 0"; fi
refused "--head without git" "git, which is not on PATH"

if [[ $status -eq 0 ]]; then
  echo "stage-native-package: ok ($n runs)"
fi
exit $status
