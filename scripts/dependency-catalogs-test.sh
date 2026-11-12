#!/usr/bin/env bash
#
# The dependency-catalogs gate (#254). scripts/dependency-catalogs.sh is run
# with `raco pkg config catalogs` stubbed: from a default configuration it
# keeps the release catalog and pkgs.racket-lang.org and drops Rhombus's and
# planet-compats, from CI's (the release catalog dropped) it keeps
# pkgs.racket-lang.org alone, and from one with neither it fails, naming
# what it read.
#
# Usage: scripts/dependency-catalogs-test.sh  (plain bash)
set -euo pipefail

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

status=0
fail() {
  status=1
  echo "FAIL: $*" >&2
}

mkdir "$work/bin"
cat > "$work/bin/raco" << 'EOF'
#!/usr/bin/env bash
[[ "$*" == "pkg config catalogs" ]] || exit 3
cat "$CATALOGS"
EOF
chmod +x "$work/bin/raco"

# catalogs NAME CONFIGURED: runs the script on CONFIGURED, leaving $out and $err.
catalogs() {
  printf '%s' "$2" > "$work/configured"
  CATALOGS=$work/configured PATH="$work/bin:$PATH" \
    bash "$here/dependency-catalogs.sh" > "$work/out" 2> "$work/err" && code=0 || code=$?
  out=$(cat "$work/out")
  err=$(cat "$work/err")
}

kept() { # NAME CONFIGURED EXPECTED
  catalogs "$1" "$2"
  [[ $code -eq 0 ]] || fail "$1: exit $code: $err"
  [[ "$out" == "$3" ]] || fail "$1: printed [$out], not [$3]"
}

release=https://download.racket-lang.org/releases/9.3/catalog/
pkgs=https://pkgs.racket-lang.org
rhombus=https://download.rhombus-lang.org/releases/current/catalog/
planet=https://planet-compats.racket-lang.org

kept "default configuration" "$release
$rhombus
$pkgs
$planet
" "$release
$pkgs"

kept "CI's configuration, the release catalog dropped" "$rhombus
$pkgs
$planet
" "$pkgs"

kept "another release, with trailing slashes" "https://download.racket-lang.org/releases/9.4/catalog
$pkgs/
" "https://download.racket-lang.org/releases/9.4/catalog
$pkgs/"

kept "a look-alike host is dropped" "https://pkgs.racket-lang.org.example.invalid
$pkgs
" "$pkgs"

catalogs "neither configured" "$rhombus
$planet
"
[[ $code -eq 1 ]] || fail "neither configured: exit $code, not 1"
[[ -z "$out" ]] || fail "neither configured: printed [$out]"
[[ "$err" == *"no release catalog or pkgs.racket-lang.org among"*"$planet"* ]] \
  || fail "neither configured: stderr is [$err]"

if [[ $status -eq 0 ]]; then
  echo "dependency-catalogs: ok"
fi
exit $status
