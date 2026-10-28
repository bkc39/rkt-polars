# AGENTS.md

## Project overview

`polars` is a Racket binding to the [Polars](https://pola.rs) DataFrame
library. Racket calls a Rust `cdylib`, `libcompat` (`rust/`, polars crate
**0.55.2**), through `ffi/unsafe`; prebuilt shared objects for Linux x86-64 and
macOS arm64 ship with the package, so users need no Rust toolchain. The
`dtype-decimal` feature is on because polars' `sign` does not compile
without it (#106); Decimal columns are read (from Parquet), not built.
`dtype-categorical` carries Categorical and Enum. Every IO feature of the
crate is on (#176): `csv`, `parquet`, `json`, `ipc`, `ipc_streaming`, `avro`,
`scan_lines`, `decompress` (gzip, zlib and zstd input) and the cloud sources
`http`, `aws`, `gcp` and `azure`, which bring `cloud`, `async` and the file
cache. The `polars` crate has no `catalog` feature; Unity Catalog is reachable
only through direct `polars-lazy` and `polars-io` dependencies with theirs
(#191 decides). HTTPS is rustls on ring with the system's root certificates
(object_store's `rustls-tls-native-roots`); the `rustls-only` gate
(`scripts/rustls-only.sh`, a flake check and CI's Lint job) fails when
`rust/Cargo.lock` holds OpenSSL or native-tls, which would link the system's
libssl, or aws-lc, rustls' default provider, which is C and assembly built
with cmake. polars' `nightly` feature is on,
as in Python polars' own wheels: its `std::simd` code carries the CSV reader
(a stable build scans nycflights at 2.5× Python). It compiles on the pinned
stable rustc, nixpkgs' at `flake.lock`, with `RUSTC_BOOTSTRAP=1`, which the
flake's build and dev shell and `scripts/build-so.sh` set.
`rust/rust-toolchain.toml` names that release for `scripts/build-so.sh`, and
the `release-toolchain` flake check fails when the two differ. The release
build is rustup's build of the release, whose LLVM can differ from nixpkgs',
so `nix flake check` does not test the shipped code generation. The Linux
build's manylinux2014 image is pinned by digest in the script. The committed
candidates are built with `[profile.dist]` in `rust/Cargo.toml`: release plus
thin LTO and one codegen unit (#125), which keeps the Linux `.so` at 81.6 MB
against GitHub's 104,857,600-byte file limit (102.2 MB without it), before
the IO features of #176, which added 2.5 MB to the first and 3.3 MB to the
second on the previous toolchain. Only
`scripts/build-so.sh` uses it. The nix build, `cargo test` and the bench stay
on `release`, because under LTO every test and example binary links on one
core (the nix check went from 30 to 145 minutes on CI), so the bench measures
the release build, not the shipped one. `panic` stays `unwind`: `guard_panic`
depends on it.

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
   `in-dataframe-rows` and their siblings; it binds the numeric, boolean and
   categorical copies, and takes the String and Decimal ones,
   `series-copy-str` / `series-str-byte-len` and `series-copy-decimal`, from
   `foreign.rkt`, where `series-ref` reads through them). `define-compat`
   binds a C symbol; the Racket name is the symbol with `_` → `-`, or an explicit
   `#:c-id`. Bindings whose Racket name carries a `/raw` or `/c` suffix are
   wrapped by a checking function of the plain name, except the
   `series-ref-<type>/raw` readers, which carry an index contract and which
   `series-ref` reads through unchecked.
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
   `(require polars)` is enough. `read-json` / `write-json` keep Python's
   names (owner's decision, 2026-10-07), which the `json` library also
   provides: `(require polars json)` fails with "identifier already
   required", and `(prefix-in js: json)` or `(except-in json read-json
   write-json)` is the fix the docs give.

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
Documentation). Tests go in the module's file under `polars/tests/`, or its
inline `test` submodule until #256 moves it (see Verification). Contracts go
in the module's `contract-out`, never as `unless`+`error`: `generic/meta.rkt`
is the shape; the older modules predate it and still rely on `->col-expr`'s
`error`.

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
  `deallocator`-wrapped `<type>-drop/raw`, which `<type>-drop` wraps,
  refusing a dropped value, so an explicit drop frees twice (#47). Where the Rust side records no reason, `#:wrap (allocator/or-fail
  <type>-drop 'who)` (`foreign.rkt`) registers the release and raises
  `who: operation failed` itself, so no wrapper is needed. A test in
  `polars/tests/foreign.rkt` reads every `define-compat` under
  `polars/private` and `polars/tests` and fails on one of these four result
  types without its allocator, or on a `_pointer` result. It also fails on
  `allocator/or-fail` around a `_v2` (or later) entry point, which records a
  reason that `operation failed` would discard.
- The `series`, `dataframe` and `lazyframe` wrappers carry
  `prop:owned-pointer`, so `series-drop` and its siblings given a wrapper
  release the pointer the allocator registered, once. A new wrapper struct
  around an allocated pointer needs the property too.
- `define-owned-cpointer-type` defines each of the four pointer types
  (`_Series-ptr`, `_DataFrame-ptr`, `_Expr-ptr`, `_LazyFrame-ptr`), its
  predicate and its drop around the `-drop/raw` `define-compat` it is given,
  which stays a subform so the ownership audit reads it. A drop retags the
  pointer, which the raw value and every wrapper of it share. The predicate
  still accepts a retagged pointer, as `port?` accepts a closed port, so every
  contract and dispatch passes it on to the conversion into Polars, which
  refuses it on its failure path: the live path costs nothing, a later use
  raises `series: series has been dropped` (`expr: expression has been
  dropped`; the kind is the `who`, since no verb is known there), a second
  drop raises under the drop's own name, and the native release still runs
  once (#131). The check is made as a call converts its arguments, outside
  any atomic region, so a drop must not run while another thread uses the
  same value: a drop between the conversion and the native call frees memory
  the call then reads.
- Strings from Rust come back as a block (`str_out` / `str_list_out`,
  `rust/src/ffi/strings.rs`). A block is native-endian 64-bit words, and
  word 0 is its size in words. A single string has its UTF-8 length in word
  1 and its bytes from word 2. A list has its count in word 1, `count + 1`
  offsets from word 2, and then the bytes. `_rsstr` and `_rsstr-list`
  (`foreign.rkt`) read a block by length, so a NUL in a name, a reason or
  printed text survives. They free it at once through `str_block_drop`, in
  atomic mode, so a thread killed during the read is killed after the free.
  NULL reads as `#f`. `str_block_drop_count` counts the releases. Only
  `series_ref_str` still returns a C string: `_c-string-result` copies it and
  frees it through `string_drop`, until #165's categorical leg retires both.
  `rust/src/tests/c_strings.rs`, on the guard audit's walk, fails on any
  other export that returns one.
- **Failure reasons travel out of band** (#45): an entry point that can fail
  calls `clear_last_error()` on entry (the shared `write_frame`,
  `collect_frame` and `scan` helpers do it) and records the **cause alone**; the Racket
  wrapper names the operation and the path. Racket reads it with
  `call/foreign-error`, which makes the call and reads the reason inside one
  `call-as-atomic` (given no format, the reason alone follows the verb;
  `call/polars-reason` is that call, and `define-reasoned` binds a
  keyword-free public name with a `name/who` variant taking the verb, as for
  the series operators): the slot is per OS thread and every Racket thread in a
  place shares one. Only wrap an entry point whose Rust side participates —
  today the `dataframe_read_*` / `dataframe_write_*` IO entry points, the
  `scan_*` family, `lazyframe_collect`, `lazyframe_explain_v2`,
  `dataframe_to_string_v2`, `expr_to_string_v2`, `series_cast`,
  `dataframe_pivot_v2`, `dataframe_unpivot_v2`,
  `dataframe_sort_with_options_v2`, `series_sort_with_options`,
  `series_new_str_packed`, the series-by-series operators (`series_add`,
  `series_sub`, `series_mul`, `series_div`, `series_mod`, `series_eq`,
  `series_ne`, `series_gt`, `series_ge`, `series_lt`, `series_le`,
  `series_and`, `series_or`, `series_xor`, `series_not`), `dataframe_vstack`,
  `dataframe_hstack`, `dataframe_join_v2`, `dataframe_join_asof_v2`,
  `dataframe_join_asof_options_v2`, every other entry point that takes a
  `_str` or `_str-list` block (`series_rename_v2`, `dataframe_select_v2`,
  `dataframe_drop_columns_v2`, `dataframe_rename_v2`, `dataframe_column_v2`,
  the five `dataframe_group_by_*_v2`, `lazyframe_sort_with_options_v2`,
  `lazyframe_join_v2`, `expr_col_v2`, `expr_lit_str_v2`, `expr_alias_v2`,
  `expr_exclude_v2`), the three Enum entry points (`series_cast_enum`,
  `expr_cast_enum`, `expr_dtype_col_enum`) and the nine that take a time
  zone's name (`series_cast_datetime_tz`, `expr_cast_datetime_tz`,
  `expr_dtype_col_datetime_tz`, `expr_lit_datetime_tz`,
  `series_dt_convert_time_zone`, `series_dt_replace_time_zone`,
  `expr_dt_convert_time_zone`, `expr_dt_replace_time_zone`,
  `expr_str_to_datetime_tz`) — or it attaches a stale reason from an unrelated
  call. `call/foreign-error`
  also respells the Python keyword names in Polars' "You might want to try"
  hints (`null_values` → `#:null-values`, `missing_columns='insert'` →
  `#:missing-columns 'insert`, `ambiguous` → `#:ambiguous`, ...;
  `non_existent='null'` becomes `dt-replace-time-zone`'s `#:non-existent
  'null`, since `str->datetime` and the other verbs that can raise it lack
  the keyword) and in the JSON readers' advice to increase
  `infer_schema_length` or give a schema. It drops the multi-file scan's
  hint to pass `extra_columns` or a schema, which the bindings lack, and the
  hint to set `POLARS_IGNORE_TIMEZONE_PARSE_ERROR`: the nine take a zone's
  name through `named_time_zone`, which checks it with
  `TimeZone::validate_time_zone` after `opt_try_new`, and only `opt_try_new`
  reads that variable, so setting it changes nothing here.
- **A polars panic becomes the failure reason, not an abort.** A panic that
  unwinds out of an `extern "C"` function aborts the Racket process, and
  polars panics on some inputs where it could return an error (crate 0.41.3
  did so on a nulls-last boolean sort and a null-dtype `arg_sort`; 0.55.2
  does neither, and `rust/src/tests/crate_sort.rs` pins that, so the sorts
  call the crate directly).
  An entry point that runs polars on caller data wraps that work in
  `guard_panic` (`rust/src/ffi/errors.rs`), which records
  `polars panicked: <cause>` as the reason and returns NULL. The panic hook
  stays quiet for a panic on a thread inside a guard, or on a polars worker
  (a rayon thread, polars' async executor or a tokio thread) while any
  guard runs, so a caught panic prints nothing to stderr; every other panic
  reaches the previous hook. The worker test is process-wide, which assumes
  one place calls polars: while a guard runs in one place, a panic on a
  worker from an unguarded entry point in another prints nothing and then
  aborts, a case guarding the `todo-129` entry points (#129) removes. A
  streaming task that panics after an earlier error cancelled it is dropped
  with its payload, so the reason is that error's and the panic prints
  nothing. 0.41.3 aborted Racket on a Parquet Categorical or Decimal column
  (#93), a `scan-csv` that reads the header (`#:schema-overrides`) aborted it
  on a compressed file (#177), and printing, a `cast` to a string, `pivot` and
  `unpivot` did on a date or datetime outside chrono's range (#141). Which
  entry points are guarded is the audit's to say, not this file's:
  `rust/src/tests/guard_audit.rs` parses every file under `rust/src` with
  `syn`, expands the crate's own `macro_rules!` invocations (nested ones
  too; a repetition, an unknown macro wrapping an export, or a recursion
  past depth 32 is a failure), and takes every function with `no_mangle` or
  `export_name` (bare or under `unsafe(...)`) and a non-Rust ABI as an entry
  point. One is guarded when the value its body returns flows from a call to
  `guard_panic` or to a guarding helper: the body's tail is such a call, a
  method call on one, a call or method call taking one (or a closure whose
  body is one) as an argument, a `match` on one, or a local bound to one by
  `let`; a helper is guarding when every function of its name is guarded in
  that sense. It does not check what runs before the guard or in an adapter
  after it. Every other entry point is listed in `rust/src/tests/unguarded.txt`,
  one `name class` per line: `drop` and `count` (which must be the `_drop`
  and `_drop_count` names), `accessor`, `builder`, `constructor`, `error`,
  and `todo-129`, the eager compute entry points that run polars on caller
  data unguarded until #129 (L7 of #223) guards them with a reason reported
  to Racket. The audit fails on a stale or misclassified line, so guarding an
  entry point means deleting its line.
- `dataframe_drop_count`, `expr_drop_count`, `lazyframe_drop_count` and
  `series_drop_count` count native releases; the reclamation tests assert on
  them because Racket cannot otherwise observe a native free
  (`polars/tests/foreign.rkt` has a case for each Series- and
  DataFrame-returning binding but the file readers, `tests/bulk.rkt` one for
  `series_copy_cat`, and `tests/expr.rkt` one for each plan helper), and
  pairing tests check that an explicit drop, of a pointer or a wrapper,
  releases it exactly once.
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
- **Strings cross into Rust in one allocation, never as `(_list i _string)`.**
  That type turns each element into a fresh byte string and stores its
  address in an array the collector does not trace, so a collection while the
  array fills moves or frees the strings already stored, and Rust reads stale
  memory (#143: wrong values from about 300,000 strings, an abort at a
  million).
  - A string series is the bulk copy in reverse: `series-new-str` passes one
    UTF-8 byte string, row offsets in a `with-raw-buffer` and a validity byte
    string to `series_new_str_packed`, which checks every offset against the
    buffer and a character boundary. The byte strings may move, so the
    binding is never `#:blocking?`.
  - A name, a list of names (`by`, `on`, `#:columns` of `dataframe-select`,
    ...) and a `lit` string cross as an argument block in the result blocks'
    layout: `_str`, `_str/null` and `_str-list` (`resource.rkt`). The block is
    `'atomic-interior` and holds no address, so a NUL in a name survives every
    lookup (`ref`, `col`, `select`, `drop`, `sort`, `join`, `pivot`, ...), and
    a name read back finds its own column, never one named by its prefix
    (#165).
  - Each element is `utf-8-name/c` (`resource.rkt`): a string (as UTF-8), or
    a byte string or path that is UTF-8 (#248). The syntax refuses any other
    value under its own name, before any call, so every public verb that
    takes a name contracts it with `utf-8-name/c` (`series`, `rename!`, the
    `series-new-*` constructors, ...) and the error names that verb.
    `_str-list` passes NULL for `'()`.
  - Rust's `str_arg` / `str_list_arg` check every bound against the block's
    size, the offsets' order and every element's UTF-8. The v2 entry points
    that take them record the cause and fail, so a malformed block is an
    error, never a read past the block. Those that run polars code on caller
    data share `boxed_result` / `scalar_result` (`rust/src/ffi/results.rs`);
    a builder or accessor that runs none uses `boxed_unguarded`.
  - The `series-new-*` constructors keep their C symbols: each is called with
    the constant empty name, and the wrapper renames the fresh series with
    `series_rename_v2`.
  - `series-eq-str` and `series-ne-str` compare against a one-row String
    series through `series_eq` / `series_ne`, so they take what `=` takes
    beside a series: a Categorical or Enum operand compares by value (a value
    outside an Enum's categories is `#f` for `series-eq-str`), and a
    `polars-null` right-hand side gives a null on every row.
  - These are `_fun` argument syntaxes, not ctypes, because a callout retains
    the values it is given and not what a ctype converts them to: as a ctype
    the block could be freed by a collection during a `#:blocking?` call or a
    callback.
  - `_string-list`, a `const char **` table and its NUL-terminated strings in
    one block, is left only where Enum categories and the IO readers'
    keywords still cross as C strings. A test in `polars/tests/resource.rkt`
    names those seven bindings and fails on any other `define-compat`,
    `define-syntax-parse-rule` or `define-syntax-parser` that uses it, at any
    depth (inside a `begin` or another definer).
  - `series-ref` reads a String value by length, through `series_copy_str`,
    since a C string ends at a NUL the value may hold.
  - Categorical and Enum values are still read as C strings, and Enum
    categories cross as one, so `series` refuses a NUL in a categorical or
    Enum value, and `series`, `cast`, `col`, `series-cast`, `expr-cast` and
    `expr-dtype-col` refuse one in an Enum category (`check-enum-categories`);
    `define-enum` refuses it at compile time. Formats, zones and
    categoricals cast from a String series still stop at a NUL (#165).
  - A C string still crossing is `_c-string` / `_c-string/null`
    (`foreign.rkt`), which refuse a NUL.
  - A test in `polars/tests/resource.rkt` reads every module under
    `polars/private` and `polars/tests` as data and fails on a
    pointer-holding ctype (`_string`, `_bytes`, `_path`, `_file`, `_symbol`,
    `_gcpointer`, `_racket`, their `/` and `*` variants, or a name `define`d
    as one, directly or through `make-ctype`) as the element of a `_list` /
    `_vector` / `_ptr` in mode `i` or `io`, of an `_array`, `_array/list`,
    `_array/vector`, `_box` or `_list-struct`, as a `define-cstruct` field,
    or in `define-series-constructors`. It also fails on a `define-compat` in
    `polars/private` whose result is `_string`, `_string/utf-8` or
    `_string*/utf-8`, and on a `_fun` or a `define-series-constructors` there
    naming `_rsstring`.
- **A scoped native resource is never paired by hand.** A buffer or owned
  result used only for the length of a computation is bound with
  `with-raw-buffer`, `with-release`, `with-releases` for a list acquired by
  a `for` loop, or `with-release-pool` for the values a computation hands to
  the procedure it binds (`polars/private/resource.rkt`), which expand into
  `dynamic-wind`, so the release runs on return, raise and escape (a raise
  part way through a `with-releases` loop releases what it acquired, and a
  release that raises does not stop the others, as with nested
  `with-release`s); the buffer's finalizer backs up a thread killed inside
  the extent. Each clause's acquire sees the bindings outside it, as `let*`
  does; its release sees the name bound to what the acquire returned, and
  that value is the one released. A `with-release` name is `#f` once
  released, and its extent is entered once: a continuation that re-enters it
  raises. A value that may or may not be owned (a variadic operator's
  running result) is released with `drop-owned` (`expr-core.rkt`), which
  dispatches on the four pointer types' predicates and ignores any other
  value; a pointer already dropped raises under that type's drop name, as
  `series-drop` does.
  No `(malloc …)` or `(free …)` appears under `polars/private` or
  `polars/tests` outside `polars/private/resource.rkt`: a test in
  `polars/tests/resource.rkt` fails on one.
- **An export never changes its signature under the same symbol.** A new
  signature gets a new symbol (`dataframe_read_csv` became
  `dataframe_read_csv_with_options`, then `dataframe_read_csv_v2`), so a
  stale library fails at load, when
  `define-compat` cannot resolve the symbol, instead of misreading its
  arguments.
- **A change to any `#[no_mangle]` export needs both
  `polars/native-libs/candidates/` refreshed before it merges.** The catalog
  installs those committed binaries (it has no Rust toolchain) and
  `define-compat` resolves every symbol at module load, so a stale candidate
  breaks `raco setup` on pkgs.racket-lang.org. CI's `Committed candidate`
  jobs go red on it, except below a stack's top, which refreshes once for
  the stack and where they only warn. Refresh with `scripts/refresh-candidates.sh <PR>` on the
  branch; any other Rust change also reaches catalog users only through a
  refresh. See `polars/native-libs/BUILDING.md`.

## Behavioural facts to know before changing semantics

- `series #:dtype`, `cast` and `series-cast` accept short and canonical
  spellings (`'f64`, `'float64`) (#64); `dtype` returns the canonical one.
- `/` on integer operands (integer, Boolean or Null) is integer division,
  unlike Python's `/` (#65), two Null operands aside, which give Float64.
  On two series it is Python's `//`: a signed integer series beside a UInt64
  one, whose supertype is Float64, gives the floored Float64 quotient
  (`series-true-div` floors it through `expr-floor`). The expression form
  (`expr_div`, `RustDivide`) still true-divides there (#303), beside a UInt64
  column or a literal from 2^63: a plan-time choice by the operands' dtypes
  (`DataTypeExpr::matches` in a `when`) fails on a regex selector, which may
  not expand inside a dtype expression, and keeps its dead `floor_div`
  branch live when an operand is not elementwise (a `sum`), where it raises
  on Decimal and Null.
  Any other `/` divides as Python's does: an integer, Boolean or Null series
  is cast to Float64 first, and so is the series under a plain number on the
  left (`(/ 1 f32)` is Float64) and a Decimal series under a boolean or a
  temporal value on the left (`(/ (hours 1) decimals)` is a duration).
- `read-csv` and `scan-csv`:
  - `read-csv` returns what `(collect (scan-csv ...))` returns for the same
    keywords, as Python's `read_csv` does: `dataframe_read_csv_v2` reads a
    glob pattern, or any path given `#:n-rows`, by scan and collect, and
    any other single file with 0.55's eager `CsvReader`, about three times
    faster on nycflights. Given `n_rows`, the eager reader stops spawning
    chunks once the chunks already parsed hold more rows, so whether it
    reaches a later chunk that fails (a late `NA` in an inferred integer
    column) depends on thread timing (#147). The scan cuts line batches in
    order (the first is what schema inference read, at least 32 KiB or the
    whole file with `#:infer-schema-length #f`, plus 32 KiB; each later one
    larger, up to 512 KiB), decodes them in parallel, and stops at the
    first batch past the slice, so a bad value beyond it is not reported:
    deterministic, but dependent on the file's size. Given
    `#:comment-prefix` too, polars-stream does not push the slice into the
    CSV source, so the scan parses the whole file: a bad value anywhere in
    it fails the read, and `#:n-rows 5` of a 100 MB file takes about
    105 ms, against 15 ms for the eager reader. Both are built
    from one decoded request, and a table-driven Rust test holds the eager,
    one-file-glob and scan reads to identical frames and error texts, with
    one listed exception, a malformed-quote error's chunk locator.
  - `#:columns` is `read-csv`'s alone, as `columns` is Python's
    `read_csv`'s; the scan entry point applies it too, so the test covers it.
  - Every keyword that names a column names it as `#:new-columns` leaves it,
    as Python's `scan_csv` does; Python's `read_csv` selects and applies a
    `null_values` mapping by the file's names and renames afterwards.
    `#:new-columns` reads the header, translates every by-name keyword back
    to the file's names, reads, and renames (`df.set_column_names` eagerly,
    `LazyFrame::rename` in a scan), with any row index added after the
    rename. So a per-column null marker counts during type inference, and
    the eager and scan paths stay independent for the parity test. A row
    index named like a column is an error on every path.
  - Every reader numbers the row index from 0 and adds `#:row-index-offset`
    afterwards, checked (`offset_rows` / `offset_frame_rows` in
    `lazyframe/scan.rs`): 0.55's eager `CsvReader` adds later chunks'
    offsets unchecked and wraps past `u32::MAX`, and the streaming row-index
    node panics.
  - The separator guard is the one read/scan difference: when
    `#:separator`, `#:new-columns` and `#:columns` are not given, a
    one-column result (a row index aside) whose header splits on a tab, `;`
    or `|` (and whose first row agrees) raises.
  - The eager readers glob like the scans, CSV, Parquet and NDJSON (#44);
    `#:glob #f` takes a CSV or Parquet path literally, and NDJSON has no
    opt-out (#36). An eager CSV read of a directory is an error, as in
    Python; a scan reads every file in it.
- `write-csv` is the eager `CsvWriter`; Python 1.42.1's `write_csv` runs
  `sink_csv`, and a Racket test holds the two to the same bytes for 18
  option sets (`polars/scribblings/data/write-csv-expected.rktd`), one of
  them a batch size of 1. The writer clamps the batch size to the frame's
  height, which writes the same bytes, because 0.55 multiplies it by the
  thread count unchecked (`write_impl.rs`), and a wrapped product loops
  forever.
- The IO keyword procedures come from `define-io-options`
  (`polars/private/io-options.rkt`): one option list gives each entry's
  `->i` contract, its sorted keyword list, the options procedure, and the
  `#:arguments` table the reference's `defproc/arguments` renders. A `_fun`
  type shared by two entry points is a macro used as
  `(define-compat name (_csv-fun -> _DataFrame-ptr/null) ...)`, so the
  ownership audit in `foreign.rkt` still reads the result type and the
  `#:wrap`.
- A `scan-csv` / `scan-parquet` / `scan-ndjson` only builds a plan; a
  missing or malformed file, an invalid glob pattern, or one that matches
  no file is reported at
  `collect`, as in Python (0.55 expands a pattern at collect). Reported at
  scan instead: with `#:schema-overrides`, an override naming a column the
  header lacks. That check reads the header because 0.55 applies overrides
  by name and ignores an absent one, as Python 1.42.1 does; a misspelt
  override would otherwise do nothing. `scan-ndjson` makes the same check
  (inferring the schema when none is given), since 0.55 reports an absent
  override at collect as a bare column name. `#:new-columns` reads the header at
  scan too, to translate names, as Python's `scan_csv` does, so
  either keyword reports a file that cannot be opened at scan, with the
  cause alone. `call/foreign-error` respells 0.55's
  empty-expansion reason, which carries the pattern, as `no files match the
  pattern`.
- polars reserves 24 bytes a row for a CSV `#:infer-schema-length` before
  it reads (`streaming.rs`), so `rows_to_infer` (`lazyframe/csv.rs`) reads
  every row instead when a count over 2^20 reserves more than the host's
  memory or 2^47 bytes, or more rows than the local inputs could hold. The
  memory is `POLARS_OVERRIDE_TOTAL_MEMORY`, parsed by `host_memory` as
  polars does, or else polars' `total_memory()` (`polars_utils::sys`: a
  container's cgroup limit where one is set, since sysinfo reads the cgroup
  mount's root, not the process's own cgroup). A malformed override counts
  as 0 bytes, and `total_memory()` is not called: it panics on one and
  poisons its `LazyLock` for every later read.
- A count kept still reserves up to all of memory per file, for up to
  min(cores, files) files at `collect` and 10 during inference: harmless
  under the default heuristic overcommit, an abort under
  `vm.overcommit_memory=2`, as in Python polars.
- The input bound is fixed when the plan is built, not at `collect`: it
  expands the paths with polars' `expand_paths`, stats each file, opens a
  regular one with `O_NONBLOCK` and checks the handle is still one (a file
  swapped for a FIFO would block the open inside `call-as-atomic`), and
  reads its first four bytes. So a pipe, a device, an unexpanded cloud path
  or a file created later gives no bound, and a count past a file's size
  then reads every row even if the file grows (or reports a size of 0
  though it has content). One poll of `expand_paths` suffices: its local
  branch never awaits, and a `Pending` poll counts as no bound (`block_on`
  could hang under `POLARS_FORCE_ASYNC` inside `call-as-atomic`).
- IO paths resolve against Racket's `current-directory`, not the process's
  (`path->complete-string` in `foreign.rkt`). For a globbing reader it
  escapes `[`, `*` and `?` in the directory part, so only the part the
  caller wrote is a pattern.
- `read-json` / `write-json` are Python's `read_json` / `write_json`: one
  JSON array of objects (a lone object reads as one row), eager only, since
  the crate has no JSON-array scan or sink. The path is literal (no glob) and
  a directory is an error. `#:infer-schema-length` must be positive or `#f`:
  Python panics on 0. An override naming a column absent from the file (or
  from `#:schema`) is an error, as in Python, reworded from 0.55's bare
  `SchemaFieldNotFound`. The schema dtypes are `series`' `#:dtype` spellings
  but an Enum, which `CompatDType` cannot carry; a column name with a NUL is
  a contract error, since `_string/utf-8` would cut it there (#165).
  `write-json` refuses a binary column, where polars hits a `todo!()`.
- Every writer goes through `write_checked_frame` (`write_frame` when there
  is nothing to check; `rust/src/dataframe/io.rs`).
  Its checks on the frame and the path (a JSON writer's binary column, say)
  run before the target is opened. It follows a symlink to the file it
  names; a dangling link is written through in place, creating that file.
  A directory target is refused, and a FIFO or device is written in place.
  For a regular or missing file it writes `.rkt-polars-<pid>-<n>.partial`
  in the target's directory (`create_new`, so never through a planted link)
  and renames it onto the target once the write succeeds, so a failed write
  leaves an existing file as it was. That directory, for a symlink the
  pointee's, must be writable. A read-only target is refused before
  anything is staged. A replaced file keeps `mode & 0o777`, set before any
  data is written: its set-ID and sticky bits, owner, ACLs, extended
  attributes and hard links are not kept. A staging file left by a killed
  process is skipped by an extension glob such as `dir/*.parquet` and read
  by a bare `dir/*`; a read of the directory itself skips it while it is
  empty (polars-io drops zero-length files) and otherwise fails with
  polars' "different file extensions" error.
- `read-ndjson` is `(collect (scan-ndjson ...))`, as Python's `read_ndjson`
  is, through `dataframe_read_ndjson_with_options`; a directory reads every
  file in it, and they must share one extension (a README or `.DS_Store`
  fails with "directory contained paths with different file extensions",
  in Python too). Its schema dtypes exclude Int8, Int16, UInt8, UInt16, Time,
  Duration and Enum: 0.55's NDJSON buffer panics on the first six, which
  Python passes through. Null is allowed, as in `read-json`: a column the
  file lacks reads as nulls, and a value for a Null column is an error, as
  in Python. `#:batch-size` and `#:low-memory` reach
  `LazyJsonLineReader` as in Python, and 0.55 reads neither.
  `#:row-index-name` and `#:include-file-paths` must differ (polars panics
  otherwise). With `#:schema`, `#:schema-overrides` is applied to it in
  Rust, as for `read-json`: Python's `read_ndjson` ignores the overrides
  once a schema is given. The eager NDJSON verbs and `lazyframe_collect`
  strip the "Resolved plan until failure" dump polars appends to a planning
  error (`without_plan`). A fluent verb that builds a plan and collects it
  (`select`, `with-columns`, `filter`, `agg`) reports the cause under its own
  name, through `lazyframe-collect/who` (the `internal` submodule of
  `expr.rkt`), and `collect` under `collect`.
- `write-ndjson` is Python's `lazy().sink_ndjson()`, through
  `dataframe_write_ndjson_with_options`, through `write_frame` like the
  other writers: the sink writes to the staged file (`SinkTarget::Dyn`), and
  since the staging name has no extension `#:check-extension` matches the
  target's name to `#:compression` in Rust (`ndjson_extension`, polars'
  own messages) and the sink gets `check_extension: false`. gzip and zstd
  need the `decompress` feature (#176) and a `flate2` newer than 1.0.30, whose
  `zlib-rs` 0.1.1 aborts the process on some gzip streams (#199). Readers
  sniff compression from the first four bytes, not the name
  (`SupportedCompression::check`): no valid JSON starts with a signature,
  so a plain file that does fails with a decompression error.
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
  ignores `#:compression-level`. Stricter than Python, a non-empty
  `#:statistics` list must name `'min`, `'max` and `'null-count`: without
  min and max polars writes a page index that marks pages holding values as
  null pages (#203), and without the null count it fails at the footer on a
  column it does not dictionary-encode. A name passed as a C string
  (`#:columns`, `#:row-index-name`, `#:include-file-paths`) refuses a NUL in
  the contract, which would otherwise truncate it (#165).
- The Parquet verbs report under the verb's own name (`read-parquet:`),
  the low-level bindings under theirs (#153). The C surface is the three
  `_with_options` entries; Rust tests reach them through the default-option
  helpers in `tests/dataframe/io.rs`.
- The Parquet reader and scan number the row index from 0 and add
  `#:row-index-offset` afterwards, checked, as the CSV readers do; polars'
  streaming row-index node would panic past `u32::MAX`.
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
- Inside `agg` or `over`, the crate's `SortExpr` reads out of bounds when its
  input holds one value per group: it gathers each group's row indices from
  that one value (#167). The read segfaults on a string or a large frame, and
  Python 1.42.1 segfaults on the same query. `cargo test` builds with debug
  assertions, where the read is a `check_bounds` panic instead, so a Rust
  test catches it without needing a crash. So an expression `sort` is
  decided by the input's structure. An input that is one value per group (an
  aggregation, `len`, a scalar literal, or an alias, cast, operator or `when`
  over those alone) comes back unsorted. An input that keeps a value per row
  (a column or selector, or an alias, cast, sort, operator or `when` with one
  among its operands) gets `Expr::sort`, because polars evaluates it per group
  as a column or a list. Anything else, a function of one value per group
  such as `(abs (sum "v"))` among them, becomes `e.sort_by([e])`.
  `SortByExpr` repoints such groups at the values before it gathers. This
  path evaluates the input twice and prints as `sort_by`. A new form goes
  into the per-row set only after its evaluation in `polars-expr` has been
  checked.
- `unpivot #:on '()` melts every non-index column, as Python's `on=None`.
- A column name, a frame's, an expression's or a plan's text and a failure
  reason come back from Rust with any NUL they hold, and print it raw, as
  Python's `str(df)` does (#165). A name or a string literal given to a verb
  keeps its NUL too, as in Python: `series #:name`, `rename`, `ref`,
  `col`, `alias`, `exclude`, `lit` and every verb that names a column, so a
  frame may hold both `"a"` and `"a\u0000b"` and each finds its own.
- A polars deprecation prints a warning to stderr: replace the spelling it
  names (a string cast to `'date` is `str->date`).
- Error wording follows the crate version. A test matches our `who:` prefix
  and the name, pattern or path the error carries, not the crate's phrasing.
- `filter` takes one predicate; combine with `and` (#62). `join #:on` takes a
  list, not a bare name (#62).
- An empty list or vector is an empty series of `#:dtype`, or `'null` without
  one, as Python's `pl.Series([])` (#98); every constructor, native ones
  included, takes zero rows. A list or vector of `polars-null` alone infers
  `'null` too, as `pl.Series([None])` does, and a null among other values
  takes their dtype; `#:dtype 'null` (`series_new_null`) takes `polars-null`
  elements only. `is-in` reads a list the same way, so `(list polars-null)`
  is a Null literal, and an empty list is a member of nothing (`#f`, null for
  a null), as Python's `is_in([])` is; a list holding an exact integer and
  a flonum or exact non-integer is a contract error naming one of each, in
  either order, as Python's `is_in([1, 2.5])` raises a `TypeError`
  (Python reads a list whose first element is a float, `[2.5, 1]`, as
  floats).
  `(lit polars-null)` is
  `expr_lit_null`, Python's `pl.lit(None)`: a null of dtype Null, so a
  comparison with it is null on every row and arithmetic keeps a numeric
  operand's dtype; with a temporal operand (date, datetime, zoned, time,
  duration) arithmetic raises, as Python's expression form does. An
  arithmetic or comparison operator given a `polars-null`, or a `'null`
  series and a plain value, runs its expression form (see the operand fact
  below); Python's eager `s - None` on a date series gives null durations
  where its expression raises, and ours raises like the expression. `and`,
  `or` and `xor` lift `polars-null` beside a series to a Boolean null, which
  gives the expression form's Kleene result; with `polars-null` on the left
  and an expression or series after it, `and` and `or` combine as Python's
  `pl.lit(None) & e` does, not as Racket's short-circuit (so an `or`
  evaluates its rest to know). On a `'null` series `sum`, `mean`, `min`, `max`, `std`
  and `var` give `polars-null` and `n-unique` gives 1, through the
  expression engine (the typed `series_sum_*` have no Null case). A `'null`
  column does not vstack or join with a typed one, and `and`, `or`, `xor`
  and `not` refuse a `'null` series, as Python's eager operators do, and any
  other non-Boolean series, where Python's `& | ^` are bitwise on integers.
- A plain value beside a typed series in an operator follows Python
  1.42.1's eager operators (decision (b) of #261). It is a constant of the
  series' dtype when it fits: a boolean beside a numeric series is 1 or 0 and
  a number or boolean compared with a string series is its string, as
  Python's `str` spells it (`1e-05`, `True`; a tie in the shortest digits
  goes to the even one, as in Python's `repr`); a gregor value keeps its own
  dtype (but `mod` of a float series and a datetime reads the datetime's
  physical integer, as Python does, and a date there is a contract error), a
  duration series divided by a number is Python's true division, a
  non-integer real beside an integer, boolean or string series is Float64,
  and in
  arithmetic a string or symbol is a String constant (`(+ ints "x")` is
  `"1x" "2x"`). Otherwise the operator runs its expression form,
  `(op (col name) (lit v))` on a one-column frame (`series-through-expr`),
  with that form's dtypes, as Python's expressions give them: beside an Enum
  series a string or symbol (`=` with a value outside the categories is
  `#f`, null on a null, and `<` raises polars' reason, as in Python), beside a
  Decimal series a real or a boolean (compared as 1 or 0), beside a
  duration series a number in `*`, a string before a series in `+`, beside
  an integer series an Int64 integer past the dtype's range (`(+ u8 300)`
  is UInt16; a row whose exact result falls outside the result's dtype is
  a contract error naming the value and both dtypes, never a wrapped
  series: in `+`, `-` and `*` read from the series' min and max, in `/`
  with the value on the left when it is the result dtype's minimum and the
  series holds -1, the one quotient that overflows), in `/`
  a negative integer beside an unsigned series (integer division,
  `(/ u8 -1)` is Int16), and beside a Boolean series an
  integer in `/`. `lit` takes an integer from
  2^63 to 2^64 − 1 as `expr_lit_u64`, a dynamic integer that materialises
  as UInt64, as `pl.lit(2**63)` does, and below 2^63 as `expr_lit_i32` /
  `expr_lit_i64`. Such an integer beside a series follows Python's eager
  operators, which raise `OverflowError` past Int64 except beside UInt64
  (where they wrap), beside Decimal and in `/`: it is a constant beside a
  UInt64 series, the expression form beside a Decimal series, and a
  contract error beside any other integer or Boolean series and a Null one
  (Python raises a `TypeError` beside Null), except in `/`, where Python gives
  Float64 (Float64 nulls beside Null) and ours refuses, since its `/` of
  integers is integer division (the `past-int64` deviation); beside a float
  or string series it is what any integer is there, and it is refused
  wherever a smaller integer is. Contract errors naming the value and the series' dtype, where Python
  raises `TypeError`, `ValueError` or
  `OverflowError`: a negative integer beside an unsigned series outside `/`,
  an integer past Int64 beside a series other than those, an integer
  outside −2^63 to 2^64 − 1, which no literal carries, a gregor value
  compared with a series of another kind (a naive datetime beside a date
  series and a date or time beside a string series aside), a time in
  arithmetic, and a value no literal takes. `mod` refuses a temporal series
  (the left one when both are series), as Python's `%` does, whatever the
  other operand. The special cases are one table in `generic/operands.rkt`,
  `operand-rules`, keyed by operator class, dtype class and operand class.
  The result takes the series' name on either side; Python's eager
  operator instead names it `literal` for a plain value left of `+`, `-`,
  `*` or `/` on a Decimal series, left of `*` on a Duration series, and for
  a string left of `+` (the `result-name` class).
  `scripts/operand-audit-expected.py` writes Python's outcome of every
  (operator, dtype, operand) row to `polars/tests/generic/operand-audit.rktd`,
  with the expression form's and, for `/`, `//`'s where they differ.
  `scripts/operand-audit-deviations.rkt` records ours, for each row where it
  differs, in `polars/tests/generic/operand-deviations.rktd`, under the first
  class of `polars/tests/generic/operand-audit-classes.rkt` that holds;
  `operand-audit-table.rkt` beside it reads both records, and the library
  requires none of them. Each class is a predicate on the row, Python's
  outcome (with its expression and `//` forms) and ours, which says what
  kind of outcome the class admits; the record, not the predicate, says
  which rows are in it. The recorder is a ratchet: a row that
  fits no class, or one not already recorded under its class with the same
  outcome (a new deviation, a changed outcome, a changed class), makes it
  print the row, ours and the record and exit 1 without writing. `--accept`
  records the new and changed rows, never an unclassified one. A recorded row
  that now gives Python's outcome counts as changed too, so undoing a
  documented deviation (`integer-division`, `racket-short-circuit`,
  `result-name`) also needs `--accept`, which drops the row from the record.
  `polars/tests/generic/operand-audit.rkt` holds every row to Python's outcome
  or the recorded one, name, dtype and values exactly, and reclassifies every
  recorded row, so a change to any row fails and names it. After a
  deliberate change, rerun the recorder. On an unclassified row, fix ours to
  Python's outcome, or add a class with its predicate and reason (and a
  forged-outcome row in the test that the predicate refuses). On a row not
  recorded, fix ours, or rerun with `--accept` and review the diff of the
  recorded rows and the class counts it prints.
- Eager reductions on a series return what Python 1.42.1's do (owner's
  decision, 2026-10-16; before it the typed paths gave `#f`): `polars-null`
  where the reduction is undefined (`mean`, `min`, `max`, `std`, `var` of an
  empty or all-null series, `std` / `var` below `ddof + 1` values, `mean`
  of a string or categorical series), `sum` 0 for an empty or all-null
  numeric, boolean or duration series, a boolean `sum` the count of `#t`,
  and an error under the verb's name for a `sum` of a string, temporal or
  categorical series and a `std` / `var` of a string, temporal (but a
  duration's `std`) or categorical one. An Int8, Int16, UInt8 or UInt16
  `sum` is an Int64 total, a Float32 `std` / `var` the Float32 value and a
  Decimal reduces as Python's does, all through the expression engine. The
  expectations are `polars/scribblings/data/reductions-expected.rktd`,
  written by `scripts/reductions-expected.py` from Python on empty,
  all-null and partly null series of each dtype;
  `polars/tests/generic/reductions.rkt` reads it. The typed low-level
  `series-sum-i32` and kin still return `#f`.
  A constructor reads its arrays through `slice_or_empty`
  (`rust/src/ffi/slices.rs`): NULL with length 0 is empty, NULL with rows
  is refused.
- `series` infers int64 / float64 / string / bool, `'categorical` from a list
  of symbols, and the temporal dtypes from gregor values (#63): `'date`,
  `'time`, `'(datetime microseconds #f)`, and `'(duration microseconds)` from
  a `period` without years or months (a day is 24 hours). A datetime or period
  that carries nanoseconds makes the column nanoseconds instead, where
  Python's `datetime` stops at microseconds, but only when a nanosecond column
  holds every value (datetimes 1677-09-21 to 2262-04-11, durations under
  2^63 ns); otherwise it stays microseconds and drops the finer part as
  `#:dtype` does, so `(series (list (now) (datetime 1600 1 1)))` builds
  although `(now)` nearly always carries nanoseconds. `#:dtype` drops a finer
  part as a polars cast does: a datetime floors, a duration truncates toward
  zero. A date or datetime outside chrono's years (-262143 to 262142) is
  refused, since polars panics printing one. A `cast` still makes one (#141):
  `ref`, the conversions and the series printer read it as gregor's value
  (`ref` reads a date through the bulk copy, as `series->list` does, so the
  two agree; a zoned series prints without its zone abbreviations when
  polars cannot format them). In a zone other than UTC polars cannot give
  its local clock: `ref` and the conversions raise under their own names
  with polars' reason, and the series printer shows that cell as
  `#<cannot print: ...>`. A frame or an expression that holds one
  prints as `#<dataframe: cannot print: polars panicked: ...>` (or
  `#<expr: ...>`): a custom-write never raises, since an error message that
  shows the value would hide its own error. `display-dataframe`,
  `dataframe->string`, `expr->string`, a `cast` to a string, `pivot` and
  `unpivot` raise under their own names with polars' panic as the reason. `lit`, and so every comparison,
  `is-between` and `is-in`, takes the same values as literals of the same
  dtypes (`expr_lit_temporal`, `expr_lit_datetime_tz`).
- A zoned datetime (#140, polars' `timezones` feature) is the datum
  `'(datetime unit "Zone/Name")`, with an explicit unit; its values are gregor
  `moment`s in the column's zone. `CompatDType`'s has-timezone flag carries no
  name, so the zone crosses as a string through its own exports
  (`series_time_zone_v2`, the `_datetime_tz` cast / selector / literal entry
  points, `series_dt_*` / `expr_dt_*` convert and replace,
  `expr_str_to_datetime_tz`); each that takes a zone canonicalises it with
  polars' `TimeZone::opt_try_new` (`+01:00` becomes `Etc/GMT-1`), validates
  it with `TimeZone::validate_time_zone` (which, unlike `opt_try_new`, ignores
  `POLARS_IGNORE_TIMEZONE_PARSE_ERROR`) and records why it fails;
  `->compat-dtype` refuses a zoned datum. A list of moments settles
  its zone as Python does: the first non-null value decides, a named zone is
  kept, a fixed offset gives UTC, a naive datetime among moments is read as
  UTC, and a list that starts naive makes a naive column of UTC clock times.
  `#:dtype` is the column's dtype outright (a naive one takes each moment's
  UTC clock time), where Python's `pl.Datetime("us")` keeps the values' zone.
  `%z` parses to UTC; on an expression, an offset with no `#:format` and no
  `#:time-zone` is an error, as in Python. Every reading is polars'
  (chrono-tz's compiled database), never tzinfo's: a moment read back is built
  with the offset polars gives, through gregor's private `make-moment` (#172;
  `temporal.rkt` checks at compile time that gregor still provides it). The
  offset is the wall clock `replace_time_zone(None)` gives on a microsecond
  view of the column, less the floored instant: on a nanosecond column polars'
  clock overflows i64, unchecked, within a day of either end of the range
  (1677, 2262), and offsets change on whole seconds, so the floored instant
  has the value's offset. The series printer takes `%Z` from polars. tzinfo,
  behind gregor's own functions, ignores the TZif footer (no daylight saving
  after 2037, or sooner with slim zoneinfo) and some systems lack the
  backward-compatible names (`US/Pacific`). Series operators refuse datetimes
  in different zones before the native call, naming the operator, and `is-in`
  refuses a list whose datetimes differ in zone (or mix naive and zoned), as
  Python's `is_in` does, though `series` builds a column from the same list. A
  zoned CSV schema override is refused (the reader would drop the zone).
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
- `ref` and the bulk conversions (`series->list`, `in-series`, …) return a
  datetime with its column's full precision (#100), as the gregor `datetime`
  of that instant, where Python's `to_list` stops at microseconds; `ref` reads
  the physical value through the bulk copy, so the two cannot disagree. The
  conversions raise on an unsupported dtype, `binary` included (#99), even
  when every entry is null. The series printer shows a binary value as
  Python 1.42.1's series repr does, read through `series_copy_binary` for
  the shown rows only and at most 61 bytes of each value (its
  `max_value_len`; the copy still reports each value's full length): bytes
  `!` to `~` as themselves, any other as `\xNN`, cut after 60 bytes with
  `"…` (Python's `POLARS_FMT_STR_LEN`, doubled, is not read). It is total: a cell that raises prints `#<cannot print:
  ...>`, and a series whose header raises `#<series: cannot print: ...>`
  (#250).
- A regexp given to `col` / `exclude` keeps its Racket meaning:
  `polars/private/column-pattern.rkt` rewrites `#rx` and `#px` syntax into the
  Rust regex crate's, and the oracle test in
  `polars/tests/generic/selectors.rkt` checks the selection against
  `regexp-match?`. It never emits the crate's `(?i`, whose Unicode folding
  differs from Racket's; it expands case-insensitive literals and ranges
  itself. `\p{...}` classes follow each side's Unicode tables, and Racket
  misjudges some classes above U+00FF (#85), so the oracle's names stay out of
  both. Lookaround, backreferences, atomic groups and conditionals, which the
  crate lacks, are rejected by `col` and `exclude`, naming the construct
  (#151).

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
- **Every guide or reference example is a test case.** The PR that adds or
  changes an example adds a test in the module's file under `polars/tests/`
  (or its inline `test` submodule until #256 moves it) asserting the same
  result, or, for an `eval:error`, the failure and its `who:` (#152 will run
  the examples themselves under `raco test`). An `eval:error` shows a failure
  that is the behaviour being documented, with a message that names the
  function the reader called; an example that errors because of a gap, or
  blames an internal binding, is a bug (#151).
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

- **`nix flake check` is the CI-equivalent** (twelve checks: cargo tests, the
  Racket build with docs, tests, guide scripts, examples and bench tests,
  `cargo fmt --check`, the Racket version floor, `no-syntax-rule`,
  `no-inline-tests`, `rustls-only`, `docs-check-test`, `install-native-libs`,
  `devshell-home`, `release-toolchain`, the rustc pin, and `build-so-darwin`,
  `scripts/test-build-so.sh`'s stub test of `build-so.sh darwin`).
  `nix build .#racket` runs only the second and is not enough. It does not
  cover CI's Lint job (`raco test lint` and the Resyntax run).
- nix builds from the **git-tracked tree**: `git add -A` before any nix
  command, or a new file fails with "file not found for module".
- Each worktree gets its own `PLTUSERHOME`, keyed on its root as
  `git rev-parse --show-toplevel` gives it (`scripts/devshell-home.sh`, which
  the dev shell's hook sources), so a trailing slash, a symlink or a
  subdirectory reaches the same home (#158), inside a git hook too, whose
  `GIT_DIR` it ignores. Outside git the key is the
  directory's real path, so a subdirectory has its own. With no home to key
  (`HOME` unset, say) the hook says so in one line and skips the setup. The
  `devshell-home` gate and flake check hold it there. In a fresh
  one, `raco setup --pkgs threading-doc` once, or the manual's `~>` link is an
  undefined tag, which fails the `docs` gate, and `threading-doc` looks unused.
- `scripts/docs-check.sh` (the `docs` gate, and the flake's Racket build) runs
  `raco setup` over `rkt-polars` and fails on an `undefined tag` or a key
  collected `multiple times` in its log, or a `badlink` in the rendered
  manual: `raco setup` and `raco scribble` only warn about these and exit 0.
  It sees the warnings only on a run that renders the manual, so that run
  records them in `polars/doc/polars.docs-check-warnings` (the dev shell's
  setup on entry too, through `--record`, which writes no GitHub Actions
  annotations) and a run that does not reads them back. The record starts
  with a copy of Scribble's build stamp, `stamp.sxref`, which names the
  render's inputs, since a render within the record's second has its mtime.
  With no record, or one whose stamp is not the manual's or that is older
  than `index.html` (a render after a dependency's manual changes, such as
  installing `threading-doc`, keeps the stamp), it deletes `stamp.sxref` and
  renders the manual again. Each run holds
  `polars/doc/polars.docs-check-lock` (a symbolic link naming its pid,
  created by `ln -s`, since macOS has no `flock`) while it renders and
  records, waiting up to `DOCS_CHECK_LOCK_TIMEOUT` seconds for a holder that
  is running, and releases it only while it names its own pid; it removes a
  lock whose pid is not running, which a `SIGKILL` leaves behind, holding
  the lock's `.reap` link meanwhile. `--scan LOG DOC-DIR`
  checks a saved log, and `scripts/docs-check-test.sh` (the `docs-check-test`
  gate, a push gate and a flake check) runs it on the fixtures in
  `scripts/docs-check-fixtures/`.
- After any Rust change: `nix run .#copy-native-libs`, or the Racket tests run
  against the stale library. It and the dev shell's hook copy through
  `scripts/install-native-libs.sh`, which leaves an identical library alone
  and replaces a differing one by a rename, never in place, so a racket in
  another shell that has the old one mapped keeps running (#265); the
  `install-native-libs` gate and flake check hold it there. The
  pre-installer (`polars/private/install-compat.rkt`) does the same on every
  `raco setup`: it writes a replacement at mode `0755`, and an identical
  library keeps its mode (#267).
- The library's module tests live in `polars/tests/`, in the file at the
  module's path under `polars/private/` (`tests/generic/csv.rkt` tests
  `private/generic/csv.rkt`). Three have no library counterpart:
  `generic/csv-options.rkt`, `generic/verb-errors.rkt` and
  `generic/operand-audit.rkt`. No module under `polars/private/` has a `test`
  submodule: the `no-inline-tests` gate (`scripts/no-inline-tests.sh`, a flake
  check and CI's Lint job) fails on one; it is a grep, which a form split
  across lines escapes, and the exact check is a test in
  `polars/tests/resource.rkt` that reads each module as data. The guide's
  `*-test.rkt`, `bench/` and `lint/` keep theirs. A test file is `#lang
  racket/base` whose body is one `(module+ test ...)`, so `raco test -x` runs
  it, with every require in one `require` at its head. That `require` takes
  every project module through `only-in` or `prefix-in`, never bare:
  `(prefix-in contracted: polars/private/<path>)` for the contracted exports,
  `only-in` for the plain ones, and `(only-in (submod polars/private/<path>
  internal) ...)` for a binding the module does not export or a test calls
  uncontracted. The module's last form, `(module+ internal (provide ...))`,
  provides those, only what a test uses; never `require/expose`. The test-only
  helpers, which test no module, live there too: `test-helpers.rkt`,
  `gc-pressure.rkt`, `generic/test-fixtures.rkt` (its `test` submodule holds
  the reader checks), `generic/operand-audit-table.rkt` and
  `generic/operand-audit-classes.rkt`. The `test` blocks of one file
  **merge**: a definition name used in one block collides with the same name
  in another. Rust tests live in `rust/src/tests/`.
- `raco test -x --timeout 600 -c polars` (Racket), `raco test -y user-guide` (the guide's
  paired scripts), `raco test -x bench` (strict mode's comparison),
  `cargo test --manifest-path rust/Cargo.toml` (Rust).
- `raco test -y -e -Q --empty-stdin -j 8 examples` runs every `examples/*.rkt`
  (the `examples` gate, in `push-gates` too; about 12 s). No `-x`: the
  examples have no `test` submodule, so `-x` would run nothing. An example
  is red if it raises, exits non-zero or writes to stderr. The flake's
  Racket check runs it too (`-j 4`), so a broken example fails CI.
- The gates in `.racket-dev.rktd` run all of the above through the
  racket-dev plugin's runner.
- The lint gates are `scripts/no-syntax-rule.sh` and
  `scripts/no-inline-tests.sh` (greps; no shell needed), and
  `scripts/resyntax-lint.sh` (dev shell; `fix` applies what it reports).
  The last runs the project's Resyntax suite, `lint/`: the default
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
- A PR that adds a public export bumps `version` in `polars/info.rkt` (the
  third number; the second for a breaking change), so that a dependent can
  require a polars new enough to have it. Racket's version form has no
  trailing `.0`: `0.1`, `0.1.1`, `0.2`. The repo-root `info.rkt` and
  `flake.nix`'s `version` carry the same string. `rust/Cargo.toml` keeps its
  own, and `flake.nix` reads it for the `rkt-polars-compat` derivation, so a
  Racket-side bump does not rebuild the native library.
- The toolchain (nixpkgs, the release rustc, the manylinux2014 image, the
  crates within the polars minor) moves only in a refresh PR of its own,
  `scripts/refresh-toolchain.sh`, which ends with a candidate refresh
  (`polars/native-libs/BUILDING.md`); a new polars minor is its own leg.
