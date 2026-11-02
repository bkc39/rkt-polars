#!/usr/bin/env bash
#
# The grep-gates-test gate (#298, #302): each grep gate run on a scratch tree, which
# it reads because it works from its own script's parent.  A clean tree
# passes, a planted hit fails with 1, and a tree missing a directory or file
# the gate reads fails with 2 and the gate's message, where a grep error
# taken for "no match" would pass.
#
# Usage: scripts/grep-gates-test.sh
set -euo pipefail

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
unset GITHUB_ACTIONS

status=0
fail() {
  status=1
  echo "FAIL: $*" >&2
}

tree() {
  rm -rf "$work/tree"
  mkdir -p "$work/tree/scripts" "$work/tree/rust"
  for dir in polars/private polars/tests examples user-guide bench; do
    mkdir -p "$work/tree/$dir"
    printf '#lang racket/base\n(define x 1)\n' > "$work/tree/$dir/clean.rkt"
  done
  printf '[[package]]\nname = "rustls"\nversion = "0.23.0"\n' > "$work/tree/rust/Cargo.lock"
  printf '(("tests/allowed.rkt" f "a reason"))\n' > "$work/tree/polars/tests/dynamic-wind-sites.rktd"
  cp "$here"/no-syntax-rule.sh "$here"/no-inline-tests.sh "$here"/rustls-only.sh \
    "$here"/no-dynamic-wind.sh "$work/tree/scripts/"
}

expect() {
  local label=$1 gate=$2 want=$3 text=$4 got=0 out
  out=$(bash "$work/tree/scripts/$gate.sh" 2>&1) || got=$?
  if [ "$got" -ne "$want" ]; then
    fail "$gate, $label: exit $got, not $want; output:"$'\n'"$out"
  elif ! grep -qF -- "$text" <<< "$out"; then
    fail "$gate, $label: output lacks [$text]:"$'\n'"$out"
  else
    echo "ok: $gate, $label"
  fi
}

tree
expect "a clean tree" no-syntax-rule 0 "no-syntax-rule: none in"
printf '(define-syntax-rule (m) 1)\n' > "$work/tree/polars/private/hit.rkt"
expect "a hit" no-syntax-rule 1 "polars/private/hit.rkt:1: use define-syntax-parse-rule"
tree
rm -r "$work/tree/bench"
expect "a missing directory" no-syntax-rule 2 "no-syntax-rule: grep failed (exit 2)"
tree
printf '(define-syntax-rule (m) 1)\n' > "$work/tree/polars/private/hit.rkt"
rm -r "$work/tree/bench"
expect "a hit and a missing directory" no-syntax-rule 2 "no-syntax-rule: grep failed (exit 2)"

tree
expect "a clean tree" no-inline-tests 0 "no-inline-tests: none in"
printf '(module+ test)\n' > "$work/tree/polars/private/hit.rkt"
expect "a hit" no-inline-tests 1 "polars/private/hit.rkt:1: move the test submodule"
tree
rm -r "$work/tree/polars/private"
expect "a missing directory" no-inline-tests 2 "no-inline-tests: grep failed (exit 2)"

tree
expect "a clean lock file" rustls-only 0 "rustls-only: no OpenSSL"
printf '[[package]]\nname = "openssl-sys"\n' >> "$work/tree/rust/Cargo.lock"
expect "a hit" rustls-only 1 'rust/Cargo.lock:5: name = "openssl-sys": TLS must be rustls'
tree
rm "$work/tree/rust/Cargo.lock"
expect "a missing lock file" rustls-only 2 "rustls-only: grep failed (exit 2) on rust/Cargo.lock"

wind='(define (f) (dynamic-wind void void void))'
tree
expect "a clean tree" no-dynamic-wind 0 "no-dynamic-wind: none in"
printf ';; (dynamic-wind void void void)\n' > "$work/tree/polars/private/comment.rkt"
printf '%s\n' "$wind" > "$work/tree/polars/private/resource.rkt"
printf '%s\n' "$wind" > "$work/tree/polars/tests/resource.rkt"
printf '%s\n%s\n' "$wind" "$wind" > "$work/tree/polars/tests/allowed.rkt"
expect "a comment, the resource.rkt files and a listed file" no-dynamic-wind 0 \
  "no-dynamic-wind: none in"
printf '%s\n' "$wind" > "$work/tree/polars/private/hit.rkt"
expect "a hit" no-dynamic-wind 1 "polars/private/hit.rkt:1: pair the resource with with-release"
tree
printf '(define (g) (apply dynamic-wind (list void void void)))\n' \
  > "$work/tree/polars/tests/reference.rkt"
expect "a reference" no-dynamic-wind 1 "polars/tests/reference.rkt:1: pair the resource"
tree
printf '(require (prefix-in base: racket/base))\n(define (f t) (base:dynamic-wind void t void))\n' \
  > "$work/tree/polars/private/prefixed.rkt"
expect "a prefixed name" no-dynamic-wind 1 "polars/private/prefixed.rkt:2: pair the resource"
tree
printf '()\n' > "$work/tree/polars/tests/dynamic-wind-sites.rktd"
printf '%s\n' "$wind" > "$work/tree/polars/tests/allowed.rkt"
expect "no sites listed" no-dynamic-wind 1 "polars/tests/allowed.rkt:1: pair the resource"
tree
rm -r "$work/tree/polars/private"
expect "a missing directory" no-dynamic-wind 2 "no-dynamic-wind: grep failed (exit 2)"
tree
rm "$work/tree/polars/tests/dynamic-wind-sites.rktd"
expect "a missing list of sites" no-dynamic-wind 2 "no-dynamic-wind: cannot read the listed sites"

exit $status
