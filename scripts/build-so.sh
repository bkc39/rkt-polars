#!/usr/bin/env bash
#
# Build the libcompat shared object with cargo and stage it as a committed,
# per-platform candidate under polars/native-libs/candidates/<platform>/.
#
# This is the cargo analogue of the cmake-based build-so.sh in the xgboost
# Racket binding.  The candidates are what pkgs.rkt-lang.org installs from,
# since its build host has no Rust toolchain.
#
# Usage:
#   scripts/build-so.sh [platform]
#
# platform defaults to the current OS (linux or darwin).
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

echo ">> cargo build --release (manifest: rust/Cargo.toml)"
cargo build --release --manifest-path "$ROOT/rust/Cargo.toml"

built="$ROOT/rust/target/release/$lib"
if [[ ! -f "$built" ]]; then
  echo "error: expected build output not found: $built" >&2
  exit 1
fi

mkdir -p "$dest"
cp -f "$built" "$dest/$lib"
echo ">> staged $dest/$lib"

# cargo bakes the absolute build path into the dylib's install name (LC_ID).
# Racket loads libcompat by path via dlopen, so the id is never resolved, but
# rewrite it to @rpath so the committed binary carries no machine-specific
# path.  (ELF .so files have no such embedded path, so this is darwin-only.)
if [[ "$platform" == "darwin" ]] && command -v install_name_tool >/dev/null 2>&1; then
  install_name_tool -id "@rpath/$lib" "$dest/$lib"
fi

# On Linux, lower the glibc floor of libcompat.so to 2.17 so it loads on
# pkg-build.racket-lang.org's old-glibc test host (glibc < 2.27).  Mirrors the
# xgboost binding: build a tiny shim (libcompatshim.so) for the symbols
# polyfill-glibc can't rewrite, run polyfill-glibc --target-glibc=2.17, then
# set RPATH=$ORIGIN so the shim resolves from native-libs/ at load time.
# gcc / patchelf / polyfill-glibc all come from Nix, so this runs the same in
# CI and on a Linux dev box.
if [[ "$platform" == "linux" ]]; then
  script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

  echo ">> building libcompatshim.so"
  cc_pkg=$(nix build --no-link --print-out-paths 'nixpkgs#gcc^out')
  "$cc_pkg/bin/gcc" -shared -fPIC -O2 \
    -Wl,-soname,libcompatshim.so \
    -o "$dest/libcompatshim.so" \
    "$script_dir/glibc-shim.c"

  patchelf=$(nix build --no-link --print-out-paths nixpkgs#patchelf)/bin/patchelf
  polyfill=$(nix build --no-link --print-out-paths .#polyfill-glibc)/bin/polyfill-glibc

  echo ">> polyfilling libcompat.so to require only glibc <= 2.17"
  "$polyfill" --rename-dynamic-symbols="$script_dir/glibc-renames.txt" \
              --target-glibc=2.17 "$dest/$lib"
  "$patchelf" --set-rpath '$ORIGIN' "$dest/$lib"

  floor=$(objdump -T "$dest/$lib" 2>/dev/null | grep -oE 'GLIBC_[0-9]+\.[0-9]+' | sort -V -u | tail -1)
  echo ">> libcompat.so max glibc dep now: ${floor:-unknown}"
  echo ">> libcompatshim.so glibc deps: $(objdump -T "$dest/libcompatshim.so" 2>/dev/null | grep -oE 'GLIBC_[0-9]+\.[0-9]+' | sort -V -u | tr '\n' ' ')"
fi

# Sanity: show the dynamic dependencies so a reviewer can confirm the
# binary is self-contained (system libs only, no /nix/store paths).
echo ">> dynamic dependencies:"
if command -v otool >/dev/null 2>&1; then
  otool -L "$dest/$lib"
elif command -v ldd >/dev/null 2>&1; then
  ldd "$dest/$lib" || true
fi

ls -la "$dest"
