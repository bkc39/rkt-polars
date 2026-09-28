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

## What CI checks

- **Build libcompat (linux, darwin)** builds both from the pushed commit with
  `scripts/build-so.sh` and uploads them as the artifacts `libcompat-linux` and
  `libcompat-darwin`. The Linux build runs in the manylinux2014 container, so
  the `.so` needs only glibc ≤ 2.17 (the catalog's test host is older than
  2.27), and the job asserts that floor.
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

1. takes the push-event CI run for the PR's head commit (a `pull_request` run
   builds the merge with `master`, not the head) and refuses unless that
   commit's `rust/` is the checkout's;
2. waits for the run's Build libcompat jobs and downloads both artifacts to
   `~/rkt-polars-candidates/<run-id>/` (`--dir` to change);
3. stops if they already match the committed files: builds of the same Rust
   source and toolchain are byte-identical;
4. checks them with `scripts/verify-candidates.py` (an x86-64 ELF needing
   glibc ≤ 2.17, an arm64 Mach-O with a code signature, the same exports on
   both) and with `scripts/check-bindings.rkt` (every module under
   `polars/private` instantiates against this host's candidate, staged in
   place of the nix-built library);
5. copies them into `candidates/` and writes the commit message, which lists
   the exports added and removed.

## Building by hand

When CI is not available, `scripts/build-so.sh <platform>` builds one
candidate and stages it in `candidates/<platform>/`:

- **linux** needs Docker. It builds inside `quay.io/pypa/manylinux2014_x86_64`
  against glibc 2.17. Do not post-process a `.so` built against a newer glibc
  with `polyfill-glibc`: that corrupts the ELF and segfaults on newer glibc.
- **darwin** needs a Mac with the Rust toolchain. The script rewrites the
  install name to `@rpath/libcompat.dylib` and re-signs ad hoc:
  `install_name_tool` invalidates the linker's signature, and Apple Silicon
  kills an unsigned dylib (`Killed: 9`) the moment Racket `dlopen()`s it.

Check the pair with

```sh
python3 scripts/verify-candidates.py \
  polars/native-libs/candidates/linux/libcompat.so \
  polars/native-libs/candidates/darwin/libcompat.dylib
```

and reproduce the catalog install with `scripts/test-local.sh`, in a fresh
`PLTUSERHOME` as on a CI runner.
