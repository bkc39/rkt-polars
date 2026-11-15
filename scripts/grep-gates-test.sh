#!/usr/bin/env bash
# shellcheck disable=SC2016
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
  out=$(PATH=${lint_path:-$PATH} "$BASH" "$work/tree/scripts/$gate.sh" 2>&1) || got=$?
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
cat > "$work/tree/scripts/fine.sh" <<'FIXTURE'
#!/usr/bin/env bash
a || st=$?
if ! a; then
  fail x
fi
echo "$?"
if a; then :; else echo "$?"; fi
if ! a; then # $? unread
  : # nor $? here
  : '$?'
fi
if a; then
  echo "$?"
fi
if ! a; b; then
  echo "$?"
fi
if ! a; then
  :
  echo "$?"
fi
if ! a; then :; else
  echo $?
fi
FIXTURE
chmod +x "$work/tree/scripts/fine.sh"
printf '# shellcheck shell=bash\nx=1\n' > "$work/tree/scripts/sourced.sh"
printf 'a fixture, not a script\n' > "$work/tree/scripts/fixture.log"
expect "a captured status, an unnegated or non-final negation, a later statement, an else, a comment, a sourced script and a fixture" \
  shell-lint 0 "shell-lint: none in scripts/"
cat > "$work/tree/scripts/text.sh" <<'FIXTURE'
#!/usr/bin/env bash
printf '%s\n' '
if ! false; then
  echo "$?"
fi
'
cat <<EOF
if ! a; then
  echo $?
EOF
cat <<-'END'
	if ! a; then
	  echo $?
	END
cat << "Q"
while ! a; do
  echo $?
Q
cat <<\EOF
until ! a; do
  echo $?
EOF
if ! a; then
  echo "literal \$?"
fi
cat <<END-TEXT
if ! a; then
  echo $?
END-TEXT
cat <<E"O"F
while ! a; do
  echo $?
EOF
n=$((1 << 2))
cat <<A <<B
x
A
if ! a; then
  echo $?
B
printf '%s\n' $'it\'s fine'
x="$(printf '%s' "don't")"
n=$((
  1 << 2
))
FIXTURE
chmod +x "$work/tree/scripts/text.sh"
expect "text in quotes and heredocs, an escaped \$?, an ANSI-C quote, nested quotes and a multi-line shift" \
  shell-lint 0 "shell-lint: none in scripts/"
printf '#!/usr/bin/env bash\necho hi\n' > "$work/tree/scripts/plain.sh"
chmod -x "$work/tree/scripts/plain.sh"
expect "a shebang without the executable bit" shell-lint 1 \
  "scripts/plain.sh:1: has a shebang but is not executable"
tree
printf '#!/usr/bin/env racket\n#lang racket/base\n' > "$work/tree/scripts/tool.rkt"
expect "a shebang on a file of another kind" shell-lint 1 "scripts/tool.rkt:1: has a shebang but is not executable"
while IFS='|' read -r line label body; do
  tree
  # shellcheck disable=SC2059
  printf "$body" > "$work/tree/scripts/negated.sh"
  expect "\$? in $label" shell-lint 1 "scripts/negated.sh:$line: \$? here is the negated condition's status"
done <<'CASES'
3|the body of if !|set -e\nif ! a "$x"; then\n  fail "a: status $?"\nfi\n
4|the body of elif !|if a; then\n  :\nelif ! b; then\n  st=$?\nfi\n
4|the body of a second elif !|if a; then\n  :\nelif b; then :; elif ! c; then\n  st=$?\nfi\n
1|the line of if !|if ! a; then fail "status $?"; fi\n
4|a body after a then on its own line|if ! a \\\n  b\nthen\n  echo $?\nfi\n
2|the body of while !|while ! a; do\n  echo "$?"\ndone\n
2|the body of until !|until ! a; do\n  echo "$?"\ndone\n
2|a condition list ending in a negation|if a; ! b; then\n  echo $?\nfi\n
4|a negated multi-line subshell|if ! (\n  false\n); then\n  echo "$?"\nfi\n
4|a negated multi-line brace group|if ! {\n  false\n}; then\n  echo "$?"\nfi\n
3|a function body|f() {\n  if ! a; then\n    echo "$?"\n  fi\n}\n
2|a body whose condition holds then and do|if ! grep -q then do; then\n  echo "$?"\nfi\n
2|a body whose condition quotes ; then|if ! echo "a; then b"; then\n  echo "$?"\nfi\n
4|a body after a multi-line quote|x=\047a\nb\047\nif ! a; then\n  echo $?\nfi\n
5|a body after a heredoc|cat <<EOF\nif ! a; then\nEOF\nif ! a; then\n  echo $?\nfi\n
5|a body after a heredoc of <<-|cat <<-EOF\n\tx\n\tEOF\nif ! a; then\n  echo $?\nfi\n
5|a body after a heredoc of a backslashed word|cat <<\\EOF\nx\nEOF\nif ! a; then\n  echo $?\nfi\n
5|a body after a heredoc of a quoted word|cat << \047EOF\047\nx\nEOF\nif ! a; then\n  echo $?\nfi\n
5|a body after a heredoc of a word with a dash|cat <<END-TEXT\nx\nEND-TEXT\nif ! a; then\n  echo $?\nfi\n
5|a body after a heredoc of a partly quoted word|cat <<E"O"F\nx\nEOF\nif ! a; then\n  echo $?\nfi\n
2|a body that escapes one $ and not another|if ! a; then\n  echo "\\$? $?"\nfi\n
3|a body after an arithmetic shift|n=$((1 << 2))\nif ! a; then\n  echo "$?"\nfi\n
7|a body after two heredocs on one line|cat <<A <<B\nx\nA\ny\nB\nif ! a; then\n  echo $?\nfi\n
3|a body after a here-string|cat <<<x\nif ! a; then\n  echo $?\nfi\n
CASES
for name in aaa zzz; do
  tree
  printf 'cat <<EOF\nx\n' > "$work/tree/scripts/$name.sh"
  expect "a heredoc that never ends in $name.sh" shell-lint 1 \
    "scripts/$name.sh:1: shfmt cannot parse it: unclosed here-document"
  tree
  printf 'x=1\ny=\047abc\n' > "$work/tree/scripts/$name.sh"
  printf 'if ! a; then\n  echo $?\nfi\n' > "$work/tree/scripts/negated.sh"
  expect "a quote that never closes in $name.sh" shell-lint 1 \
    "scripts/$name.sh:2: shfmt cannot parse it: reached EOF without closing quote"
  expect "a hit beside a quote that never closes in $name.sh" shell-lint 1 \
    "scripts/negated.sh:2: \$? here is the negated condition's status"
done
for tool in shfmt jq; do
  tree
  rm -rf "${work:?}/bin"
  mkdir "$work/bin"
  for other in dirname find sort head shfmt jq; do
    [ "$other" = "$tool" ] || ln -s "$(command -v "$other")" "$work/bin/$other"
  done
  lint_path=$work/bin expect "no $tool on PATH" shell-lint 2 "shell-lint: $tool is not on PATH"
done
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
