<div align="center">

<h1>
  <img src="docs/assets/rkt-polars-logo.png" alt="" height="93" align="middle">&nbsp;&nbsp;&nbsp;rkt-polars&nbsp;&nbsp;&nbsp;<img src="docs/assets/header-spacer.png" alt="" height="93" align="middle">
</h1>

**Fast, multi-threaded DataFrames for Racket — [Polars](https://pola.rs/)**

[![Build](https://img.shields.io/github/actions/workflow/status/bkc39/rkt-polars/ci.yml?label=build)](https://github.com/bkc39/rkt-polars/actions/workflows/ci.yml)
[![Docs](https://img.shields.io/badge/docs-racket--lang.org-blue.svg)](https://docs.racket-lang.org/polars)
[![Package](https://img.shields.io/badge/raco%20pkg-polars-purple.svg)](https://pkgs.racket-lang.org/package/polars)
[![License](https://img.shields.io/badge/license-Apache--2.0%20OR%20MIT-blue.svg)](#license)

</div>

`rkt-polars` provides Racket bindings to [Polars](https://pola.rs/), the
blazingly fast DataFrame library written in Rust. This package supports both Linux and macOS.

For the full API, see the [reference documentation](https://docs.racket-lang.org/polars)
and the runnable scripts in [`examples/`](examples/).

## Install

To install run:

```sh
raco pkg install polars
```

On x86-64 Linux, arm64 Linux and arm64 macOS this also installs the native
package that holds `libcompat`, `polars-x86_64-linux`, `polars-aarch64-linux`
or `polars-aarch64-macosx`, so no Rust toolchain is needed. Then

```racket
(require polars)
```

## Usage

Here is a brief example:

```racket
#lang racket/base
(require polars)

(define df
  (dataframe (list (series '(1 2 3 4)     #:name "x" #:dtype 'i64)
                   (series '(10 20 30 40) #:name "y" #:dtype 'i64))))

(~> df
    (with-columns (~> (col "x") (* (col "y")) (alias "x_times_y"))
                  (~> (col "y") sqrt          (alias "sqrt_y"))))
```

```text
shape: (4, 4)
┌─────┬─────┬───────────┬──────────┐
│ x   ┆ y   ┆ x_times_y ┆ sqrt_y   │
│ --- ┆ --- ┆ ---       ┆ ---      │
│ i64 ┆ i64 ┆ i64       ┆ f64      │
╞═════╪═════╪═══════════╪══════════╡
│ 1   ┆ 10  ┆ 10        ┆ 3.162278 │
│ 2   ┆ 20  ┆ 40        ┆ 4.472136 │
│ 3   ┆ 30  ┆ 90        ┆ 5.477226 │
│ 4   ┆ 40  ┆ 160       ┆ 6.324555 │
└─────┴─────┴───────────┴──────────┘
```

### Lazy queries

Build a query plan with `lazy`, chain the verbs, and execute it with `collect`.

```racket
#lang racket/base
(require polars)

(define df
  (dataframe
   (list (series '("setosa" "setosa" "versicolor" "versicolor" "virginica" "virginica")
                 #:name "species")
         (series '(5.1 4.9 7.0 6.4 6.3 5.8) #:name "sepal_length")
         (series '(1.4 1.4 4.7 4.5 6.0 5.1) #:name "petal_length"))))

(~> df
    lazy
    (filter (> (col "sepal_length") 5.0))
    (group-by "species")
    (agg (~> (col "sepal_length") sum  (alias "total_sepal"))
         (~> (col "petal_length") mean (alias "avg_petal")))
    (sort "species")
    collect)
```

```text
shape: (3, 3)
┌────────────┬─────────────┬───────────┐
│ species    ┆ total_sepal ┆ avg_petal │
│ ---        ┆ ---         ┆ ---       │
│ str        ┆ f64         ┆ f64       │
╞════════════╪═════════════╪═══════════╡
│ setosa     ┆ 5.1         ┆ 1.4       │
│ versicolor ┆ 13.4        ┆ 4.6       │
│ virginica  ┆ 12.1        ┆ 5.55      │
└────────────┴─────────────┴───────────┘
```

You can also start a lazy plan straight from a file with `scan-csv` /
`scan-parquet`, and read or write eagerly with `read-csv` / `write-csv`,
`read-parquet` / `write-parquet`, and `read-ndjson` / `write-ndjson`. See
[`examples/`](examples/) for end-to-end scripts covering joins, string and
datetime operations, window functions, and more.

## Development

This project uses [Nix](https://nixos.org/) as its primary build
infrastructure. The Rust compatibility library lives in `rust/`; Nix builds the
shared library and the Racket package separately, and the Racket package loads
`libcompat` from `polars/native-libs/`.

The pinned toolchain is **Racket 9.3**. `flake.nix` takes Racket from
`nixpkgs-unstable` rather than a version input, so the `racket-version` check
asserts the floor explicitly — `nix flake check` fails if a `flake.lock` bump
ever moves Racket below it. The Release build workflow installs the native
packages on Racket 9.3 and on `stable`, on Linux and macOS.

### Build with Nix

```sh
nix build              # the default Racket package environment
nix build .#rust       # just the Rust compatibility library
nix build .#racket     # the packaged Racket environment
nix flake check        # the full check set (incl. rustfmt + racket-version)
nix fmt                # format the flake with nixfmt-rfc-style
```

### Development shell

Enter the pinned toolchain shell:

```sh
nix develop
```

On first entry, the shell links the local `rkt-polars` package into
`.racket-user/`, copies `libcompat` into `polars/native-libs/`, and runs `raco
setup`. Typical commands inside the shell:

```sh
cargo test --manifest-path rust/Cargo.toml
cargo fmt --manifest-path rust/Cargo.toml --check          # same check as CI
cd rust && cargo build --release
cp target/release/libcompat.dylib ../polars/native-libs/   # macOS
cd .. && raco test -e --timeout 600 -c polars
raco test -e user-guide                                    # the guide's scripts
raco test -e -Q --empty-stdin -j 8 examples                # every numbered example
```

On macOS, `otool -D polars/native-libs/libcompat.dylib` should print
`@rpath/libcompat.dylib`.

### Non-Nix `raco` fallback

Populate `polars/native-libs/` from the Nix-built Rust library, then use plain
Racket commands (no Cargo at install time):

```sh
nix run .#copy-native-libs
raco pkg install --name rkt-polars .
raco setup --pkgs rkt-polars
raco test -e --timeout 600 -c polars
```

### Native packages

`polars` loads `libcompat` from the native package for the platform,
`polars-x86_64-linux`, `polars-aarch64-linux` or `polars-aarch64-macosx`,
which `polars/info.rkt`
depends on by `#:platform`; `RKT_POLARS_COMPAT_LIB_PATH` or a dev-built
staged copy outranks it. `polars/native-libs/BUILDING.md` (Native packages)
has the load order, the package's layout and manifest, and
`scripts/stage-native-package.rkt`, which assembles one.

No binary is committed: a tag `v<native-version>` builds the three libraries
and drafts the GitHub Release that holds their packages, and developers load the
dev shell's staged copy or set the variable.

To build the shipped library on the matching platform (Linux needs Docker,
and builds for Docker's machine, x86_64 or aarch64), into
`rust/target/libcompat/<platform>/`:

```sh
scripts/build-so.sh            # auto-detects linux/darwin
scripts/build-so.sh darwin     # or name the platform explicitly
```

To reproduce a catalog install locally from a built library (no toolchain, no
env override), in a fresh `PLTUSERHOME`:

```sh
scripts/test-local.sh rust/target/libcompat/linux/libcompat.so
scripts/test-local.sh polars/native-libs/libcompat.so      # the dev shell's copy
```

The Release build workflow (`.github/workflows/release.yml`) builds the
libraries on a PR that touches `rust/` or the release's inputs, gates,
packages and installs them, and installs them as the package server does.
They are built by rustup's build of the flake's rustc release, which
`rust/rust-toolchain.toml` pins; its LLVM can differ from nixpkgs', so
`nix flake check` does not cover the shipped code generation; those install
jobs do. `polars/native-libs/BUILDING.md` has the jobs and the release
checklist.

## License

Licensed under either the [Apache License 2.0](LICENSE-APACHE) or the
[MIT License](LICENSE-MIT) at your option.
