#!/usr/bin/env bash
#
# The Linux half of scripts/build-so.sh, which runs it inside the manylinux2014
# image with the checkout at /src (read-only) and the output directory at
# /out.  It installs RUST_TOOLCHAIN with rustup, builds libcompat.so with the
# dist-linux profile in a container-local target directory, and copies the
# library and the record of the toolchain and MANYLINUX_IMAGE to /out.
set -euo pipefail

curl --proto "=https" --tlsv1.2 -sSf https://sh.rustup.rs \
  | sh -s -- -y --default-toolchain "$RUST_TOOLCHAIN" --profile minimal
# shellcheck source=/dev/null
. "$HOME/.cargo/env"

# GNU ld lacks --icf=all and rustc links with rust-lld by default on x86_64 alone.
gcc_ld="$(rustc --print sysroot)/lib/rustlib/$(rustc -vV | sed -n 's/^host: //p')/bin/gcc-ld"
if [ ! -x "$gcc_ld/ld.lld" ]; then
  echo "error: rustc $RUST_TOOLCHAIN has no $gcc_ld/ld.lld to link with --icf=all" >&2
  exit 1
fi
RUSTFLAGS="--remap-path-prefix=$HOME/.cargo=/cargo" cargo rustc --lib --profile dist-linux --locked \
  --manifest-path /src/rust/Cargo.toml --target-dir /tmp/target \
  -- -C "link-arg=-B$gcc_ld" -C link-arg=-fuse-ld=lld -C link-arg=-Wl,--icf=all
cp /tmp/target/dist-linux/libcompat.so /out/
{ rustc -vV; echo "image: $MANYLINUX_IMAGE"; } > /out/toolchain
