# AGENTS.md

## Project overview

`polars` is a Racket binding to the [Polars](https://pola.rs) DataFrame
library. Racket calls a Rust `cdylib`, `libcompat` (`rust/`, polars crate
**0.55.2**), through `ffi/unsafe`; prebuilt shared objects for Linux x86-64 and
macOS arm64 ship with the package, so users need no Rust toolchain. The
`dtype-decimal` feature is on because polars' `sign` does not compile
without it (#106); Decimal columns are read (from Parquet), not built.
`dtype-categorical` carries Categorical and Enum. polars' `nightly` feature is on,
as in Python polars' own wheels: its `std::simd` code carries the CSV reader
(a stable build scans nycflights at 2.5× Python). It compiles on the pinned
stable rustc (1.98.1, nixpkgs at `flake.lock`) with `RUSTC_BOOTSTRAP=1`, which
the flake's build and dev shell and `scripts/build-so.sh` set; the release
build uses that same rustc version. The committed candidates are built with
`[profile.dist]` in `rust/Cargo.toml`: release plus thin LTO and one codegen
unit (#125), which keeps the Linux `.so` at 81.4 MB against GitHub's
104,857,600-byte file limit (102.2 MB without it). Only `scripts/build-so.sh`
uses it. The nix build, `cargo test` and the bench stay on `release`, because
under LTO every test and example binary links on one core (the nix check went
from 30 to 145 minutes on CI), so the bench measures the release build, not
the shipped one. `panic` stays `unwind`: `guard_panic` depends on it.

The published package is the **`polars/` subdirectory** (the catalog source is
this repo with `?path=polars`). Package metadata lives in `polars/info.rkt`,
not the repo root, and anything the docs need at build time (fixtures, helper
modules) must live under `polars/` or the catalog's doc build cannot see it.

The manual (`polars/scribblings/`) is published at
docs.racket-lang.org/polars. The package build server rebuilds it from
`master` on its own cycle, roughly daily, not on each merge.

## The three layers

1. **Raw FFI** — `polars/private/foreign.rkt` (series, dataframe, IO),
   `expr-core.rkt` / `expr.rkt` / `expr-str.rkt` / `expr-dt.rkt` (expressions,
   lazyframes), `bulk.rkt` (column copies into Racket-allocated buffers,
   whole or a block of rows at a time, behind `series->list`,
   `in-dataframe-rows` and their siblings). `define-compat` binds a
   C symbol; the Racket name is the symbol with `_` → `-`, or an explicit
   `#:c-id`. Bindings whose Racket name carries a `/raw` or `/c` suffix are
   wrapped by a checking function of the plain name.
2. **Monomorphic** — `series-sum-i32`, `dataframe-select-exprs`, `expr-gt`,
   `expr-str->date`: one binding per operation and dtype, documented in the
   reference's low-level sections. Not the surface users write.
3. **Generic / fluent** — `polars/private/generic/*.rkt`, aggregated by
   `generic.rkt`, re-exported by `main.rkt`. This is the surface: `series` and
   `dataframe` wrapper structs with `prop:custom-write`, and verbs that
   dispatch at runtime on series / dataframe / expression / plain value. The
   operators `+ - * / > < >= <= = and or not xor when abs round floor sqrt exp
   log filter sort min max first last reverse` **shadow `racket/base`** and fall
   back to it on plain values. `~>` from `threading` is re-provided so
   `(require polars)` is enough.

A pipeline reads as `(~> df (filter (> (col "v") 15)) (group-by "g") (agg (sum "v")))`.
Every fluent verb takes the frame — or the expression — as its **first**
argument so it threads; a bare column-name string is accepted wherever an
expression is and is lifted with `col`.

### Adding a fluent verb

Imitate the neighbouring module in `polars/private/generic/`. `->col-expr`
(in `generic/expr-util.rkt`) does the name-or-expression lift; `define-expr-unop`
and `define-math-unop` generate the two common unary shapes. A new name is
added to **both** the module's `provide` and the list in `generic.rkt`, and it
gets a `@defproc` with a live example in `polars/scribblings/reference.scrbl`,
guide coverage and a numbered example in the same change (see
Documentation). Tests go in the module's `(module+ test ...)`. Contracts go
in the module's `contract-out`, never as `unless`+`error`: `generic/meta.rkt` is
the shape; the older modules predate it and still rely on `->col-expr`'s `error`.

### Macros

`define-syntax-parse-rule`, or `define-syntax-parser` for several clauses;
never `define-syntax-rule` or `syntax-rules`. Put a syntax class on each
pattern variable (`name:id`, `op:expr`). Require the whole of
`syntax/parse/define`: it also provides the syntax classes, and with only an
`only-in` of `define-syntax-parse-rule` an annotation fails with "not defined
as syntax class" (a `define-syntax-parser` clause also needs `(for-syntax
racket/base)` for `#'`). `define-syntax-parse-rule` leaves each expansion at
the template's source location, where `define-syntax-rule` moved it to the
use site; a macro whose location shows (a rackunit helper, a template that
is a `lambda`) is a `define-syntax-parser` clause returning
`(syntax/loc this-syntax ...)`. The `no-syntax-rule` gate rejects both old
forms; the `resyntax` gate's suite rewrites the ones it can.

### Adding an FFI entry point

Rust side: `#[no_mangle] pub extern "C"`, in the module for its family under
`rust/src/`; the `expr_unop!` / `expr_binop!` macros in `rust/src/expr/macros.rs`
cover the common expression shapes. `cargo fmt` before committing — CI checks
it. Racket side: `define-compat` with `#:c-id`.

## Ownership across the boundary (invariants)

- A binding declared `-> _Series-ptr` / `_DataFrame-ptr` / `_Expr-ptr` /
  `_LazyFrame-ptr` takes `#:wrap (allocator <type>-drop)`, which registers
  the release.
- **A binding that can return NULL is declared `-> _X-ptr/null` with
  `#:wrap (allocator <type>-drop)`** (`expr-exclude`, `expr-dtype-col`).
  `allocator` skips a `#f` result, so the wrapper sees `#f` and raises. The
  non-null `_X-ptr` type itself raises a useless `argument is not non-null`
  error on NULL, before any reason can be reported. Never `cast` +
  `register-finalizer` by hand: that breaks the pairing with the
  `deallocator`-wrapped `<type>-drop`, so an explicit drop frees twice
  (#47). Where the Rust side records no reason, `#:wrap (allocator/or-fail
  <type>-drop 'who)` (`foreign.rkt`) registers the release and raises
  `who: operation failed` itself, so no wrapper is needed. A test in
  `foreign.rkt` reads every `define-compat` under `polars/private` and fails
  on one of these four result types without its allocator, or on a
  `_pointer` result.
- The `series`, `dataframe` and `lazyframe` wrappers carry
  `prop:owned-pointer`, so `series-drop` and its siblings given a wrapper
  release the pointer the allocator registered, once. A new wrapper struct
  around an allocated pointer needs the property too.
- Strings from Rust are allocated with `rust_string_to_ptr`, marshalled by the
  `_rsstring` ctype (NULL → `#f`, finalizer frees via `string_drop`).
- **Failure reasons travel out of band** (#45): an entry point that can fail
  calls `clear_last_error()` on entry (the shared `read_frame`, `write_frame`,
  `collect_frame` and `scan` helpers do it) and records the **cause alone**; the Racket
  wrapper names the operation and the path. Racket reads it with
  `call/foreign-error`, which makes the call and reads the reason inside one
  `call-as-atomic`: the slot is per OS thread and every Racket thread in a
  place shares one. Only wrap an entry point whose Rust side participates —
  today the `dataframe_read_*` / `dataframe_write_*` IO entry points, the
  `scan_*` family, `lazyframe_collect`, `lazyframe_explain`,
  `dataframe_sort_with_options`, `series_sort_with_options` and the three
  Enum entry points (`series_cast_enum`, `expr_cast_enum`,
  `expr_dtype_col_enum`) — or it attaches a stale reason from an unrelated
  call. `call/foreign-error`
  also respells the Python keyword names in Polars' "You might want to try"
  hints (`null_values` → `#:null-values`, `missing_columns='insert'` →
  `#:missing-columns 'insert`, ...), and drops the multi-file scan's hint to
  pass `extra_columns` or a schema, which the bindings lack.
- **A polars panic becomes the failure reason, not an abort.** A panic that
  unwinds out of an `extern "C"` function aborts the Racket process, and
  polars panics on some inputs where it could return an error (crate 0.41.3
  did so on a nulls-last boolean sort and a null-dtype `arg_sort`; 0.55.2
  does neither, `rust/src/tests/crate_sort.rs`, and #108 removes the
  routing around them).
  An entry point that runs polars on caller data wraps that work in
  `guard_panic` (`rust/src/ffi/errors.rs`), which records
  `polars panicked: <cause>` as the reason and returns NULL. Today
  `lazyframe_collect`, `lazyframe_explain`, `dataframe_sort_with_options`,
  `series_sort_with_options`, `series_cast_enum` and the IO helpers
  (`read_frame`, `read_path`, `write_frame`, `scan`) do: 0.41.3 aborted Racket on a
  Parquet Categorical or Decimal column (#93).
- `dataframe_drop_count`, `expr_drop_count` and `series_drop_count` count
  native releases; the reclamation tests assert on them because Racket cannot
  otherwise observe a native free (`foreign.rkt` has a case for each Series-
  and DataFrame-returning binding but the file readers, and `bulk.rkt` one for
  `series_copy_cat`), and pairing tests
  check that an explicit drop, of a pointer or a wrapper, releases it exactly
  once.
- The bulk copies (`series_copy_*`, `series_copy_as_f64`) write into memory
  Racket allocated: a raw buffer of the column's native type (bound with
  `with-raw-buffer`, freed when the conversion's extent exits), byte strings,
  and the `f64vector` a caller gets back. `in-dataframe-rows` binds one raw
  scratch buffer per block of rows, 16 bytes a row, which holds what any dtype
  needs, and each column's copy reuses it in turn: a `with-raw-buffer` costs a
  finalizer registration, several microseconds, which a buffer per column
  would pay for each column of each block. `series_copy_cat` also returns the
  copy's category strings as a new series, held with `with-release` while the
  conversion reads them. The byte strings and the `f64vector` may move: those
  bindings are never `#:blocking?`. Every destination travels with its
  length, Rust checks the rows it writes against it, and a refused copy writes
  nothing.
- **A scoped native resource is never paired by hand.** A buffer or owned
  result used only for the length of a computation is bound with
  `with-raw-buffer` or `with-release` (`polars/private/resource.rkt`), which
  expand into `dynamic-wind`, so the release runs on return, raise and
  escape; the buffer's finalizer backs up a thread killed inside the extent.
  No `(malloc …)` or `(free …)` appears outside `resource.rkt`: a test there
  fails on one.
- **An export never changes its signature under the same symbol.** A new
  signature gets a new symbol (`dataframe_read_csv` became
  `dataframe_read_csv_with_options`), so a stale library fails at load, when
  `define-compat` cannot resolve the symbol, instead of misreading its
  arguments.
- **A change to any `#[no_mangle]` export needs both
  `polars/native-libs/candidates/` refreshed before it merges.** The catalog
  installs those committed binaries (it has no Rust toolchain) and
  `define-compat` resolves every symbol at module load, so a stale candidate
  breaks `raco setup` on pkgs.racket-lang.org. CI's `Committed candidate`
  jobs go red on it. Refresh with `scripts/refresh-candidates.sh <PR>` on the
  branch; any other Rust change also reaches catalog users only through a
  refresh. See `polars/native-libs/BUILDING.md`.

## Behavioural facts to know before changing semantics

- `series #:dtype` accepts short and canonical spellings (`'f64`, `'float64`);
  `cast` / `series-cast` accept only canonical (#64).
- `/` on an integer column is integer division, unlike Python's `/` (#65).
- `read-csv` returns what `(collect (scan-csv ...))` returns for the same
  keywords, as Python's `read_csv` does: `dataframe_read_csv_with_options`
  reads a glob pattern by scan and collect, and a single file with 0.55's
  eager `CsvReader`, which is about three times faster on nycflights. Both
  are built from one decoded request, and a table-driven Rust test holds
  the eager, one-file-glob and scan reads to identical frames and error
  texts, with three listed exceptions (a malformed-quote error's chunk
  locator; an `#:n-rows 0` read of invalid UTF-8 fails eagerly). The one
  deliberate difference is the separator guard: when
  `#:separator` is not given, a one-column result whose header splits on a
  tab, `;` or `|` (and whose first row agrees) raises. The eager readers
  glob like the scans, CSV and Parquet (not NDJSON, #44); `#:glob #f` takes
  a CSV or Parquet path literally. An eager CSV read
  of a directory is an error, as in Python; a scan reads every file in it.
- A `scan-csv` / `scan-parquet` only builds a plan; a missing or malformed
  file, an invalid glob pattern, or one that matches no file is reported at
  `collect`, as in Python (0.55 expands a pattern at collect). Reported at
  scan instead: with `#:schema-overrides`, an override naming a column the
  header lacks. That check reads the header because 0.55 applies overrides
  by name and ignores an absent one, as Python 1.42.1 does; a misspelt
  override would otherwise do nothing. `call/foreign-error` respells 0.55's
  empty-expansion reason, which carries the pattern, as `no files match the
  pattern`.
- IO paths resolve against Racket's `current-directory`, not the process's
  (`path->complete-string` in `foreign.rkt`). For a globbing reader it
  escapes `[`, `*` and `?` in the directory part, so only the part the
  caller wrote is a pattern.
- Parquet reads add hive (`key=value`) columns only for a directory path,
  never for a single file or a glob, matching Python (`HiveOptions {
  enabled: None }`, which 0.55 resolves at collect).
- `read-parquet` is `scan-parquet` with the same keywords, collected, as
  Python's `read_parquet` is; its `#:columns` selects after the scan, so a
  position counts the row index column. The names and positions are checked
  against the scan's schema first, so a missing name, a position out of
  range or a column picked twice reports one line (Python's `select` reports
  the plan as well), and a name is a name, never Python's regex or `*`.
  `write-parquet` runs the eager `ParquetWriter`, where Python's goes
  through the streaming sink: given `#:row-group-size`, it writes groups of
  exactly that many rows, as the sink does (the eager writer alone splits
  the frame into equal parts); by default its groups are about 512² rows,
  the sink's about 122,880. The frames read back are the same. As in
  Python, `#:row-group-size 0` is the default and a codec without levels
  ignores `#:compression-level`. The
  Parquet verbs report under the verb's own name (`read-parquet:`), the
  low-level bindings under theirs (#153). `dataframe_read_parquet`,
  `dataframe_write_parquet`, `lazyframe_scan_parquet` and
  `lazyframe_scan_parquet_options` are no longer bound from Racket; their
  `_with_options` successors are.
- The separator guard is stricter than Python, whose `read_csv` returns the
  one column; the #86 scoreboard (check C1) requires the error.
- A duration schema override is a contract error: polars cannot parse a
  `Duration` column from CSV, in Python either.
- `round` rounds ties to even, as Python Polars and `racket/base` do.
- `sign` keeps the column's dtype: a float column gives `-1.0` / `0.0` / `1.0`.
- A `join` promises no row order except `'cross`, as Python's default
  `maintain_order='none'`; sort the result when order matters.
- `pivot` sorts the new columns by value, as Python's `sort_columns=True`; its
  aggregates are Python's (`'sum` of a missing cell is 0, `'count` is `len`).
- `unpivot #:on '()` melts every non-index column, as Python's `on=None`.
- A polars deprecation prints a warning to stderr: replace the spelling it
  names (a string cast to `'date` is `str->date`).
- Error wording follows the crate version. A test matches our `who:` prefix
  and the name, pattern or path the error carries, not the crate's phrasing.
- `filter` takes one predicate; combine with `and` (#62). `join #:on` takes a
  list, not a bare name (#62).
- `series` infers int64 / float64 / string / datetime / bool, and a list of
  symbols infers `'categorical`. It cannot build a `date` column from gregor
  `date`s (#63), and `lit` rejects gregor values.
- Categorical and Enum values surface as symbols (`ref`, every conversion);
  `lit` and `is-in` read a symbol as its name's string. An Enum dtype is the
  datum `'(enum sym ...)`, as `dtype` prints it; user code and the docs define
  one with `(define-enum id category ...)`, which checks the categories at
  compile time and binds that datum. Every categorical shares polars'
  one global mapping (no named `Categories`), whose codes restart when the
  last categorical column drops: the codes never leave Rust, and
  `series_copy_cat` re-encodes each copy densely with its own category table.
  A cast to an Enum is strict, as Python's default is; every other `cast`
  stays non-strict (a value that does not convert becomes null).
- A Decimal is `'(decimal precision scale)`, which `CompatDType` carries in
  `array_width` and `time_unit`; its values read as exact rationals. It has no
  `#:dtype` or cast-target spelling.
- `ref` and the bulk conversions (`series->list`, `in-series`, …) floor
  datetimes to whole seconds (#100); the conversions raise on an unsupported
  dtype, `binary` included (#99), even when every entry is null.
- A regexp given to `col` / `exclude` keeps its Racket meaning:
  `polars/private/column-pattern.rkt` rewrites `#rx` and `#px` syntax into the
  Rust regex crate's, and the oracle test in `generic/selectors.rkt` checks
  the selection against `regexp-match?`. It never emits the crate's `(?i`,
  whose Unicode folding differs from Racket's; it expands case-insensitive
  literals and ranges itself. `\p{...}` classes follow each side's Unicode
  tables, and Racket misjudges some classes above U+00FF (#85), so the
  oracle's names stay out of both. Lookaround, backreferences, atomic groups
  and conditionals, which the crate lacks, fail at `collect`.

## Documentation

- Scribble only; nothing explanatory in source comments. A comment survives
  only if it states an invariant the code cannot show.
- `polars/scribblings/utils.rkt` is the `mz.rkt` analogue: it re-exports
  `scribble/manual` and `scribble/example`, holds the `for-label` shadowing
  list once, and builds the evaluator (`make-polars-eval`).
- **Examples run at doc-build time.** Write `@examples[#:eval ev #:label #f ...]`,
  never hand-pasted `@verbatim` output; `eval:error` for an expected failure;
  `#:hidden` for setup. A broken example fails the build, on the package
  server too.
- Every `@section` has an explicit `#:tag`. Guide chapters mirror the upstream
  user guide in fluent style with terse prose; where a binding has no
  spelling for an upstream call, say so in an "API gap" note rather than
  quietly working around it.
- **Every new public name or keyword ships in the same PR with** (a) a
  reference entry whose live `@examples` exercise it, including an
  `eval:error` for a failure it reports; (b) guide coverage wherever the
  upstream user guide covers the feature: a snippet in the matching chapter
  of `polars/scribblings/guide/` and in its paired `user-guide/` `.rkt` and
  `.py` scripts; and (c) a numbered example `examples/NN-<area>-<topic>.rkt`
  at the next free number, which the `examples` gate runs. An example is
  self-contained, prints its results, needs no network, and deletes any file
  it writes.

## Verification

- **`nix flake check` is the CI-equivalent** (five checks: cargo tests, the
  Racket build with docs, tests, guide scripts, examples and bench tests,
  `cargo fmt --check`, the Racket version floor, `no-syntax-rule`).
  `nix build .#racket` runs only the second and is not enough. It does not
  cover CI's Lint job (`raco test lint` and the Resyntax run).
- nix builds from the **git-tracked tree**: `git add -A` before any nix
  command, or a new file fails with "file not found for module".
- Each worktree gets its own `PLTUSERHOME` (keyed on the path). In a fresh
  one, `raco setup --pkgs threading-doc` once, or the manual's `~>` link is an
  undefined tag and `threading-doc` looks unused.
- After any Rust change: `nix run .#copy-native-libs`, or the Racket tests run
  against the stale library.
- Racket tests live in `(module+ test ...)` submodules, which **merge per
  file** — a definition name used in one test block collides with the same
  name in another. Rust tests live in `rust/src/tests/`.
- `raco test -x -c polars` (Racket), `raco test -y user-guide` (the guide's
  paired scripts), `raco test -x bench` (strict mode's comparison),
  `cargo test --manifest-path rust/Cargo.toml` (Rust).
- `raco test -y -e -Q --empty-stdin -j 8 examples` runs every `examples/*.rkt`
  (the `examples` gate, in `push-gates` too; about 12 s). No `-x`: the
  examples have no `test` submodule, so `-x` would run nothing. An example
  is red if it raises, exits non-zero or writes to stderr. The flake's
  Racket check runs it too (`-j 4`), so a broken example fails CI.
- The gates in `.racket-dev.rktd` run all of the above through the
  racket-dev plugin's runner.
- The lint gates are `scripts/no-syntax-rule.sh` (a grep; no shell needed)
  and `scripts/resyntax-lint.sh` (dev shell; `fix` applies what it reports).
  The second runs the project's Resyntax suite, `lint/`: the default
  recommendations minus the rules it disables, plus the project's own rules,
  each tested by a `#lang resyntax/test` file (`raco test lint`). `lint/` is
  outside the published package and the nix build never compiles it. A
  review comment that is a semantics-preserving local rewrite becomes a rule
  there; anything else becomes a grep gate. The Resyntax run takes minutes
  (one large file alone takes about four), so it is not a push gate; CI runs
  it on every PR.
- `nix run .#bench` (the `bench` gate, not in the push subset) fetches the
  nycflights file into `bench/data/` (gitignored) and prints the scoreboard
  (`bench/blog-test.rkt`) and the rkt-polars / Python polars ratio table
  (`bench/perf.rkt`, `bench/perf.py`) for the working tree. Each nycflights
  leg (#88) reports it before and after, from a quiet host: the table's
  header prints the load average, and a Rust build alongside moves ratios
  several-fold. `bench/` is outside the published
  package; nothing under `polars/` may depend on it. A check for API a leg
  has not landed yet resolves it at run time and reports FAIL with the
  reason, so the harness compiles against master.
- `nix run .#bench -- --strict` (the `bench-strict` gate, not in the push
  subset) is the exit gate of the nycflights arc (#88, #90). It exits 1 unless
  every scoreboard check PASSes and every op's rkt/py ratio, as printed to
  two decimals, is within its allowance, and it lists each violation with the
  ratio, the allowance and the issue that owns it. The allowance is 1.2×
  unless the one table in `bench/allowances.rkt` names the op, with its
  issue and the measurement it was set from (today only the f64 matrix, #115).
  An entry is tightened when a run on master moves its op's ratio, and
  deleted once the op is within 1.2×. An op over its allowance is timed
  again, on both sides, before it fails. Each ratio is a median of 5 runs,
  so strict mode needs a quiet host even more than the table does; the
  verdict repeats the load average, the first thing to read on a red run.

## Process

- Arc = an epic issue listing its legs; leg = one PR on a branch
  `<area>/<slug>-<issue>`, title `area: what lands (#issue)`, review packet as
  the first comment, a comment on the epic when it opens.
- Preflight before the first push: gates green, an adversarial review and a
  style read of the diff applied locally.
- `master` requires one review and the maintainer is the only reviewer, so
  merges are `gh pr merge --squash --admin` once the owner approves.
- Follow-ups become issues, never TODO comments.
