<div align="center">

# rkt-polars

**Fast, multi-threaded DataFrames for Racket — [Polars](https://pola.rs/) with a prefix-free, threadable API.**

[![Native](https://github.com/bkc39/rkt-polars/actions/workflows/native.yml/badge.svg)](https://github.com/bkc39/rkt-polars/actions/workflows/native.yml)
[![Nix](https://github.com/bkc39/rkt-polars/actions/workflows/nix.yml/badge.svg)](https://github.com/bkc39/rkt-polars/actions/workflows/nix.yml)
[![Docs](https://img.shields.io/badge/docs-racket--lang.org-blue.svg)](https://docs.racket-lang.org/polars)
[![Package](https://img.shields.io/badge/raco%20pkg-polars-purple.svg)](https://pkgs.racket-lang.org/package/polars)
[![License](https://img.shields.io/badge/license-Apache--2.0%20OR%20MIT-blue.svg)](#license)

</div>

`rkt-polars` provides Racket bindings to [Polars](https://pola.rs/), the
blazingly fast DataFrame library written in Rust. It wraps the Polars engine
through a native compatibility layer and exposes it as an idiomatic Racket API.

The Polars engine:

- uses all available cores on your machine,
- optimizes lazy queries to cut unneeded work and allocations,
- handles datasets larger than your available RAM,
- and follows a consistent, schema-aware API.

On top of that engine, `rkt-polars` adds a Racket-native surface:

- **Prefix-free, data-first verbs** that thread cleanly with `~>` — a Polars
  pipeline reads top-to-bottom, mirroring the Python/Rust method chains.
- **Eager and lazy execution** — work with a `dataframe` directly, or build a
  `lazy` query plan and run it with `collect`.
- **Expressions** over columns (`col`), with the `.str` / `.dt` namespaces,
  null/NaN handling, cumulative ops, ranking, and `when`/`then`/`otherwise`.
- **Temporal values as [gregor](https://docs.racket-lang.org/gregor/) dates and
  datetimes** on the Racket side.

For the full API, see the [reference documentation](https://docs.racket-lang.org/polars)
and the runnable scripts in [`examples/`](examples/).

## Install

```sh
raco pkg install polars
```

The package ships prebuilt native libraries for Linux (x86_64) and macOS
(arm64), so no Rust toolchain is needed to install. Then:

```racket
(require polars)
```

## Usage

A quick taste — build a DataFrame and derive columns with expressions that
thread with `~>`:

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
The engine optimizes the whole plan before running it:

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

### Build with Nix

```sh
nix build              # the default Racket package environment
nix build .#rust       # just the Rust compatibility library
nix build .#racket     # the packaged Racket environment
nix flake check        # the full check set
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
cd rust && cargo build --release
cp target/release/libcompat.dylib ../polars/native-libs/   # macOS
cd .. && raco test -x -c polars
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
raco test -x -c polars
```

### Prebuilt native libraries

The package catalog's build host has no Rust toolchain, so prebuilt shared
objects are committed per platform under `polars/native-libs/candidates/`
(`linux/libcompat.so`, built on glibc 2.17 / manylinux2014, and
`darwin/libcompat.dylib` for arm64). The `pre-install-collection` hook
(`polars/private/install-compat.rkt`) selects a library at `raco pkg install`
time, preferring `RKT_POLARS_COMPAT_LIB_PATH`, then the committed candidate for
the platform, then an already-staged `polars/native-libs/libcompat.*`.

To (re)build and stage a candidate on the matching platform:

```sh
scripts/build-so.sh            # auto-detects linux/darwin
scripts/build-so.sh darwin     # or name the platform explicitly
```

To reproduce a catalog install locally (no toolchain, no env override):

```sh
scripts/test-local.sh
```

CI (`.github/workflows/native.yml`) builds both candidates with cargo and runs
the catalog install on Linux and macOS.

## License

Licensed under either the Apache License 2.0 or the [MIT License](LICENSE-MIT)
at your option.
