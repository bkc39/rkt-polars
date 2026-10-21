#!/usr/bin/env bash
#
# Stub test of scripts/build-so.sh's darwin branch (#161): runs a copy of the
# script against fake rustup, cargo and rustc on a PATH of its own and builds
# nothing.  With rustup it must install and call the channel
# rust/rust-toolchain.toml names, `rustup run <channel> cargo build ...`,
# though a nix cargo and rustc that reject `+toolchain` come first on PATH.
# Without rustup it must build with the cargo on PATH when the rustc there is
# that release, and refuse otherwise.
#
# Usage: scripts/test-build-so.sh [build-so.sh to test]
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$(realpath "${1:-$ROOT/scripts/build-so.sh}")"
BASH_BIN="$(command -v bash)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

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
  mkdir -p "$repo/scripts" "$repo/rust" "$bin"
  cp "$SCRIPT" "$repo/scripts/build-so.sh"
  printf '[toolchain]\nchannel = "%s"\n' "$channel" > "$repo/rust/rust-toolchain.toml"
  : > "$log"
  local tool q_log q_repo
  q_log="$(printf '%q' "$log")"
  q_repo="$(printf '%q' "$repo")"
  for tool in awk cp dirname head ls mkdir sed; do
    ln -s "$(command -v "$tool")" "$bin/$tool"
  done
  for tool in install_name_tool codesign otool; do
    printf '#!%s\necho "%s $*" >> %s\n' "$BASH_BIN" "$tool" "$q_log" > "$bin/$tool"
  done
  printf '#!%s\necho "@(#)PROGRAM:ld fake"\n' "$BASH_BIN" > "$bin/ld"
  cat > "$bin/cargo" <<EOF
#!$BASH_BIN
echo "PATH cargo \$* RUSTC=\${RUSTC:-unset}" >> $q_log
[[ "\$1" != +* ]] || { echo "error: no such command: \\\`\$1\\\`" >&2; exit 101; }
mkdir -p $q_repo/rust/target/dist
: > $q_repo/rust/target/dist/libcompat.dylib
EOF
  cat > "$bin/rustc" <<EOF
#!$BASH_BIN
echo "PATH rustc \$*" >> $q_log
[[ "\$1" != +* ]] || { echo "error: couldn't read \$1: No such file" >&2; exit 1; }
printf 'rustc %s (nix)\nrelease: %s\n' $path_release $path_release
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
      rustc) printf 'rustc %s (rustup)\nrelease: %s\n' "\$t" "\$t" ;;
      cargo) mkdir -p $q_repo/rust/target/dist
             : > $q_repo/rust/target/dist/libcompat.dylib ;;
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
}

run_script() {
  PATH="$bin" "$BASH_BIN" "$repo/scripts/build-so.sh" darwin > "$out" 2>&1
}

expect_built() {
  local what="$1" channel="$2"
  [[ -f "$repo/polars/native-libs/candidates/darwin/libcompat.dylib" ]] \
    || fail "$what: no staged libcompat.dylib"
  grep -qxF "release: $channel" "$repo/polars/native-libs/candidates/darwin/toolchain" \
    || fail "$what: the toolchain record does not name release $channel"
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
    "run $channel cargo build --profile dist --locked --manifest-path $repo/rust/Cargo.toml RUSTC=/rustup/toolchains/$channel/bin/rustc"; do
    grep -qxF "$want" "$log" || { fail "$what: no line '$want' in the log:"; show "$log"; }
  done
  if grep -q '^PATH ' "$log"; then
    fail "$what: the cargo or rustc on PATH ran: $(grep '^PATH ' "$log")"
  fi
  expect_built "$what" "$channel"
done

# Without rustup, the rustc on PATH is checked, and its cargo builds.
what="no rustup, PATH rustc $pinned"
setup "$pinned" no-rustup "$pinned"
if run_script; then
  want="PATH cargo build --profile dist --locked --manifest-path $repo/rust/Cargo.toml RUSTC=unset"
  grep -qxF "$want" "$log" || { fail "$what: no line '$want' in the log:"; show "$log"; }
  expect_built "$what" "$pinned"
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

if ((failures > 0)); then
  echo "test-build-so: $failures failure(s)" >&2
  exit 1
fi
echo "test-build-so: ok"
