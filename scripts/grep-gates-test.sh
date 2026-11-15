#!/usr/bin/env bash
#
# The grep-gates-test gate (#298, #302, #332): each grep gate, shell-lint, and
# dependency-catalogs-test.sh's check of release/catalog-test.sh, run on a scratch
# tree, which it reads because it works from its own script's parent.  A clean tree
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
  mkdir -p "$work/tree/scripts/release" "$work/tree/rust"
  for dir in polars/private polars/tests examples user-guide bench; do
    mkdir -p "$work/tree/$dir"
    printf '#lang racket/base\n(define x 1)\n' > "$work/tree/$dir/clean.rkt"
  done
  printf '[[package]]\nname = "rustls"\nversion = "0.23.0"\n' > "$work/tree/rust/Cargo.lock"
  printf '(("tests/allowed.rkt" f "a reason"))\n' > "$work/tree/polars/tests/dynamic-wind-sites.rktd"
  cp "$here"/no-syntax-rule.sh "$here"/no-inline-tests.sh "$here"/rustls-only.sh \
    "$here"/no-dynamic-wind.sh "$here"/dependency-catalogs.sh \
    "$here"/dependency-catalogs-test.sh "$here"/shell-lint.sh "$work/tree/scripts/"
  cp "$here"/release/catalog-test.sh "$work/tree/scripts/release/"
  chmod -R u+w "$work/tree/scripts"
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
printf ':dynamic-wind\n' > "$work/tree/polars/private/colon.rkt"
expect "a line-initial colon prefix" no-dynamic-wind 1 "polars/private/colon.rkt:1: pair the resource"
tree
printf '(define (f #:dynamic-wind [w void]) w)\n(f #:dynamic-wind void)\n' \
  > "$work/tree/polars/private/keyword.rkt"
expect "a keyword" no-dynamic-wind 0 "no-dynamic-wind: none in"
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

tree
expect "this checkout's catalog-test.sh" dependency-catalogs-test 0 "dependency-catalogs: ok"
tree
# shellcheck disable=SC2016
printf 'raco pkg catalog-copy --from-config "$catalog"\n' >> "$work/tree/scripts/release/catalog-test.sh"
expect "--from-config" dependency-catalogs-test 1 \
  "scripts/release/catalog-test.sh copies every configured catalog (--from-config)"
tree
sed -i.bak '/^listed=/d' "$work/tree/scripts/release/catalog-test.sh"
expect "no filter" dependency-catalogs-test 1 \
  "scripts/release/catalog-test.sh does not read its catalogs from release_catalogs"
tree
rm "$work/tree/scripts/release/catalog-test.sh"
expect "a missing catalog-test.sh" dependency-catalogs-test 2 \
  "cannot read $work/tree/scripts/release/catalog-test.sh"

tree
expect "a clean tree" shell-lint 0 "shell-lint: none in scripts/"
# shellcheck disable=SC2016
printf '#!/usr/bin/env bash\na || st=$?\nif ! a; then\n  fail x\nfi\necho "$?"\nif a; then :; else echo "$?"; fi\n' \
  > "$work/tree/scripts/fine.sh"
chmod +x "$work/tree/scripts/fine.sh"
printf '# shellcheck shell=bash\nx=1\n' > "$work/tree/scripts/sourced.sh"
printf 'a fixture, not a script\n' > "$work/tree/scripts/fixture.log"
expect "a captured status, a sourced script and a fixture" shell-lint 0 "shell-lint: none in scripts/"
printf '#!/usr/bin/env bash\necho hi\n' > "$work/tree/scripts/plain.sh"
chmod -x "$work/tree/scripts/plain.sh"
expect "a shebang without the executable bit" shell-lint 1 \
  "scripts/plain.sh:1: has a shebang but is not executable"
tree
printf '#!/usr/bin/env racket\n#lang racket/base\n' > "$work/tree/scripts/tool.rkt"
expect "a shebang on a file of another kind" shell-lint 1 "scripts/tool.rkt:1: has a shebang but is not executable"
negated() {
  local label=$1 line=$2 body=$3
  tree
  # shellcheck disable=SC2059
  printf "$body" > "$work/tree/scripts/negated.sh"
  expect "$label" shell-lint 1 "scripts/negated.sh:$line: \$? here is the negated condition's status"
}
# shellcheck disable=SC2016
negated "\$? in the body of if !" 3 'set -e\nif ! a "$x"; then\n  fail "a: status $?"\nfi\n'
# shellcheck disable=SC2016
negated "\$? in the body of elif !" 4 'if a; then\n  :\nelif ! b; then\n  st=$?\nfi\n'
# shellcheck disable=SC2016
negated "\$? on the line of if !" 1 'if ! a; then fail "status $?"; fi\n'
# shellcheck disable=SC2016
negated "\$? after a then on its own line" 4 'if ! a \\\n  b\nthen\n  echo $?\nfi\n'
# shellcheck disable=SC2016
negated "\$? in the body of while !" 2 'while ! a; do\n  echo "$?"\ndone\n'
tree
printf '#!/usr/bin/env bash\n' > "$work/tree/scripts/unreadable.sh"
chmod 0 "$work/tree/scripts/unreadable.sh"
if [ -r "$work/tree/scripts/unreadable.sh" ]; then
  echo "ok: shell-lint, an unreadable file: skipped, since this user reads a mode-0 file"
else
  expect "an unreadable file" shell-lint 2 "shell-lint: cannot read scripts/unreadable.sh"
fi
chmod u+rw "$work/tree/scripts/unreadable.sh"

exit $status
