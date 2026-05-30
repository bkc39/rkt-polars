#!/usr/bin/env bash
#
# Build the libcompat shared object and stage it as a committed, per-platform
# candidate under polars/native-libs/candidates/<platform>/.  The candidates
# are what pkgs.rkt-lang.org installs from, since its build host has no Rust
# toolchain.
#
# Linux: built inside the manylinux2014 container (glibc 2.17) so the .so
# requires only GLIBC <= 2.17 and loads on every Linux from the last decade,
# including pkg-build.racket-lang.org's test host (glibc < 2.27).  Building
# natively against an old glibc avoids any ELF post-processing.
#
# Darwin: built natively with cargo.
#
# Usage:
#   scripts/build-so.sh [platform]      # platform defaults to current OS
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

platform="${1:-}"
if [[ -z "$platform" ]]; then
  case "$(uname -s)" in
    Linux)  platform="linux" ;;
    Darwin) platform="darwin" ;;
    *) echo "error: unsupported OS '$(uname -s)'; pass linux|darwin" >&2; exit 1 ;;
  esac
fi

case "$platform" in
  linux)  ext="so" ;;
  darwin) ext="dylib" ;;
  *) echo "error: unknown platform '$platform' (expected linux|darwin)" >&2; exit 1 ;;
esac

lib="libcompat.${ext}"
dest="$ROOT/polars/native-libs/candidates/$platform"
mkdir -p "$dest"

if [[ "$platform" == "linux" ]]; then
  # Build against glibc 2.17 inside manylinux2014.  The source is mounted
  # read-only; cargo writes to a container-local target dir and copies just
  # the .so out to the mounted candidate directory.
  echo ">> building $lib inside manylinux2014 (glibc 2.17)"
  docker run --rm \
    -v "$ROOT:/src:ro" \
    -v "$dest:/out" \
    quay.io/pypa/manylinux2014_x86_64 bash -ec '
      set -euo pipefail
      curl --proto "=https" --tlsv1.2 -sSf https://sh.rustup.rs \
        | sh -s -- -y --default-toolchain stable --profile minimal
      . "$HOME/.cargo/env"
      cargo build --release --locked \
        --manifest-path /src/rust/Cargo.toml --target-dir /tmp/target
      cp /tmp/target/release/libcompat.so /out/
    '
  echo ">> staged $dest/$lib"
else
  echo ">> cargo build --release (manifest: rust/Cargo.toml)"
  cargo build --release --manifest-path "$ROOT/rust/Cargo.toml"

  built="$ROOT/rust/target/release/$lib"
  if [[ ! -f "$built" ]]; then
    echo "error: expected build output not found: $built" >&2
    exit 1
  fi
  cp -f "$built" "$dest/$lib"
  echo ">> staged $dest/$lib"

  # cargo bakes the absolute build path into the dylib's install name (LC_ID).
  # Racket loads libcompat by path via dlopen, so the id is never resolved, but
  # rewrite it to @rpath so the committed binary carries no machine-specific
  # path.
  if command -v install_name_tool >/dev/null 2>&1; then
    install_name_tool -id "@rpath/$lib" "$dest/$lib"
  fi
fi

# Sanity: show the dynamic dependencies / glibc floor so a reviewer can
# confirm the binary is portable.
echo ">> dynamic dependencies:"
if command -v otool >/dev/null 2>&1; then
  otool -L "$dest/$lib"
elif command -v objdump >/dev/null 2>&1; then
  echo "max glibc dep: $(objdump -T "$dest/$lib" 2>/dev/null | grep -oE 'GLIBC_[0-9]+\.[0-9]+' | sort -V -u | tail -1)"
elif command -v ldd >/dev/null 2>&1; then
  ldd "$dest/$lib" || true
fi

ls -la "$dest"
