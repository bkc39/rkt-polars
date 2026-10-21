#!/usr/bin/env bash
#
# The devshell-home gate: every spelling of one checkout (a trailing slash, a
# symlink, a dot segment, a subdirectory) keys the same PLTUSERHOME, given as
# the PWD the shell inherits, as the racket-dev gate runner passes it (#158).
# It checks a git checkout, and a copy outside git inside an unrelated
# repository, which must not key on that repository's root.
#
# Usage: scripts/devshell-home-test.sh
set -euo pipefail

script="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)/devshell-home.sh"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
export XDG_CACHE_HOME="$work/cache"

status=0
fail() {
  status=1
  echo "FAIL: $*" >&2
}

home_from() {
  (cd "$1" && PWD=$1 bash "$script")
}

same() {
  local label=$1 want=$2 dir=$3 got
  got=$(home_from "$dir")
  if [ "$got" = "$want" ]; then
    echo "ok: $label"
  else
    fail "$label: $dir gives [$got], not [$want]"
  fi
}

check_checkout() {
  local kind=$1 root=$2 want
  mkdir -p "$root/polars/private"
  touch "$root/info.rkt" "$root/polars/info.rkt"
  ln -s "$root" "$work/link-$kind"
  want=$(home_from "$root")
  [ "$(head -1 <<< "$want")" = "$(cd "$root" && pwd -P)" ] \
    || fail "$kind: root is not the canonical path: $want"
  same "$kind: trailing slash" "$want" "$root/"
  same "$kind: double slash" "$want" "$root//"
  same "$kind: symlink" "$want" "$work/link-$kind"
  same "$kind: symlink, trailing slash" "$want" "$work/link-$kind/"
  same "$kind: dot segment" "$want" "$root/polars/.."
  if [ "$kind" = git ]; then
    same "$kind: subdirectory" "$want" "$root/polars/private"
    same "$kind: subdirectory through a symlink" "$want" "$work/link-$kind/polars"
  fi
}

mkdir -p "$work/repo" "$work/outer"
git -C "$work/repo" init -q
check_checkout git "$work/repo"
git -C "$work/outer" init -q
check_checkout plain "$work/outer/checkout"

exit $status
