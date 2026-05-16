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
