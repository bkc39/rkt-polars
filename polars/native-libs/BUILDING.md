# The committed `libcompat` candidates

`polars` loads `libcompat` from the native package for its platform,
`polars-x86_64-linux` or `polars-aarch64-macosx` (#254), which a release
builds (see [Native packages](#native-packages)). The candidates below stay
until #254's L3 removes them: the pre-installer stages one only where no
native package is installed, and only on the platform it was built for.

`rkt-polars` calls a Rust shared library, `libcompat`, over the FFI. The build
host at **pkgs.racket-lang.org has no Rust toolchain**, so the package ships a
prebuilt binary per platform, and the pre-installer
(`polars/private/install-compat.rkt`) copies it into place. It leaves an
identical library alone and replaces a differing one by a rename, as
`scripts/install-native-libs.sh` does (#267). It keeps a library that
script installed, which it marks with `.libcompat.*.dev` beside it, until
`RKT_POLARS_FORCE_CANDIDATE=1` or the dev shell installs another (#306):

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

The candidates are built by the same rustc release as the tests run on, but
not the same build of it:

- `rust/rust-toolchain.toml` pins the release rustc. `scripts/build-so.sh`
  builds with it, and the `release-toolchain` flake check fails when it is not
  the release of nixpkgs' rustc at `flake.lock`, which builds and tests the
  library in `nix flake check` and the dev shell. rustup also picks it for
  `cargo` run in `rust/`. The release and commit match, but rustup's build of
  a release carries its own LLVM, which can differ from nixpkgs' (22.1.8
  against 21.1.8 for 1.98.1), so `nix flake check` does not cover the shipped
  code generation. The CI jobs that install the built candidates and run the
  tests do.
- `scripts/build-so.sh` names the manylinux2014 image, which supplies the
  Linux candidate's linker and glibc, by digest. The darwin linker is the CI
  runner's Xcode, which nothing pins.
- Each build writes `toolchain` beside the library: the `rustc -vV` that built
  it, and the image (Linux) or the linker (darwin). CI uploads it in the
  artifact with `rust-tree`.

The same rustc release, `rust/` and image give a byte-identical Linux
candidate: a build on another host in the pinned image matched CI's. The
darwin candidate also depends on the runner's Xcode, which nothing pins: CI
runs on one runner image have matched, but a runner update can change its
bytes.

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
  Rust change that no test exercises. A stack refreshes the candidates once,
  on its top PR, so on a PR that another open PR is stacked on (one whose
  base is its branch) a failed install or test is a warning naming the PR
  above, and Catalog install still tests that PR's own build. The top and
  `master` stay strict, and the stack lands in one merge on the top.

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
3. refuses unless each build recorded its `rust/` tree and toolchain, the tree
   is the checkout's, the rustc release is the dev shell's (the flake's), and
   the Linux image is the one the checkout's `scripts/build-so.sh` names (the
   script lies outside `rust/`, so the tree check misses an image change); it
   prints each toolchain;
4. stops if they already match the committed files (see "The toolchain" for
   when builds are byte-identical);
5. checks them with `scripts/verify-candidates.py` (an x86-64 ELF needing
   glibc ≤ 2.17, an arm64 Mach-O with a code signature, the same exports on
   both) and with `scripts/check-bindings.rkt` (every module under
   `polars/private` instantiates against this host's candidate, staged in
   place of the nix-built library);
6. copies them into `candidates/` and writes the commit message, which lists
   the toolchains and the exports added and removed.

A run from before the toolchain record (#138) records none and is refused, so
a PR opened before #138 merged must merge `master`, push, and wait for the new
CI run before its next refresh.

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
3. runs `cargo update`, the newest semver-compatible crates: polars stays
   at the fork's rev, which `rust/Cargo.toml` fixes, so a polars patch
   release is a new fork branch (see below);
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
from that PR's run (`scripts/refresh-candidates.sh` refuses an older run,
built in the old image).

## The polars fork

Every polars crate comes from the branch `rkt-polars/0.55.2` of
[bkc39/polars](https://github.com/bkc39/polars/tree/rkt-polars/0.55.2)
(#362). `rust/Cargo.toml` takes `polars`, `polars-async`, `polars-buffer`
and `polars-core` from it by `git` and the same `rev`, a full commit hash,
so cargo resolves the rest of the workspace from that commit and no polars
crate from crates.io (`polars-arrow-format` and `polars-parquet-format` are
published on their own and stay there). The branch starts at upstream's
`0.55.2` commit (d7488c7). Its first commit makes
`crates/polars-io/src/cloud/options.rs` the crates.io release's: that
release was published from a dirty tree that leaves out the caching DNS
resolver and the CRC64NVME checksum, which need the object_store fork
polars' workspace patches in, and a workspace's patches do not reach its
git dependents. Each later commit is one change, named by the rkt-polars
issue it fixes.

To change a crate, commit on the branch, push it, and move every `rev` in
`rust/Cargo.toml` to the new tip; `cargo fetch` rewrites `rust/Cargo.lock`.
The nix build fetches the commit with `fetchgit`, so `flake.nix`'s
`outputHashes."polars-0.55.2"`, the NAR hash of the commit's tree, moves
with it: `git archive <rev> | tar -x -C <dir>` and `nix hash path <dir>`
print it, and a stale one fails the build with the hash it got. The
`polars-fork` flake check fails when a direct polars dependency is not the
fork at the one rev, when `rust/Cargo.toml` has a `[patch]` table, or when
`rust/Cargo.lock` takes a polars crate from anywhere else.

cargo fetches the fork with its history (about 160 MB) once per
`CARGO_HOME`, so `scripts/build-so.sh`'s Docker build downloads it each
time; `fetchgit` takes the one commit. A polars bump starts a new branch, as
`AGENTS.md`'s toolchain rule says.

## Building by hand

When CI is not available, `scripts/build-so.sh <platform>` builds one
candidate and stages it, with its `toolchain` record, in
`candidates/<platform>/`:

- **linux** needs Docker. It builds inside the pinned manylinux2014 image
  against glibc 2.17. Do not post-process a `.so` built against a newer glibc
  with `polyfill-glibc`: that corrupts the ELF and segfaults on newer glibc.
- **darwin** needs a Mac with rustup, from which the script installs the
  pinned rustc and builds with `rustup run <channel> cargo`, whatever `cargo`
  is first on `PATH` (nix's, in the dev shell). Without rustup, the rustc on
  `PATH` must be that release. cargo runs without the nix cc wrapper's
  flag variables (every `NIX_LDFLAGS*` and `NIX_CFLAGS*`), and the script
  refuses a dylib that `otool -L` shows linked against `/nix/store` or
  `otool -l` shows with an `LC_RPATH` there; build outside the dev shell if
  it does. The `toolchain` record names the dylib's minimum macOS
  (`minos`), which nothing pins. `scripts/test-build-so.sh` checks all of
  this against fakes (the `build-so-darwin` flake check, under nixpkgs'
  bash); `BASH_UNDER_TEST=/bin/bash` runs it under macOS's bash 3.2,
  which nixpkgs lacks. The script
  rewrites the install name to
  `@rpath/libcompat.dylib` and re-signs ad hoc: `install_name_tool`
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

## Native packages

`polars/private/native-library.rkt` loads `libcompat` from the first of:

1. `$RKT_POLARS_COMPAT_LIB_PATH/lib`, when the variable is set and not empty;
2. a staged `polars/native-libs/libcompat.*`, unless a native package holding
   a library is installed and the staged copy has no dev marker matching it
   (`.libcompat.*.dev`, which `nix run .#copy-native-libs` and the dev shell
   write), so a staged committed candidate never shadows the package;
3. the native package for the platform, found with `collection-file-path`
   and `dynamic-require`. Its version must equal `native-version` in
   `polars/info.rkt`, which the loader reads when it is compiled.

A native package is its skeleton, `native/polars-<platform>/` (`info.rkt`
and `main.rkt`, no binary; under `native/` so the repo root's `'multi`
package does not make it a collection), plus the licences, the library in
`native-libs/` and a `manifest.json`: the native version, the `rust/` tree
and commit the library was built from, and each `libcompat.*`'s sha256.

    racket scripts/stage-native-package.rkt [--rust-tree TREE --commit SHA | --head] \
      [--notices FILE] PLATFORM LIBCOMPAT OUT-DIR

assembles one for `x86_64-linux` or `aarch64-macosx` in `OUT-DIR`, which
must not exist. The tree and commit are `--rust-tree` and `--commit`, or else
the `rust-tree` and `commit` files CI's build records beside the library, or
else, given `--head`, this checkout's `HEAD`, which it refuses while `rust/`
differs from `HEAD`. With none of these it fails. `--notices` ships FILE
as `THIRD-PARTY-NOTICES.txt`, which a release does. The script requires
`polars/private/native-location` by collection, so run it where `polars` is
installed or linked, or with `racket -S <repo>` (`scripts/test-local.sh`
does). `scripts/stage-native-package-test.sh` (the `stage-native-package`
gate, and a step of CI's Lint job) holds it there.

The pre-installer (`polars/private/install-compat.rkt`) fails `raco setup` on
a native package whose version, manifest version or library hashes do not
match, and checks nothing under the variable or a dev-marked staged copy. It
runs only when `polars` is set up: `raco pkg install` or `raco pkg update` of
the native package alone does not run it, and the loader then checks the
version alone.

`scripts/test-local.sh` (the `Catalog install` and `Committed candidate`
jobs) stages the candidate as the native package, puts it in a `file://`
catalog with a copy of the configured ones, installs `polars` from that
catalog with `--auto`, so a `#:platform` string that does not match leaves
the package out, and then `scripts/check-native-install.rkt` requires that
`polars` loads the package's library and staged no candidate.

## Releases

`.github/workflows/release.yml` (the `Release build` workflow) runs on a tag
`v*`, on demand, and on a PR that touches `rust/`, `native/`,
`polars/info.rkt`, `scripts/release/`, `scripts/build-so.sh` or
`scripts/stage-native-package.rkt`. A PR run checks out the PR's head, not
the merge with its base, so the manifest names a commit that outlives the
run. Its jobs:

1. **plan**: `scripts/release/draft-tag.sh` fails unless both
   `native/*/info.rkt` versions equal `native-version`, and drafts only for a
   tag `v<native-version>`; a tag `v<version>` that differs drafts nothing,
   and any other tag fails.
2. **notices**: `scripts/release/notices.sh` runs cargo-about, at
   `flake.lock`'s nixpkgs, over `rust/Cargo.lock` into
   `THIRD-PARTY-NOTICES.txt` (`about.toml` lists the accepted licences,
   `about.hbs` the layout). It needs nix and the network for the crates'
   sources, so CI runs it; it builds nothing.
3. **build**: `scripts/build-so.sh` on each platform, as above, with cargo's
   home remapped to `/cargo` in the panic locations (#32), and the `rust/`
   tree and commit recorded beside the library.
4. **package**, per platform, on official Racket 9.3:
   - `scripts/release/gates.sh PLATFORM LIBRARY` checks the file type and
     architecture (and the code signature on macOS); no RPATH or RUNPATH but
     `$ORIGIN` (no `LC_RPATH` but `@loader_path`, and the install name
     `@rpath/libcompat.dylib`); no `/nix/store` path and no `/home`,
     `/Users` or `/root` one; glibc ≤ 2.17 (Linux); the NEEDED or
     `LC_LOAD_DYLIB` allow-list in `scripts/release/pins.sh`; a size under
     GitHub's 104,857,600-byte file limit, with a warning within 5 MiB of
     it; and every binding exported (`scripts/check-bindings.rkt` against the
     library, so only on its own platform).
     `scripts/release/gates-test.sh LIBCOMPAT` (the `release-gates` gate, a
     push gate and a step of CI's Lint job, and a step here on each
     platform) plants a library for each refusal and checks `draft-tag.sh`
     and `package.sh`.
   - `scripts/release/package.sh PLATFORM ARTIFACT NOTICES DIST` stages the
     native package with the notices, refuses a manifest whose `rust_tree`
     is not the checkout's `HEAD:rust`, and writes `polars-<platform>.zip`
     and its `.CHECKSUM`, the catalog entry `polars-<platform>.rktd` (its
     source is the Release's zip), `polars-<platform>.manifest.json`,
     `polars-<platform>.SHA256SUMS` and the notices.
   - `scripts/release/catalog-test.sh PLATFORM DIST [--full]` installs
     `polars` from a `file://` catalog holding the zip, in front of the 9.3
     release catalog and pkgs.racket-lang.org, and checks that `polars`
     loads the package's library, filters a frame and instantiates every
     module. On macOS, which has no pkg-build test, `--full` also renders
     the docs and runs the suite.
5. **pkg-build** (Linux): `scripts/release/pkg-build-test.sh DIST` installs
   `polars` with docs in pkg-build's image (`racket/pkg-build:deps-x86_64`,
   Debian buster, glibc 2.28, by digest) with racket-lang.org's natipkg
   installer, as root, with `PLT_PKG_BUILD_SERVICE=1`, `CI=true` and
   `PLT_INFO_ALLOW_VARS=;PLT_PKG_BUILD_SERVICE`, from such a catalog, so
   the `x86_64-linux-natipkg` dependency must pull `polars-x86_64-linux`,
   and requires the rendered manual. It then runs `raco test --jobs 2
   --drdr --package polars` with `--network none`. `RELEASE_LOGS` names a
   directory for the install and test logs.
6. **draft** (a tag `v<native-version>` only): `gh release create --draft
   --verify-tag` with every file the package jobs wrote. Only this job may
   write to the repository.

### Release checklist

A native release, when `rust/` or a native package changed:

1. On `master`, set `native-version` in `polars/info.rkt` and `version` in
   both `native/*/info.rkt` to the new version, and usually `polars`'
   `version` too.
2. Tag that commit `v<native-version>` and push the tag.
3. Read the draft the run makes: each manifest's `rust_tree` is the tag's
   `rust/` tree (`git rev-parse v<native-version>:rust`), each
   `.SHA256SUMS` checks, and the notices are attached.
4. Publish the draft.
5. On pkgs.racket-lang.org, register (the first time) or update
   `polars-x86_64-linux` and `polars-aarch64-macosx` with the source
   `https://github.com/bkc39/rkt-polars/releases/download/v<native-version>/polars-<platform>.zip`;
   `polars-<platform>.rktd` holds the entry, the checksum included.
6. Set `polars`' source to
   `https://github.com/bkc39/rkt-polars.git?path=polars#v<version>`.
7. After pkg-build's next cycle, check that polars' docs rendered and its
   tests passed there.

A Racket-only release bumps `polars`' `version` alone and tags
`v<version>`: its run builds, gates and tests both packages but drafts
nothing, and the catalog's `polars` source moves to the new tag (step 6).

The scripts run locally on any library, with no Rust build:
`scripts/release/gates.sh x86_64-linux polars/native-libs/candidates/linux/libcompat.so`
gates the committed candidate (which fails `home-paths` on its
`/root/.cargo` paths, from before the remap); `package.sh` takes a
directory holding a library, `rust-tree` and `commit`; and
`pkg-build-test.sh` needs Docker.
