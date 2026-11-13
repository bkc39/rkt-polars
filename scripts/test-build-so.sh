#!/usr/bin/env bash
#
# Stub test of scripts/build-so.sh (#161, #377).  The darwin branch runs a
# copy of the script against fake rustup, cargo and rustc on a PATH of its
# own and builds nothing.  With rustup it must install and call the channel
# rust/rust-toolchain.toml names, `rustup run <channel> cargo build ...`,
# though a nix cargo and rustc that reject `+toolchain` come first on PATH.
# Without rustup it must build with the cargo on PATH when the rustc there is
# that release, and refuse otherwise.  Either way cargo runs without any
# NIX_LDFLAGS* or NIX_CFLAGS* variable, a dylib that otool lists as linked
# against /nix/store or with an LC_RPATH there is refused and not staged, and
# the record names its rustc, LLVM, linker and minimum macOS.  A failed
# cargo build stages nothing and writes no record, though an earlier build's
# dylib is still in the target directory, and a missing otool or ld stops it
# before rustup installs anything.  An earlier build's library and records
# (CI's rust-tree and commit) are gone after a build, failed or not.
#
# Its linux branch runs against a fake docker: for BUILD_SO_MACHINE, without
# asking docker, or else for Docker's machine, x86_64 or aarch64, it runs
# scripts/build-so-linux.sh in the manylinux2014 image pinned by digest for
# that machine, which links the library with rustc's rust-lld and --icf=all
# and records that image.  For another machine, or with no machine from
# `docker info` (podman's), it runs nothing.
#
# The copy runs under $BASH_UNDER_TEST (default: the bash on PATH), so that
# macOS's bash 3.2 can be tested; the stubs run under the bash on PATH.  Each
# case runs under `env -i`, so nothing the caller exports reaches the script.
#
# Usage: [BASH_UNDER_TEST=bash] scripts/test-build-so.sh [build-so.sh to test]
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$(realpath "${1:-$ROOT/scripts/build-so.sh}")"
BASH_BIN="$(command -v bash)"
SHELL_UNDER_TEST="$(command -v "${BASH_UNDER_TEST:-bash}")"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

# What a caller's shell may hold, and no case may see.
export RUSTC=/caller/rustc CARGO=/caller/cargo RUSTUP_TOOLCHAIN=0.0.0 \
  NIX_LDFLAGS_CALLER=-L/nix/store/caller/lib X=caller

# Flag variables of nix's cc wrapper, the dev shell's and others of the two
# prefixes, which build-so.sh must keep from cargo: the stubs report every
# NIX_LDFLAGS* and NIX_CFLAGS* name they are given, not these.
nix_vars=(NIX_LDFLAGS NIX_LDFLAGS_FOR_BUILD NIX_LDFLAGS_FOR_TARGET
  NIX_CFLAGS_COMPILE NIX_CFLAGS_COMPILE_FOR_BUILD NIX_CFLAGS_COMPILE_FOR_TARGET
  NIX_CFLAGS_LINK NIX_CFLAGS_LINK_FOR_BUILD NIX_LDFLAGS_FOO NIX_CFLAGS_BAR)

# A stub's line logging "$1 sees NAME" for each such variable it is given,
# from builtins alone (nixpkgs' bash has no compgen).  A name that is not an
# identifier, which a bash 3.2 stub lists, is not one nix's cc wrapper reads.
sees() {
  # shellcheck disable=SC2016
  printf 'export -p | while read -r _ _ v; do case "${v%%%%=*}" in *[!A-Za-z0-9_]*) ;; NIX_LDFLAGS*|NIX_CFLAGS*) echo "%s sees ${v%%%%=*}" >> %s ;; esac; done\n' \
    "$1" "$(printf '%q' "$log")"
}

