# Rebuilding the native `libcompat` candidates

`rkt-polars` calls a Rust shared library (`libcompat`) over the FFI. The build
host at **pkgs.racket-lang.org has no Rust toolchain**, so it does not compile
this library — instead it installs a *prebuilt, committed* per-platform binary
from `polars/native-libs/candidates/<platform>/` (see
`polars/private/install-compat.rkt`):

| Platform | Committed file | Installed on |
|----------|----------------|--------------|
| `darwin` | `candidates/darwin/libcompat.dylib` | macOS users |
| `linux`  | `candidates/linux/libcompat.so`     | **pkgs.racket-lang.org** + Linux users |

Because `define-compat` (in `polars/private/{foreign,expr-core}.rkt`) resolves
each C symbol **at module load**, a stale candidate that is missing a newly
added symbol makes `raco setup` fail on install — not just at call time. **Any
PR that adds or changes a `#[no_mangle] pub extern "C"` function in `rust/src`
must rebuild and re-commit both candidates**, or the catalog build breaks.

> Example: the `series_quantile` export (added for `describe`) requires both
> `candidates/darwin/libcompat.dylib` **and** `candidates/linux/libcompat.so`
> to be rebuilt. macOS can be done on a Mac; Linux must be done on Linux/Docker.

---

## macOS (`darwin`)

On any Mac with the Rust toolchain:

```sh
scripts/build-so.sh darwin
```

This runs `cargo build --release`, rewrites the dylib install-name to
`@rpath/libcompat.dylib`, and re-signs it ad-hoc (`codesign -f -s -`). The
re-sign is required: `install_name_tool` invalidates the linker's signature,
and on Apple Silicon an unsigned dylib is `Killed: 9` the instant Racket
`dlopen()`s it. The result is staged to `candidates/darwin/libcompat.dylib`.

---

## Linux (`linux`) — what the Linux agent must do

The Linux `.so` is what pkgs.racket-lang.org actually installs, and its
**build host runs an old glibc (< 2.27)**. The `.so` must therefore depend only
on `GLIBC <= 2.17`. We get that by building inside the **manylinux2014**
container (glibc 2.17) — building natively against an old glibc, *not* by
post-processing with `polyfill-glibc` (that corrupts the ELF and segfaults on
newer glibc).

### Steps

1. **Get a Linux host (x86_64) with Docker** (a CI runner, a cloud VM, or
   Docker Desktop). Docker is the only hard requirement; no local Rust needed —
   the container installs its own toolchain.

2. **Clone the branch under review** and run the Linux build target:

   ```sh
   git clone https://github.com/bkc39/rkt-polars.git
   cd rkt-polars
   git checkout <this-PR-branch>
   scripts/build-so.sh linux
   ```

   `scripts/build-so.sh linux` mounts the repo read-only into
   `quay.io/pypa/manylinux2014_x86_64`, installs rustup + stable inside, runs
   `cargo build --release --locked`, and copies the resulting
   `libcompat.so` out to `polars/native-libs/candidates/linux/`.

3. **Verify the build before committing:**

   ```sh
   so=polars/native-libs/candidates/linux/libcompat.so

   # (a) the new symbol(s) are present — adjust the grep per PR:
   nm -D "$so" | grep series_quantile        # must print a 'T series_quantile' line

   # (b) the glibc floor is <= 2.17 (must print nothing ABOVE 2.17):
   objdump -T "$so" | grep -oE 'GLIBC_[0-9]+\.[0-9]+' | sort -V -u | tail -1
   # expected: GLIBC_2.17 (or lower)
   ```

   If (b) shows anything higher than `2.17`, the build escaped the container —
   do **not** commit it; it will fail to load on the catalog host.

4. **Smoke-test the install path** (optional but recommended) on the same Linux
   host, against the freshly staged candidate:

   ```sh
   raco pkg install --auto --link $(pwd)     # runs the pre-installer, copies the candidate
   raco test polars/                          # should load libcompat and pass
   ```

5. **Commit and push the rebuilt candidate** onto the PR branch:

   ```sh
   git add polars/native-libs/candidates/linux/libcompat.so
   git commit -m "native: rebuild linux libcompat candidate (series_quantile)"
   git push
   ```

That's it — once `candidates/linux/libcompat.so` on the branch contains the new
symbol with a `GLIBC <= 2.17` floor, the catalog build at pkgs.racket-lang.org
will install and load it successfully.
