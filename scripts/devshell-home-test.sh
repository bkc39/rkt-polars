#!/usr/bin/env bash
#
# The devshell-home gate (#158). It sources scripts/devshell-home.sh, as the
# dev shell's hook does, and runs the hook itself, rendered from flake.nix's
# devSetup with local stand-ins for its store paths.
#
# Every spelling of one checkout (a trailing slash, a symlink, a dot segment,
# a subdirectory), given as the PWD the shell inherits, keys exactly
# $XDG_CACHE_HOME/rkt-polars-devshell/<the first 12 hex digits of the root's
# sha256>, for a git checkout and for a copy outside git inside an unrelated
# repository, which must not key on that repository's root. `/` keys a
# pinned id, so a change of hash or width, which would orphan every home,
# fails. A home that cannot be keyed (HOME unset, sha256sum failing or
# printing nothing) is one line on stderr, and the hook skips the rest.
#
# Usage: scripts/devshell-home-test.sh
set -euo pipefail
shopt -u patsub_replacement 2> /dev/null || true

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)
script=$here/devshell-home.sh
flake=$here/../flake.nix
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
while read -r var; do
  unset "$var"
done < <(git rev-parse --local-env-vars)
unset PLTUSERHOME project_root
export XDG_CACHE_HOME="$work/cache"
pinned_id=8a5edab28263
base_path=$PATH

status=0
fail() {
  status=1
  echo "FAIL: $*" >&2
}

key_of() {
  printf '%s/rkt-polars-devshell/%s' "$XDG_CACHE_HOME" \
    "$(printf '%s' "$1" | sha256sum | cut -c1-12)"
}

# shellcheck source-path=SCRIPTDIR source=devshell-home.sh
home_from() {
  (cd "$1" && PWD=$1 && . "$script" && printf '%s\n%s\n' "$project_root" "$PLTUSERHOME")
}

same() {
  local label=$1 want=$2 dir=$3 got
  got=$(home_from "$dir") || got="(refused, status $?)"
  if [ "$got" = "$want" ]; then
    echo "ok: $label"
  else
    fail "$label: $dir gives [$got], not [$want]"
  fi
}

check_checkout() {
  local kind=$1 root=$2 canon want
  mkdir -p "$root/polars/private"
  touch "$root/info.rkt" "$root/polars/info.rkt"
  ln -s "$root" "$work/link-$kind"
  canon=$(cd "$root" && pwd -P)
  want=$(printf '%s\n%s' "$canon" "$(key_of "$canon")")
  same "$kind: root" "$want" "$root"
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

one_reason() {
  local label=$1 err=$2
  if [ "$(wc -l < "$err")" -eq 1 ] \
    && grep -q '^rkt-polars dev shell: .*; skipping the setup$' "$err"; then
    return 0
  fi
  fail "$label: stderr is not one reason: [$(cat "$err")]"
  return 1
}

refused() {
  local label=$1 dir=$2 got
  shift 2
  # shellcheck disable=SC2016
  got=$(cd "$dir" && env "$@" bash -c \
    '. "$1"; printf "%s|%s|%s" "$?" "${PLTUSERHOME-unset}" "${project_root-unset}"' \
    _ "$script" 2> "$work/err")
  if [ "$got" != "1|unset|unset" ]; then
    fail "$label: status|PLTUSERHOME|project_root is [$got], not [1|unset|unset]"
  elif one_reason "$label" "$work/err"; then
    echo "ok: $label"
  fi
}

shim() {
  mkdir -p "$work/$1"
  printf '#!%s\n%s\n' "$(command -v bash)" "$2" > "$work/$1/sha256sum"
  chmod +x "$work/$1/sha256sum"
}

# shellcheck disable=SC2016
render_hook() {
  local hook bare esc="''\${" dollar='${' rest='echo "rest ran: $PLTUSERHOME"'
  hook=$(awk -v head="      devSetup = pkgs: rust: rest: ''" -v tail="      '';" \
    '$0 == head { on = 1; next } on && $0 == tail { exit } on' "$flake")
  [ -n "$hook" ] || { fail "flake.nix: no devSetup = pkgs: rust: rest: ''"; return 1; }
  hook=${hook//'${./scripts/devshell-home.sh}'/$script}
  hook=${hook//'${pkgs.coreutils}'/$(dirname "$(dirname "$(command -v sha256sum)")")}
  hook=${hook//'${pkgs.git}'/$(dirname "$(dirname "$(command -v git)")")}
  hook=${hook//'${rust}'/$work/rust}
  hook=${hook//'${rest}'/$rest}
  bare=${hook//"$esc"/}
  if [[ $bare == *'${'* ]]; then
    fail "flake.nix: devSetup has an interpolation the test does not render"
    return 1
  fi
  printf '%s' "${hook//"$esc"/$dollar}"
}

check_hook() {
  local root=$1 canon hook out want
  canon=$(cd "$root" && pwd -P)
  want=$(key_of "$canon")
  hook=$(render_hook) || { status=1; return 0; }
  mkdir -p "$work/rust/lib" "$work/stub"
  touch "$work/rust/lib/libcompat.so"
  printf '#!%s\necho "$*" >> %q\n' "$(command -v bash)" "$work/raco.log" > "$work/stub/raco"
  chmod +x "$work/stub/raco"

  out=$(cd "$root/polars/private" && env -u HOME -u XDG_CACHE_HOME \
    PATH="$work/stub:$base_path" bash -c "$hook" 2> "$work/err") \
    || fail "hook, HOME unset: status $?"
  if [ -n "$out" ] || [ -e "$root/polars/native-libs" ] || [ -e "$work/raco.log" ]; then
    fail "hook, HOME unset: it went on: [$out]"
  elif one_reason "hook, HOME unset" "$work/err"; then
    echo "ok: hook, HOME unset"
  fi

  out=$(cd "$root/polars/private" && env PATH="$work/stub:$base_path" bash -c "$hook") \
    || fail "hook: status $?"
  if [ "$out" != "$(printf 'Setting up rkt-polars in %s (deps changed or first run)\nDone. Run '\''raco test -x --timeout 600 -c polars'\'' to test.\nrest ran: %s' "$want" "$want")" ]; then
    fail "hook: output is [$out]"
  elif [ ! -f "$root/polars/native-libs/libcompat.so" ]; then
    fail "hook: libcompat was not copied into $root/polars/native-libs"
  elif ! compgen -G "$want/.setup-installed-*" > /dev/null; then
    fail "hook: no setup stamp in $want"
  elif ! grep -qxF -- "pkg install --batch --auto --no-setup --link --scope user --skip-installed --name rkt-polars $canon" "$work/raco.log"; then
    fail "hook: raco did not link $canon: [$(cat "$work/raco.log")]"
  else
    echo "ok: hook, from a subdirectory"
  fi
}

mkdir -p "$work/repo" "$work/outer"
git -C "$work/repo" init -q
check_checkout git "$work/repo"
git -C "$work/outer" init -q
check_checkout plain "$work/outer/checkout"
same "pinned id of /" "$(printf '/\n%s' "$XDG_CACHE_HOME/rkt-polars-devshell/$pinned_id")" /

shim broken 'exit 127'
shim silent 'exit 0'
refused "HOME and XDG_CACHE_HOME unset" "$work/repo" -u HOME -u XDG_CACHE_HOME
refused "sha256sum fails" "$work/repo" PATH="$work/broken:$base_path"
refused "sha256sum prints nothing" "$work/repo" PATH="$work/silent:$base_path"

check_hook "$work/repo"

exit $status
