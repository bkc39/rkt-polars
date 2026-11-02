#!/usr/bin/env bash
#
# The grep-gates-test gate (#298): each grep gate run on a scratch tree, which
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

# tree: a fresh scratch tree at $work/tree holding every directory and file
# the gates read, with nothing for them to flag.
tree() {
  rm -rf "$work/tree"
  mkdir -p "$work/tree/scripts" "$work/tree/rust"
  for dir in polars/private polars/tests examples user-guide bench; do
    mkdir -p "$work/tree/$dir"
    printf '#lang racket/base\n(define x 1)\n' > "$work/tree/$dir/clean.rkt"
  done
  printf '[[package]]\nname = "rustls"\nversion = "0.23.0"\n' > "$work/tree/rust/Cargo.lock"
  cp "$here"/no-syntax-rule.sh "$here"/no-inline-tests.sh "$here"/rustls-only.sh \
    "$work/tree/scripts/"
}

# expect LABEL GATE WANT-STATUS TEXT: runs GATE's script on the scratch tree,
# holding its exit status to WANT-STATUS and its output to holding TEXT.
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

exit $status
