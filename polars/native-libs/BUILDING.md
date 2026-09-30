# The committed `libcompat` candidates

`rkt-polars` calls a Rust shared library, `libcompat`, over the FFI. The build
host at **pkgs.racket-lang.org has no Rust toolchain**, so the package ships a
prebuilt binary per platform, and the pre-installer
(`polars/private/install-compat.rkt`) copies it into place:

| Platform | Committed file | Installed on |
|----------|----------------|--------------|
| `linux`  | `candidates/linux/libcompat.so`     | **pkgs.racket-lang.org** + Linux x86-64 users |
| `darwin` | `candidates/darwin/libcompat.dylib` | macOS arm64 users |

`define-compat` resolves each C symbol **at module load**, so a candidate that
lacks an export the Racket side binds makes `raco setup` fail for every catalog
user, not just the call. **A PR that adds or changes a `#[no_mangle] pub extern
"C"` function in `rust/src` needs both candidates refreshed before it merges.**
Any other Rust change reaches catalog users only once they are refreshed.

## The toolchain

The candidates are built by the rustc the tests run on:

- `rust/rust-toolchain.toml` pins the release rustc. `scripts/build-so.sh`
  builds with it, and the `release-toolchain` flake check fails when it is not
  nixpkgs' rustc at `flake.lock`, which builds and tests the library in
  `nix flake check` and the dev shell. rustup also picks it for `cargo` run in
  `rust/`. The release and commit match, but rustup's build of a release
  carries its own LLVM, which can differ from nixpkgs' (22.1.8 against 21.1.8
  for 1.98.1); the CI jobs that install the built candidates and run the tests
  are what cover the shipped code.
- `scripts/build-so.sh` names the manylinux2014 image, which supplies the
  Linux candidate's linker and glibc, by digest. The darwin linker is the CI
  runner's Xcode, which nothing pins.
- Each build writes `toolchain` beside the library: the `rustc -vV` that built
  it, and the image (Linux) or the linker (darwin). CI uploads it in the
  artifact with `rust-tree`.

The same rustc release, `rust/` and image give byte-identical candidates.

## What CI checks

- **Build libcompat (linux, darwin)** builds both from the pushed commit with
  `scripts/build-so.sh` and uploads them as the artifacts `libcompat-linux` and
  `libcompat-darwin`. The Linux build runs in the manylinux2014 container, so
  the `.so` needs only glibc ≤ 2.17 (the catalog's test host is older than
  2.27), and the job asserts that floor.
- **Old-glibc load test** `dlopen`s the Linux artifact in the image that built
  it.
- **Catalog install** installs those fresh artifacts the way the catalog does,
  then builds the docs and runs the tests.
- **Committed candidate (linux, darwin)** does the same with the **committed**
  binaries (`scripts/test-local.sh`, which first instantiates every module
  under `polars/private` with `scripts/check-bindings.rkt`). The Linux job also
  checks both committed files with `scripts/verify-candidates.py`. It is red on
  a PR that adds an export, or whose tests need its new Rust behaviour, without
  refreshing the candidates, and its error says what to run. It cannot see a
  Rust change that no test exercises.

## Refreshing the candidates from CI

On a checkout of the PR branch:

```sh
scripts/refresh-candidates.sh <PR>            # or: --run <run-id>
git add polars/native-libs/candidates
git commit -F ~/rkt-polars-candidates/<run-id>/commit-msg.txt
git push
```

The script re-runs itself inside `nix develop`, then:

1. takes the CI run for the PR's head commit (its `pull_request` run, which
   builds the merge with `master`);
2. waits for the run's Build libcompat jobs and downloads both artifacts to
   `~/rkt-polars-candidates/<run-id>/` (`--dir` to change);
3. refuses unless the `rust/` tree each build recorded is the checkout's, and
   prints the toolchain each recorded, refusing a rustc release other than the
   dev shell's (the flake's);
4. stops if they already match the committed files: builds of the same Rust
   source and toolchain are byte-identical;
5. checks them with `scripts/verify-candidates.py` (an x86-64 ELF needing
   glibc ≤ 2.17, an arm64 Mach-O with a code signature, the same exports on
   both) and with `scripts/check-bindings.rkt` (every module under
   `polars/private` instantiates against this host's candidate, staged in
   place of the nix-built library);
6. copies them into `candidates/` and writes the commit message, which lists
   the toolchains and the exports added and removed.

## Refreshing the toolchain

About every six weeks, once a new stable rustc has reached nixpkgs-unstable
(sooner for a polars patch release with a fix the package wants), refresh the
toolchain in a PR of its own. On a branch off `master`, from a quiet host:

```sh
scripts/refresh-toolchain.sh                  # --no-bench to skip the bench
```

It benches the tree (`nix run .#bench`), then:

1. runs `nix flake update` and sets `rust/rust-toolchain.toml` to the new
   nixpkgs' rustc;
2. moves `scripts/build-so.sh`'s image to the digest quay.io lists for
   `manylinux2014_x86_64:latest`, with the dated tag that shares it;
3. runs `cargo update`, the newest semver-compatible crates: polars stays on
   its minor, which `rust/Cargo.toml` fixes;
4. rebuilds `racket-deps`, whose pinned hash a store that already holds it
   never checks, and runs `nix flake check`;
5. benches the result, and writes the commit message and a PR body (the
   versions before and after, the `cargo update` log, both bench tables) under
   `~/rkt-polars-toolchain/<time>/` (`--dir` to change).

Commit, push and open the PR as it prints; once the PR's CI has built both
candidates, refresh them with `scripts/refresh-candidates.sh <PR>`.

When a step fails, nothing is committed. A new `racket-deps` hash goes in
`outputHash` in `flake.nix` (nix prints it). A build that fails on the new
rustc (polars' `nightly` feature tracks `std::simd`) becomes an issue, and the
refresh waits for it. A new polars minor (0.55 → 0.56) breaks API and is a leg
of its own, not a refresh.

To move only the image, set `MANYLINUX_IMAGE` in `scripts/build-so.sh` to
`quay.io/pypa/manylinux2014_x86_64:<tag>@<digest>`, a dated tag and its digest
from [quay.io's tag list](https://quay.io/repository/pypa/manylinux2014_x86_64?tab=tags).
A new image can change the Linux candidate's bytes; refresh the candidates
from that PR's run.

## Building by hand

When CI is not available, `scripts/build-so.sh <platform>` builds one
candidate and stages it, with its `toolchain` record, in
`candidates/<platform>/`:

- **linux** needs Docker. It builds inside the pinned manylinux2014 image
  against glibc 2.17. Do not post-process a `.so` built against a newer glibc
  with `polyfill-glibc`: that corrupts the ELF and segfaults on newer glibc.
- **darwin** needs a Mac with rustup, from which the script installs the
  pinned rustc, or with that rustc on `PATH`. The script rewrites the install
  name to `@rpath/libcompat.dylib` and re-signs ad hoc: `install_name_tool`
  invalidates the linker's signature, and Apple Silicon kills an unsigned
  dylib (`Killed: 9`) the moment Racket `dlopen()`s it.

Check the pair with

```sh
python3 scripts/verify-candidates.py \
  polars/native-libs/candidates/linux/libcompat.so \
  polars/native-libs/candidates/darwin/libcompat.dylib
```

and reproduce the catalog install with `scripts/test-local.sh`, in a fresh
`PLTUSERHOME` as on a CI runner.