# A cargo stub's build: it logs the X it is given, fails as cargo does when
# the case made $cargo_fails, and otherwise writes an empty dylib.
build() {
  # shellcheck disable=SC2016
  printf 'echo "cargo X=${X-unset}" >> %s\n[[ ! -e %s ]] || { echo "error: could not compile polars" >&2; exit 101; }\nmkdir -p %s\n: > %s/libcompat.dylib\n' \
    "$(printf '%q' "$log")" "$(printf '%q' "$cargo_fails")" \
    "$(printf '%q' "$repo/rust/target/dist")" "$(printf '%q' "$repo/rust/target/dist")"
}

failures=0
fail() { echo "FAIL: $*" >&2; failures=$((failures + 1)); }
show() { sed 's/^/  | /' "$1" >&2; }

# A tree holding the script and a toolchain file pinning $1, and a bin
# directory with the host tools the script uses and the fakes.  $2 is "rustup"
# to add a fake rustup; the cargo and rustc on PATH are nix's, which refuse a
# `+toolchain` argument, and that rustc reports release $3.
setup() {
  local channel="$1" rustup="$2" path_release="$3"
  rm -rf "$tmp/case"
  repo="$tmp/case/repo"
  bin="$tmp/case/bin"
  log="$tmp/case/log"
  out="$tmp/case/out"
  cargo_fails="$tmp/case/cargo-fails"
  mkdir -p "$repo/scripts" "$repo/rust" "$bin" "$tmp/case/home"
  cp "$SCRIPT" "$repo/scripts/build-so.sh"
  printf '[toolchain]\nchannel = "%s"\n' "$channel" > "$repo/rust/rust-toolchain.toml"
  : > "$log"
  local tool q_log
  q_log="$(printf '%q' "$log")"
  for tool in awk cat cp dirname head ls mkdir rm sed; do
    ln -s "$(command -v "$tool")" "$bin/$tool"
  done
  for tool in install_name_tool codesign; do
    printf '#!%s\necho "%s $*" >> %s\n' "$BASH_BIN" "$tool" "$q_log" > "$bin/$tool"
  done
  otool_deps="$tmp/case/otool-deps"
  otool_loads="$tmp/case/otool-loads"
  fake_otool /usr/lib/libiconv.2.dylib LC_BUILD_VERSION 11.0
  cat > "$bin/otool" <<EOF
#!$BASH_BIN
echo "otool \$*" >> $q_log
$(sees otool)
case "\$1" in
  -L) echo "\$2:"; cat $(printf '%q' "$otool_deps") ;;
  -l) cat $(printf '%q' "$otool_loads") ;;
  *) exit 2 ;;
esac
EOF
  printf '#!%s\necho "@(#)PROGRAM:ld fake"\n' "$BASH_BIN" > "$bin/ld"
  cat > "$bin/cargo" <<EOF
#!$BASH_BIN
echo "PATH cargo \$* RUSTC=\${RUSTC:-unset}" >> $q_log
$(sees cargo)
[[ "\$1" != +* ]] || { echo "error: no such command: \\\`\$1\\\`" >&2; exit 101; }
$(build)
EOF
  cat > "$bin/rustc" <<EOF
#!$BASH_BIN
echo "PATH rustc \$*" >> $q_log
[[ "\$1" != +* ]] || { echo "error: couldn't read \$1: No such file" >&2; exit 1; }
printf 'rustc %s (nix)\nrelease: %s\nLLVM version: 19.1.7\n' $path_release $path_release
EOF
  if [[ "$rustup" == rustup ]]; then
    cat > "$bin/rustup" <<EOF
#!$BASH_BIN
set -euo pipefail
echo "rustup \$*" >> $q_log
case "\$1" in
  toolchain) [[ "\$2" == install ]] || exit 2 ;;
  which)
    [[ "\$2" == --toolchain && "\$4" == rustc ]] || exit 2
    echo "/rustup/toolchains/\$3/bin/rustc"
    ;;
  run)
    t="\$2"; shift 2
    echo "run \$t \$* RUSTC=\${RUSTC:-unset}" >> $q_log
    case "\$1" in
      rustc) printf 'rustc %s (rustup)\nrelease: %s\nLLVM version: 20.1.8\n' "\$t" "\$t" ;;
      cargo)
        $(sees cargo)
        $(build)
        ;;
      *) exit 2 ;;
    esac
    ;;
  *) exit 2 ;;
