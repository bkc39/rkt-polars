# rkt-polars

Racket bindings to [polars](https://pola.rs/).

The project now uses Nix as its primary build infrastructure:

- the Rust compatibility library lives in `rust/`
- Nix builds the shared library and the Racket package separately
- the Racket package loads `libcompat` from `polars/native-libs/`

## Build With Nix

Build the default Racket package environment:

```sh
nix build
```

Build the Rust compatibility library on its own:

```sh
nix build .#rust
```

Build the packaged Racket environment explicitly:

```sh
nix build .#racket
```

Run the full check set:

```sh
nix flake check
```

## Development Shell

Enter the pinned toolchain shell:

```sh
nix develop
```

On first entry, the shell:

- links the local `rkt-polars` package into `.racket-user/`
- copies `libcompat` into `polars/native-libs/`
- runs `raco setup` for the package

Typical commands inside the shell:

```sh
cargo test --manifest-path rust/Cargo.toml
cd rust && cargo build --release
cp target/release/libcompat.dylib ../polars/native-libs/
otool -D ../polars/native-libs/libcompat.dylib
cd ..
raco test -x -c polars
```

On macOS, the `otool -D` line should print `@rpath/libcompat.dylib`.

## Non-Nix `raco` Fallback

Populate `polars/native-libs/` from the Nix-built Rust library:

```sh
nix run .#copy-native-libs
```

After that, plain Racket commands work without invoking Cargo during install:

```sh
raco pkg install --name rkt-polars .
raco setup --pkgs rkt-polars
raco test -x -c polars
```

## Prebuilt Native Libraries (pkgs.rkt-lang.org)

The package catalog's build host has no Rust toolchain, so it cannot compile
`libcompat` at install time. To support it, prebuilt shared objects are
committed per platform under `polars/native-libs/candidates/`:

```
polars/native-libs/candidates/
├── linux/libcompat.so       # x86_64, built on Ubuntu 22.04 (glibc 2.35)
└── darwin/libcompat.dylib   # arm64
```

The linux candidate is built on Ubuntu 22.04 to match the glibc the
pkgs.rkt-lang.org build host runs, so it does not require a newer glibc than
that host provides.

The `pre-install-collection` hook (`polars/private/install-compat.rkt`) selects
a library at `raco pkg install` time, in priority order:

1. `RKT_POLARS_COMPAT_LIB_PATH` — copy from `$VAR/lib` (Nix build / dev shell).
2. the committed candidate for the current platform (catalog install).
3. an already-staged `polars/native-libs/libcompat.*`.

To (re)build and stage a candidate with the Rust toolchain — the cargo
analogue of a cmake build — run, on the matching platform:

```sh
scripts/build-so.sh            # auto-detects linux/darwin
scripts/build-so.sh darwin     # or name the platform explicitly
```

To reproduce the catalog install locally (no toolchain, no env override),
forcing the installer to copy from `candidates/`:

```sh
scripts/test-local.sh
```

CI (`.github/workflows/native.yml`) builds both candidates with cargo and runs
this catalog install on Linux and macOS.
