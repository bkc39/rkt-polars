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
# Darwin: built natively with cargo, on the pinned rustc: with rustup, its
# toolchain (installed when missing) through `rustup run`, whatever cargo is
# first on PATH (nix's dev shell puts nixpkgs' there, which rejects
# `+toolchain`, #161); without rustup, the one on PATH if it is that release.
#
# Beside the library it writes `toolchain`: the `rustc -vV` that built it, and
# the image (Linux) or the linker and the minimum macOS (darwin).  CI uploads
# it with the candidate.
#
# Usage:
#   scripts/build-so.sh [platform]      # platform defaults to current OS
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# The release rustc, which rust/rust-toolchain.toml pins to the flake's rustc
# release (nixpkgs at flake.lock).  This is rustup's build of that release,
# whose LLVM can differ from nixpkgs', so the tests nix runs do not cover its
# code generation; CI's jobs that install the built library do.  polars'
# `nightly` feature needs RUSTC_BOOTSTRAP=1 on it, as the flake's build sets.
RUST_TOOLCHAIN="$(sed -n 's/^channel = "\([^"]*\)"$/\1/p' "$ROOT/rust/rust-toolchain.toml")"
if [[ -z "$RUST_TOOLCHAIN" ]]; then
  echo "error: no channel = \"<version>\" line in rust/rust-toolchain.toml" >&2
  exit 1
fi
export RUSTC_BOOTSTRAP=1

# The Linux build image, by digest: its tags move every few days, and it
# supplies the linker.  scripts/refresh-toolchain.sh moves it.
MANYLINUX_IMAGE=quay.io/pypa/manylinux2014_x86_64:2026.09.30-1@sha256:3462ead9a7152857bb8efd2ddc0014c729be718c531a95c5a949a28b99e5e585

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
  # the .so, and the record of the toolchain that built it, out to the
  # mounted candidate directory.
  echo ">> building $lib inside $MANYLINUX_IMAGE (glibc 2.17)"
  docker run --rm \
    -e RUSTC_BOOTSTRAP \
    -e RUST_TOOLCHAIN="$RUST_TOOLCHAIN" \
    -e MANYLINUX_IMAGE="$MANYLINUX_IMAGE" \
    -v "$ROOT:/src:ro" \
    -v "$dest:/out" \
    "$MANYLINUX_IMAGE" bash -ec '
      set -euo pipefail
      curl --proto "=https" --tlsv1.2 -sSf https://sh.rustup.rs \
        | sh -s -- -y --default-toolchain "$RUST_TOOLCHAIN" --profile minimal
      . "$HOME/.cargo/env"
      cargo build --profile dist --locked \
        --manifest-path /src/rust/Cargo.toml --target-dir /tmp/target
      cp /tmp/target/dist/libcompat.so /out/
      { rustc -vV; echo "image: $MANYLINUX_IMAGE"; } > /out/toolchain
    '
  echo ">> staged $dest/$lib"
else
  cargo=(cargo)
  rustc=(rustc)
  if command -v rustup >/dev/null 2>&1; then
    rustup toolchain install "$RUST_TOOLCHAIN" --profile minimal --no-self-update
    cargo=(rustup run "$RUST_TOOLCHAIN" cargo)
    rustc=(rustup run "$RUST_TOOLCHAIN" rustc)
    # cargo would otherwise take the rustc first on PATH, which rustup run
    # need not have put ahead of nix's.
    RUSTC="$(rustup which --toolchain "$RUST_TOOLCHAIN" rustc)"
    export RUSTC
  fi
  release="$("${rustc[@]}" -vV | sed -n 's/^release: //p')" || true
  if [[ "$release" != "$RUST_TOOLCHAIN" ]]; then
    echo "error: rustc is ${release:-missing}; rust/rust-toolchain.toml pins $RUST_TOOLCHAIN" >&2
    exit 1
  fi
  if ! command -v otool >/dev/null 2>&1; then
    echo "error: otool not found; it checks the dylib's dependencies and minimum macOS" >&2
    exit 1
  fi
  echo ">> ${cargo[*]} build --profile dist --locked (manifest: rust/Cargo.toml)"
  # In the nix dev shell rustc links through nix's cc wrapper, which adds the
  # search paths its NIX_LDFLAGS* and NIX_CFLAGS* variables name (each in a
  # _FOR_BUILD and a _FOR_TARGET form too), and a library found there
  # (libiconv) would be linked by its /nix/store path.
  (
    # Unquoted: the expansions are variable names, which never split or glob,
    # and an empty one is then no word at all in any bash (3.2 on macOS).
    # shellcheck disable=SC2086
    unset -v ${!NIX_LDFLAGS@} ${!NIX_CFLAGS@}
    "${cargo[@]}" build --profile dist --locked --manifest-path "$ROOT/rust/Cargo.toml"
  )

  built="$ROOT/rust/target/dist/$lib"
  if [[ ! -f "$built" ]]; then
    echo "error: expected build output not found: $built" >&2
    exit 1
  fi
  store_deps="$(otool -L "$built" | awk 'NR > 1 && /\/nix\/store\//')"
  store_rpaths="$(otool -l "$built" | awk '
    $1 == "cmd" { rpath = ($2 == "LC_RPATH"); next }
    rpath && $1 == "path" && $2 ~ /^\/nix\/store\// { print "\tLC_RPATH " $2 }')"
  if [[ -n "$store_deps$store_rpaths" ]]; then
    {
      echo "error: $built links against or searches the nix store, which catalog users lack:"
      [[ -z "$store_deps" ]] || echo "$store_deps"
      [[ -z "$store_rpaths" ]] || echo "$store_rpaths"
      echo "build outside the nix dev shell, or with SDKROOT and MACOSX_DEPLOYMENT_TARGET unset"
    } >&2
    exit 1
  fi
  minos="$(otool -l "$built" | awk '
    $1 == "cmd" && $2 == "LC_BUILD_VERSION" { field = "minos"; next }
    $1 == "cmd" && $2 == "LC_VERSION_MIN_MACOSX" { field = "version"; next }
    $1 == "cmd" { field = ""; next }
    field != "" && $1 == field && minos == "" { minos = $2 }
    END { print minos }')"
  if [[ -z "$minos" ]]; then
    echo "error: $built has no LC_BUILD_VERSION or LC_VERSION_MIN_MACOSX" >&2
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

  # install_name_tool invalidates the linker's ad-hoc code signature, and on
  # Apple Silicon an unsigned/mismatched dylib is SIGKILL'd ("Killed: 9") the
  # moment Racket dlopen()s it.  Re-sign ad-hoc so the committed candidate loads.
  if command -v codesign >/dev/null 2>&1; then
    codesign -f -s - "$dest/$lib"
  fi

  # The system linker comes with the host's Xcode, which nothing here pins, and
  # nothing pins the minimum macOS either (MACOSX_DEPLOYMENT_TARGET, else
  # rustc's default for the target): it is recorded, not checked.
  {
    "${rustc[@]}" -vV
    echo "ld: $(ld -v 2>&1 | head -1)"
    echo "minos: $minos"
  } > "$dest/toolchain"
fi
echo ">> built by $(head -1 "$dest/toolchain")"

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