esac
EOF
  fi
  for tool in "$bin"/*; do
    [[ -L "$tool" ]] || chmod +x "$tool"
  done
  distinct_ignoring_case "$tmp/case" "$log" "$out" "$cargo_fails" \
    "$otool_deps" "$otool_loads"
}

# Exits unless the paths named, and every path under $1, differ beyond case:
# APFS folds case, so two such names there are one file.
distinct_ignoring_case() {
  local clash
  clash="$({ find "$1"; printf '%s\n' "${@:2}"; } | sort -u | tr '[:upper:]' '[:lower:]' | sort | uniq -d)"
  [[ -z "$clash" ]] || {
    echo "test-build-so: paths that differ only in case: $clash" >&2
    exit 1
  }
}

# The fake otool's answers: -L lists $1 and libSystem after the install name,
# -l prints load command $2 with minimum macOS $3 after a LC_SOURCE_VERSION,
# whose own `version` line must not be read, then an LC_RPATH of $4 and $5
# more load commands (none by default).
fake_otool() {
  local dep="$1" cmd="$2" min="$3" rpath="${4:-@loader_path/../lib}" more="${5:-0}"
  printf '\t%s (compatibility version 0.0.0, current version 0.0.0)\n' \
    "$repo/rust/target/dist/libcompat.dylib" "$dep" /usr/lib/libSystem.B.dylib > "$otool_deps"
  {
    printf 'Load command 0\n      cmd LC_SOURCE_VERSION\n  cmdsize 16\n  version 0.0\n'
    case "$cmd" in
      LC_BUILD_VERSION)
        printf 'Load command 1\n      cmd LC_BUILD_VERSION\n  cmdsize 32\n platform 1\n'
        printf '    minos %s\n      sdk 15.0\n   ntools 1\n     tool 3\n  version 1115.7\n' "$min" ;;
      LC_VERSION_MIN_MACOSX)
        printf 'Load command 1\n      cmd LC_VERSION_MIN_MACOSX\n  cmdsize 16\n'
        printf '  version %s\n      sdk 10.15\n' "$min" ;;
    esac
    printf 'Load command 2\n          cmd LC_RPATH\n      cmdsize 32\n         path %s (offset 12)\n' "$rpath"
    awk -v n="$more" 'BEGIN {
      for (i = 3; i < n + 3; i++)
        printf "Load command %d\n          cmd LC_LOAD_DYLIB\n      cmdsize 56\n         name /usr/lib/libz.1.dylib (offset 24)\n", i
    }'
  } > "$otool_loads"
}

# Arguments are more NAME=value pairs for the script's environment.
run_script() {
  local v nix_env=()
  for v in "${nix_vars[@]}"; do nix_env+=("$v=-L/nix/store/fake-libiconv/lib"); done
  env -i PATH="$bin" HOME="$tmp/case/home" "${nix_env[@]}" "$@" \
    "$SHELL_UNDER_TEST" "$repo/scripts/build-so.sh" darwin > "$out" 2>&1
}

# $3 is the rustc that ran: rustup's, or nix's on PATH.
expect_built() {
  local what="$1" channel="$2" rustc="$3" minos="${4:-11.0}" v llvm line
  local record="$repo/rust/target/libcompat/darwin/toolchain"
  [[ -f "$repo/rust/target/libcompat/darwin/libcompat.dylib" ]] \
    || fail "$what: no staged libcompat.dylib"
  grep -qxF "release: $channel" "$record" \
    || fail "$what: the toolchain record does not name release $channel"
  grep -qxF "minos: $minos" "$record" \
    || { fail "$what: the toolchain record does not name minos $minos:"; show "$record"; }
  for v in "${nix_vars[@]}"; do
    grep -qxF "otool sees $v" "$log" || fail "$what: build-so.sh was not given $v"
  done
  if grep -q '^cargo sees ' "$log"; then
    fail "$what: cargo ran with $(sed -n 's/^cargo sees //p' "$log" | paste -sd ' ' -)"
  fi
  case "$rustc" in rustup) llvm=20.1.8 ;; *) llvm=19.1.7 ;; esac
  for line in "rustc $channel ($rustc)" "LLVM version: $llvm" "ld: @(#)PROGRAM:ld fake"; do
    grep -qxF "$line" "$record" \
      || { fail "$what: the toolchain record lacks the line '$line':"; show "$record"; }
  done
}

expect_refused() {
  local what="$1" message="$2"
  if run_script; then
    fail "$what: build-so.sh darwin succeeded"
  fi
  grep -qF "$message" "$out" || { fail "$what: no '$message' in the output:"; show "$out"; }
  [[ ! -e "$repo/rust/target/libcompat/darwin/libcompat.dylib" ]] \
    || fail "$what: the refused dylib was staged"
}

# With rustup, for the real pin and another channel, so the script reads the
# channel rather than naming it, and with nix's cargo first on PATH.
pinned="$(sed -n 's/^channel = "\([^"]*\)"$/\1/p' "$ROOT/rust/rust-toolchain.toml")"
for channel in "$pinned" 1.2.3; do
  what="rustup, $channel"
  setup "$channel" rustup 0.0.0
  if ! run_script; then
    fail "$what: build-so.sh darwin exited non-zero"
    show "$out"
    continue
  fi
  for want in \
    "rustup toolchain install $channel --profile minimal --no-self-update" \
    "run $channel cargo build --profile dist --locked --config target.'cfg(all())'.rustflags=['--remap-path-prefix=$tmp/case/home/.cargo=/cargo'] --manifest-path $repo/rust/Cargo.toml RUSTC=/rustup/toolchains/$channel/bin/rustc"; do
    grep -qxF "$want" "$log" || { fail "$what: no line '$want' in the log:"; show "$log"; }
  done
  if grep -q '^PATH ' "$log"; then
    fail "$what: the cargo or rustc on PATH ran: $(grep '^PATH ' "$log")"
  fi
  expect_built "$what" "$channel" rustup
done

# Without rustup, the rustc on PATH is checked, and its cargo builds.
what="no rustup, PATH rustc $pinned"
setup "$pinned" no-rustup "$pinned"
if run_script; then
  want="PATH cargo build --profile dist --locked --config target.'cfg(all())'.rustflags=['--remap-path-prefix=$tmp/case/home/.cargo=/cargo'] --manifest-path $repo/rust/Cargo.toml RUSTC=unset"
  grep -qxF "$want" "$log" || { fail "$what: no line '$want' in the log:"; show "$log"; }
  expect_built "$what" "$pinned" nix
else
  fail "$what: build-so.sh darwin exited non-zero"
  show "$out"
fi

what="no rustup, PATH rustc 0.0.0"
setup "$pinned" no-rustup 0.0.0
if run_script; then
  fail "$what: build-so.sh darwin succeeded"
fi
grep -qxF "error: rustc is 0.0.0; rust/rust-toolchain.toml pins $pinned" "$out" \
  || { fail "$what: no release error in the output:"; show "$out"; }
if grep -q ' cargo build ' "$log"; then
  fail "$what: cargo build ran"
fi

# A dylib linked against the nix store or searching it, one with only the
# older load command, and one whose load commands go on long after the
# minimum macOS, through rustup and without it.
store_dir=/nix/store/0123456789abcdfghijklmnpqrsvwxyz-libiconv-109/lib
for mode in rustup no-rustup; do
  case "$mode" in rustup) rustc=rustup ;; *) rustc=nix ;; esac
  what="$mode, a /nix/store dependency"
  setup "$pinned" "$mode" "$pinned"
  fake_otool "$store_dir/libiconv.2.dylib" LC_BUILD_VERSION 11.0
  expect_refused "$what" "links against or searches the nix store"
  grep -qF "$store_dir/libiconv.2.dylib (compatibility version" "$out" \
    || { fail "$what: the refusal does not name the dependency:"; show "$out"; }
  advice="$(grep -F "build outside the nix dev shell" "$out")" \
    || { fail "$what: the refusal does not say how to build:"; show "$out"; }
  [[ "$advice" != *NIX_* ]] \
    || fail "$what: the refusal asks for a variable build-so.sh unsets: $advice"

  what="$mode, a /nix/store LC_RPATH"
  setup "$pinned" "$mode" "$pinned"
  fake_otool /usr/lib/libiconv.2.dylib LC_BUILD_VERSION 11.0 "$store_dir"
  expect_refused "$what" "links against or searches the nix store"
  grep -qxF "$(printf '\tLC_RPATH %s' "$store_dir")" "$out" \
    || { fail "$what: the refusal does not name the LC_RPATH:"; show "$out"; }

  what="$mode, LC_VERSION_MIN_MACOSX"
  setup "$pinned" "$mode" "$pinned"
  fake_otool /usr/lib/libiconv.2.dylib LC_VERSION_MIN_MACOSX 10.12
  if run_script; then
    expect_built "$what" "$pinned" "$rustc" 10.12
  else
    fail "$what: build-so.sh darwin exited non-zero"
    show "$out"
  fi

  what="$mode, 40000 load commands after the minimum macOS"
  setup "$pinned" "$mode" "$pinned"
  fake_otool /usr/lib/libiconv.2.dylib LC_BUILD_VERSION 11.0 "" 40000
  if run_script; then
    expect_built "$what" "$pinned" "$rustc"
  else
    fail "$what: build-so.sh darwin exited non-zero"
    show "$out"
  fi
done

what="no load command naming a minimum macOS"
setup "$pinned" rustup "$pinned"
fake_otool /usr/lib/libiconv.2.dylib none ""
expect_refused "$what" "has no LC_BUILD_VERSION or LC_VERSION_MIN_MACOSX"

for tool in otool ld; do
  what="no $tool"
  setup "$pinned" rustup "$pinned"
  rm "$bin/$tool"
  expect_refused "$what" "error: $tool not found"
  if grep -q ' cargo build ' "$log"; then
    fail "$what: cargo build ran"
  fi
  if grep -q '^rustup toolchain install ' "$log"; then
    fail "$what: rustup installed the toolchain"
  fi
  [[ ! -e "$repo/rust/target/libcompat/darwin/toolchain" ]] \
    || fail "$what: a toolchain record was written"
done

# An earlier build's staged dylib and records in the output directory.
plant_stale() {
  local staged="$repo/rust/target/libcompat/darwin" record
  mkdir -p "$staged"
  for record in libcompat.dylib rust-tree commit toolchain; do
    echo stale > "$staged/$record"
  done
}

expect_no_stale() {
  local what="$1" record
  for record in libcompat.dylib rust-tree commit toolchain; do
    if grep -qx stale "$repo/rust/target/libcompat/darwin/$record" 2>/dev/null; then
      fail "$what: the earlier build's $record is still staged"
    fi
  done
}

# A failed build beside an earlier build's dylib, which bash 3.2 would stage
# if the build's subshell were not checked.
for mode in rustup no-rustup; do
  what="$mode, cargo fails beside a stale dylib"
  setup "$pinned" "$mode" "$pinned"
  mkdir -p "$repo/rust/target/dist"
  echo stale > "$repo/rust/target/dist/libcompat.dylib"
  plant_stale
  : > "$cargo_fails"
  expect_refused "$what" "error: could not compile polars"
  [[ ! -e "$repo/rust/target/libcompat/darwin/toolchain" ]] \
    || fail "$what: a toolchain record was written"
  expect_no_stale "$what"
done

what="a build over an earlier build's records"
setup "$pinned" rustup "$pinned"
plant_stale
if run_script; then
  expect_built "$what" "$pinned" rustup
  expect_no_stale "$what"
else
  fail "$what: build-so.sh darwin exited non-zero"
  show "$out"
fi

# Environment names that are not identifiers, which bash 3.2 imports as
# variables: build-so.sh must leave X alone, not fail on the `*`, and not
# hand such a name to unset, which refuses it and goes on.
for odd in 'NIX_CFLAGS X=1' 'NIX_CFLAGS*=1'; do
  what="the environment name '${odd%%=*}'"
  setup "$pinned" rustup "$pinned"
  if run_script "$odd" X=kept; then
    grep -qxF "cargo X=kept" "$log" || { fail "$what: cargo was not given X=kept:"; show "$log"; }
    if grep -qF "not a valid identifier" "$out"; then
      fail "$what: build-so.sh unset a name that is not an identifier:"
      show "$out"
    fi
    expect_built "$what" "$pinned" rustup
  else
    fail "$what: build-so.sh darwin exited non-zero"
    show "$out"
  fi
done

# The linux branch against a fake docker on Docker machine $1, where an empty
# $1 is a `docker info` that fails, as podman's does on this format.  The rest
# are NAME=value pairs for the script's environment.
linux_case() {
  local machine="$1" q_log
  shift
  rm -rf "$tmp/case"
  repo="$tmp/case/repo"
  bin="$tmp/case/bin"
  log="$tmp/case/log"
  out="$tmp/case/out"
  mkdir -p "$repo/scripts" "$repo/rust" "$bin" "$tmp/case/home"
  cp "$SCRIPT" "$repo/scripts/build-so.sh"
  cp "$LINUX_SCRIPT" "$repo/scripts/build-so-linux.sh"
  printf '[toolchain]\nchannel = "%s"\n' "$pinned" > "$repo/rust/rust-toolchain.toml"
  : > "$log"
  q_log="$(printf '%q' "$log")"
  for tool in cat dirname head ls mkdir rm sed; do
    ln -s "$(command -v "$tool")" "$bin/$tool"
  done
  cat > "$bin/docker" <<EOF
#!$BASH_BIN
case "\$1" in
  info)
    echo "docker info" >> $q_log
    [[ -n $(printf '%q' "$machine") ]] || { echo 'Error: template: info:1:2: executing "info" at <.Architecture>: can'"'"'t evaluate field Architecture' >&2; exit 125; }
    echo $(printf '%q' "$machine"); exit 0 ;;
  run) shift ;;
  *) exit 2 ;;
esac
dest= src=
while [[ \$# -gt 0 && "\$1" == -* ]]; do
  case "\$1" in
    -v)
      [[ "\$2" != *:/out ]] || dest="\${2%:/out}"
      [[ "\$2" != *:/src:ro ]] || src="\${2%:/src:ro}"
      shift 2 ;;
    -e) shift 2 ;;
    *) shift ;;
  esac
done
echo "docker run \$*" >> $q_log
[[ "\$3" != /src/* || -f "\$src\${3#/src}" ]] || { echo "bash: \$3: No such file or directory" >&2; exit 127; }
: > "\$dest/libcompat.so"
printf 'rustc $pinned\nimage: %s\n' "\$1" > "\$dest/toolchain"
EOF
  chmod +x "$bin/docker"
  env -i PATH="$bin" HOME="$tmp/case/home" "$@" \
    "$SHELL_UNDER_TEST" "$repo/scripts/build-so.sh" linux > "$out" 2>&1
}

pinned_image() {
  sed -n "s|^MANYLINUX_IMAGE_$1=\\(.*\\)\$|\\1|p" "$SCRIPT"
}

# expect_linux_built WHAT MACHINE: the image pinned for MACHINE ran the
# container script, and the record names it.
expect_linux_built() {
  local what="$1" machine="$2" image
  image="$(pinned_image "$machine")"
  [[ "$image" == "quay.io/pypa/manylinux2014_$machine:"*@sha256:* ]] \
    || fail "$what: build-so.sh pins [$image], not manylinux2014_$machine by digest"
  grep -qxF "docker run $image bash /src/scripts/build-so-linux.sh" "$log" \
    || { fail "$what: docker did not run scripts/build-so-linux.sh in $image:"; show "$log"; show "$out"; }
  grep -qxF "image: $image" "$repo/rust/target/libcompat/linux/toolchain" \
    || fail "$what: the record does not name $image"
}

expect_linux_refused() {
  local what="$1" message="$2"
  grep -qF -- "$message" "$out" || { fail "$what: no [$message] in the output:"; show "$out"; }
  if grep -q '^docker run' "$log"; then
    fail "$what: docker ran an image:"
    show "$log"
  fi
}

LINUX_SCRIPT="$(dirname "$SCRIPT")/build-so-linux.sh"
# shellcheck disable=SC2016
for flag in '-C "link-arg=-B$gcc_ld"' '-C link-arg=-fuse-ld=lld' '-C link-arg=-Wl,--icf=all' \
  '[ ! -x "$gcc_ld/ld.lld" ]' '--profile dist-linux' 'echo "image: $MANYLINUX_IMAGE"'; do
  grep -qF -- "$flag" "$LINUX_SCRIPT" \
    || fail "scripts/build-so-linux.sh lacks [$flag]"
done

for machine in x86_64 aarch64; do
  what="linux on $machine"
  if linux_case "$machine"; then
    expect_linux_built "$what" "$machine"
  else
    fail "$what: build-so.sh linux exited non-zero"
    show "$out"
  fi
done

for machine in x86_64 aarch64; do
  what="linux, BUILD_SO_MACHINE=$machine on another Docker"
  case "$machine" in x86_64) docker_machine=aarch64 ;; *) docker_machine=x86_64 ;; esac
  if linux_case "$docker_machine" BUILD_SO_MACHINE="$machine"; then
    expect_linux_built "$what" "$machine"
    if grep -q '^docker info' "$log"; then
      fail "$what: build-so.sh asked docker info"
    fi
  else
    fail "$what: build-so.sh linux exited non-zero"
    show "$out"
  fi
done

what="linux, BUILD_SO_MACHINE=x86_64 under a docker info that fails"
if linux_case "" BUILD_SO_MACHINE=x86_64; then
  expect_linux_built "$what" x86_64
else
  fail "$what: build-so.sh linux exited non-zero"
  show "$out"
fi

what="linux on armv7l"
if linux_case armv7l; then
  fail "$what: build-so.sh linux succeeded"
fi
expect_linux_refused "$what" "error: Docker runs on 'armv7l'; the Linux library builds on one of: aarch64 x86_64"

for machine in armv7l x86-64 'x86_64 ' ../x86_64; do
  what="linux, BUILD_SO_MACHINE=[$machine]"
  if linux_case x86_64 BUILD_SO_MACHINE="$machine"; then
    fail "$what: build-so.sh linux succeeded"
  fi
  expect_linux_refused "$what" "error: BUILD_SO_MACHINE is '$machine'; the Linux library builds on one of: aarch64 x86_64"
done

what="linux, no BUILD_SO_MACHINE and a docker info that fails"
if linux_case ""; then
  fail "$what: build-so.sh linux succeeded"
fi
expect_linux_refused "$what" "error: docker info names no machine; set BUILD_SO_MACHINE to one of: aarch64 x86_64"

if ((failures > 0)); then
  echo "test-build-so: $failures failure(s)" >&2
  exit 1
fi
echo "test-build-so: ok"
