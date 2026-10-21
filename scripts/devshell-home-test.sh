#!/usr/bin/env bash
#
# The devshell-home gate (#158). It sources scripts/devshell-home.sh, as the
# dev shell's hook does, and runs the dev shell's hook and `nix run .#bench`'s
# script themselves, rendered from flake.nix with local stand-ins for their
# store paths: the hook is devSetup with lintSetup as its rest, as shellHook
# composes them, and the bench is its guard, devSetup with its exec as the
# rest, and its fall-through.
#
# Every spelling of one checkout (a trailing slash, a symlink, a dot segment,
# a subdirectory, and a subdirectory under a git hook's GIT_DIR), given as the
# PWD the shell inherits, keys exactly
# $XDG_CACHE_HOME/rkt-polars-devshell/<the first 12 hex digits of the root's
# sha256>, for a git checkout and for a copy outside git inside an unrelated
# repository, which must not key on that repository's root. `/` keys a
# pinned id, so a change of hash or width, which would orphan every home,
# fails. A home that cannot be keyed (HOME unset, sha256sum failing or
# printing nothing) is one line on stderr, and the hook skips the rest,
# Resyntax's setup included; the bench then adds its own line and exits 1.
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
  local dir=$1
  shift
  # shellcheck disable=SC2163
  (cd "$dir" && PWD=$dir && { [ $# -eq 0 ] || export "$@"; } \
    && . "$script" && printf '%s\n%s\n' "$project_root" "$PLTUSERHOME")
}

same() {
  local label=$1 want=$2 dir=$3 got
  shift 3
  got=$(home_from "$dir" "$@") || got="(refused, status $?)"
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
    same "$kind: subdirectory, GIT_DIR set" "$want" "$root/polars/private" \
      GIT_DIR="$root/.git"
    same "$kind: subdirectory, GIT_DIR and GIT_WORK_TREE set" "$want" \
      "$root/polars/private" GIT_DIR="$root/.git" GIT_WORK_TREE="$root/polars"
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

# Prints the lines of flake.nix strictly between HEAD and the first TAIL after
# it, or fails naming HEAD.
block() {
  local text
  text=$(awk -v head="$1" -v tail="$2" \
    '$0 == head { on = 1; next } on && $0 == tail { exit } on' "$flake")
  [ -n "$text" ] || { fail "flake.nix: no [$1]"; return 1; }
  printf '%s' "$text"
}

prefix_of() {
  dirname "$(dirname "$(command -v "$1")")"
}

# Replaces each store path with its stand-in and Nix's ''${ escape with ${.
# shellcheck disable=SC2016
render() {
  local text=$1 bare esc="''\${" dollar='${' resyntax
  resyntax=$(sed -n 's/^      resyntaxSource = "\(.*\)";$/\1/p' "$flake")
  [ -n "$resyntax" ] || { fail "flake.nix: no resyntaxSource"; return 1; }
  text=${text//'${./scripts/devshell-home.sh}'/$script}
  text=${text//'${./scripts/install-native-libs.sh}'/$here/install-native-libs.sh}
  text=${text//'${pkgs.coreutils}'/$(prefix_of sha256sum)}
  text=${text//'${pkgs.diffutils}'/$(prefix_of cmp)}
  text=${text//'${pkgs.git}'/$(prefix_of git)}
  text=${text//'${pkgs.bash}'/$(prefix_of bash)}
  text=${text//'${rust}'/$work/rust}
  text=${text//'${resyntaxSource}'/$resyntax}
  bare=${text//"$esc"/}
  if [[ $bare == *'${'* ]]; then
    fail "flake.nix: an interpolation the test does not render: [$bare]"
    return 1
  fi
  printf '%s' "${text//"$esc"/$dollar}"
}

# shellcheck disable=SC2016
setup_block() {
  block "      devSetup = pkgs: rust: rest: ''" "      '';"
}

render_hook() {
  local setup lint
  grep -qxF '            shellHook = devSetup pkgs rust (lintSetup pkgs);' "$flake" \
    || { fail "flake.nix: shellHook is not devSetup pkgs rust (lintSetup pkgs)"; return 1; }
  setup=$(setup_block) || return 1
  # shellcheck disable=SC2016
  lint=$(block "      lintSetup = pkgs: ''" "      '';") || return 1
  # shellcheck disable=SC2016
  render "${setup//'${rest}'/$lint}"
}

render_bench() {
  local text guard rest tail setup
  local mid="            '' + devSetup pkgs rust ''" end="            '' + ''"
  # shellcheck disable=SC2016
  text=$(awk '$0 ~ /^            name = "bench";$/ { found = 1 }
    found && $0 == "            text = '\'''\''" { on = 1; next }
    on && $0 == "            '\'''\'';" { exit } on' "$flake")
  guard=${text%%$'\n'"$mid"$'\n'*}
  rest=${text#*$'\n'"$mid"$'\n'}
  tail=${rest#*$'\n'"$end"$'\n'}
  rest=${rest%%$'\n'"$end"$'\n'*}
  if [ "$guard" = "$text" ] || [ "$tail" = "$rest" ] || [ -z "$tail" ]; then
    fail "flake.nix: bench's text is not a guard, devSetup with a rest, and a fall-through"
    return 1
  fi
  setup=$(setup_block) || return 1
  # shellcheck disable=SC2016
  render "$guard"$'\n'"${setup//'${rest}'/$rest}"$'\n'"$tail"
}

stubs() {
  rm -rf "$work/stub" "$work/raco.log" "$work/racket.log"
  mkdir -p "$work/rust/lib" "$work/stub"
  printf 'library\n' > "$work/rust/lib/libcompat.so"
  printf '#!%s\necho "$*" >> %q\n' "$(command -v bash)" "$work/raco.log" > "$work/stub/raco"
  printf '#!%s\necho "$*" >> %q\nprintf %%s %q\n' "$(command -v bash)" \
    "$work/racket.log" "$work/lintbin" > "$work/stub/racket"
  chmod +x "$work/stub/raco" "$work/stub/racket"
}

check_hook() {
  local root=$1 canon hook out want resyntax lines
  canon=$(cd "$root" && pwd -P)
  want=$(key_of "$canon")
  hook=$(render_hook) || { status=1; return 0; }
  resyntax=$(sed -n 's/^      resyntaxSource = "\(.*\)";$/\1/p' "$flake")

  stubs
  out=$(cd "$root/polars/private" && env -u HOME -u XDG_CACHE_HOME \
    PATH="$work/stub:$base_path" bash -c "$hook" 2> "$work/err") \
    || fail "hook, HOME unset: status $?"
  if [ -n "$out" ] || [ -e "$root/polars/native-libs" ] || [ -e "$work/raco.log" ] \
    || [ -e "$work/racket.log" ]; then
    fail "hook, HOME unset: it went on: [$out]"
  elif one_reason "hook, HOME unset" "$work/err"; then
    echo "ok: hook, HOME unset: neither the setup nor Resyntax's runs"
  fi

  stubs
  # shellcheck disable=SC2016
  out=$(cd "$root/polars/private" && env PATH="$work/stub:$base_path" \
    bash -c "$hook"$'\nprintf "PATH=%s\\n" "$PATH"') || fail "hook: status $?"
  lines=$(printf '%s\n' \
    "Setting up rkt-polars in $want (deps changed or first run)" \
    "Done. Run 'raco test -x --timeout 600 -c polars' to test." \
    "Installing Resyntax in $want" \
    "PATH=$work/lintbin:$work/stub:$base_path")
  if [ "$out" != "$lines" ]; then
    fail "hook: output is [$out], not [$lines]"
  elif [ "$(cat "$root/polars/native-libs/libcompat.so" 2> /dev/null)" != library ]; then
    fail "hook: libcompat was not copied into $root/polars/native-libs"
  elif ! compgen -G "$want/.setup-installed-*" > /dev/null; then
    fail "hook: no setup stamp in $want"
  elif ! compgen -G "$want/.resyntax-installed-*" > /dev/null; then
    fail "hook: no Resyntax stamp in $want"
  elif ! grep -qxF -- "pkg install --batch --auto --no-setup --link --scope user --skip-installed --name rkt-polars $canon" "$work/raco.log"; then
    fail "hook: raco did not link $canon: [$(cat "$work/raco.log")]"
  elif ! grep -qxF -- "pkg install --batch --auto --no-docs --scope user --skip-installed $resyntax" "$work/raco.log"; then
    fail "hook: raco did not install $resyntax: [$(cat "$work/raco.log")]"
  else
    echo "ok: hook, from a subdirectory: the setup, then Resyntax's"
  fi
}

check_bench() {
  local root=$1 bench out err
  bench=$(render_bench) || { status=1; return 0; }
  mkdir -p "$root/bench"
  printf '#!%s\nprintf "bench ran: %%s\\n" "$*"\n' "$(command -v bash)" > "$root/bench/run.sh"
  chmod +x "$root/bench/run.sh"

  stubs
  out=$(cd "$root" && env PATH="$work/stub:$base_path" bash -c "$bench" bench --strict) \
    || fail "bench: status $?"
  if [ "${out##*$'\n'}" = "bench ran: --strict" ]; then
    echo "ok: bench runs bench/run.sh with its arguments"
  else
    fail "bench: output is [$out]"
  fi

  stubs
  if out=$(cd "$root" && env -u HOME -u XDG_CACHE_HOME PATH="$work/stub:$base_path" \
    bash -c "$bench" bench 2> "$work/err"); then
    fail "bench, HOME unset: status 0"
  else
    err=$(cat "$work/err")
    if [ -n "$out" ] || [ "$(wc -l < "$work/err")" -ne 2 ] \
      || ! grep -q '^rkt-polars dev shell: .*; skipping the setup$' "$work/err" \
      || [ "${err##*$'\n'}" != "bench: the dev shell setup was skipped, so the bench did not run" ]; then
      fail "bench, HOME unset: stdout [$out], stderr [$err]"
    else
      echo "ok: bench, HOME unset: the shell's reason, its own, and exit 1"
    fi
  fi

  if out=$(cd "$work" && env PATH="$work/stub:$base_path" bash -c "$bench" bench 2>&1); then
    fail "bench outside a checkout: status 0"
  elif [ "$out" != "bench: run from the root of an rkt-polars checkout" ]; then
    fail "bench outside a checkout: [$out]"
  else
    echo "ok: bench outside a checkout"
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
check_bench "$work/repo"

exit $status
