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
  `deallocator`-wrapped `<type>-drop/raw`, which `<type>-drop` wraps,
  refusing a dropped value, so an explicit drop frees twice (#47). Where the Rust side records no reason, `#:wrap (allocator/or-fail
  <type>-drop 'who)` (`foreign.rkt`) registers the release and raises
  `who: operation failed` itself, so no wrapper is needed. A test in
  `foreign.rkt` reads every `define-compat` under `polars/private` and fails
  on one of these four result types without its allocator, or on a
  `_pointer` result.
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
- Strings from Rust are allocated with `rust_string_to_ptr`, marshalled by the
  `_rsstring` ctype (NULL → `#f`, finalizer frees via `string_drop`).
- **Failure reasons travel out of band** (#45): an entry point that can fail
  calls `clear_last_error()` on entry (the shared `write_frame`,
  `collect_frame` and `scan` helpers do it) and records the **cause alone**; the Racket
  wrapper names the operation and the path. Racket reads it with
  `call/foreign-error`, which makes the call and reads the reason inside one
  `call-as-atomic`: the slot is per OS thread and every Racket thread in a
  place shares one. Only wrap an entry point whose Rust side participates —
  today the `dataframe_read_*` / `dataframe_write_*` IO entry points, the
  `scan_*` family, `lazyframe_collect`, `lazyframe_explain`,
  `dataframe_sort_with_options`, `series_sort_with_options`,
  `series_new_str_packed`, the three Enum entry points (`series_cast_enum`,
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
  `polars panicked: <cause>` as the reason and returns NULL. Today
  `lazyframe_collect`, `lazyframe_explain`, `dataframe_sort_with_options`,
  `series_sort_with_options`, `series_cast_enum`, `series_new_str_packed`,
  the three series time-zone entry points (`series_cast_datetime_tz`,
  `series_dt_convert_time_zone`, `series_dt_replace_time_zone`), the IO
  helpers (`read_frame`, `read_path`, `write_frame`, `scan`) and the JSON entry points
  (`dataframe_read_json_with_options`, `lazyframe_scan_ndjson_with_options`,
  `dataframe_write_ndjson_with_options`) do: 0.41.3 aborted Racket on a
  Parquet Categorical or Decimal column (#93), and a `scan-csv` that reads
  the header (`#:schema-overrides`) aborted it on a compressed file (#177).
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
- **Strings cross into Rust in one allocation, never as `(_list i _string)`.**
  That type turns each element into a fresh byte string and stores its
  address in an array the collector does not trace, so a collection while the
  array fills moves or frees the strings already stored, and Rust reads stale
  memory (#143: wrong values from about 300,000 strings, an abort at a
  million). A string series is the bulk copy in reverse: `series-new-str`
  passes one UTF-8 byte string, row offsets in a `with-raw-buffer` and a
  validity byte string to `series_new_str_packed`, which checks every offset
  against the buffer and a character boundary. The byte strings may move, so
  the binding is never `#:blocking?`. A list of names (`by`, `on`,
  `categories`, ...) is a `_string-list` argument (`resource.rkt`): the
  `const char **` table and every NUL-terminated string share one
  `'atomic-interior` block, which the collector never moves. Its elements are
  what `_string` took: a string (as UTF-8), a byte string, or a path.
  `_string-list` is a `_fun` argument syntax, not a ctype, because a callout
  retains the values it is given and not what a ctype converts them to: as a
  ctype the block could be freed by a collection during a `#:blocking?` call
  or a callback. `series-ref` reads a String value by length, through
  `series_copy_str`, since a C string ends at a NUL the value may hold.
  Categorical and Enum values are still read as C strings, and Enum categories
  cross as one, so `series` refuses a NUL in a categorical or Enum value, and
  `series`, `cast`, `col`, `series-cast`, `expr-cast` and `expr-dtype-col`
  refuse one in an Enum category (`check-enum-categories`); `define-enum`
  refuses it at compile time. Names, single string arguments and categoricals
  cast from a String series still stop at a NUL (#165). A test in
  `resource.rkt` reads every module under `polars/private` as data and fails
  on a pointer-holding ctype (`_string`, `_bytes`, `_path`, `_file`,
  `_symbol`, `_gcpointer`, `_racket`, their `/` and `*` variants, or a name
  `define`d as one, directly or through `make-ctype`) as the element of a
  `_list` / `_vector` / `_ptr` in mode `i` or `io`, of an `_array`,
  `_array/list`, `_array/vector`, `_box` or `_list-struct`, as a
  `define-cstruct` field, or in `define-series-constructors`.
- **A scoped native resource is never paired by hand.** A buffer or owned
  result used only for the length of a computation is bound with
  `with-raw-buffer` or `with-release` (`polars/private/resource.rkt`), which
  expand into `dynamic-wind`, so the release runs on return, raise and
  escape; the buffer's finalizer backs up a thread killed inside the extent.
  No `(malloc …)` or `(free …)` appears outside `resource.rkt`: a test there
  fails on one.
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
  jobs go red on it. Refresh with `scripts/refresh-candidates.sh <PR>` on the
  branch; any other Rust change also reaches catalog users only through a
  refresh. See `polars/native-libs/BUILDING.md`.

## Behavioural facts to know before changing semantics

- `series #:dtype`, `cast` and `series-cast` accept short and canonical
  spellings (`'f64`, `'float64`) (#64); `dtype` returns the canonical one.
- `/` on an integer column is integer division, unlike Python's `/` (#65).
- `read-csv` and `scan-csv`:
  - `read-csv` returns what `(collect (scan-csv ...))` returns for the same
    keywords, as Python's `read_csv` does: `dataframe_read_csv_v2` reads a
    glob pattern by scan and collect, and a single file with 0.55's eager
    `CsvReader`, about three times faster on nycflights. Both are built
    from one decoded request, and a table-driven Rust test holds the eager,
    one-file-glob and scan reads to identical frames and error texts, with
    listed exceptions (a malformed-quote error's chunk locator; an
    `#:n-rows 0` read of a line that does not parse, invalid UTF-8 or a
    ragged line, fails eagerly).
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
  once a schema is given. The eager NDJSON verbs strip the "Resolved plan
  until failure" dump polars appends to a planning error (`without_plan`).
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
  is a Null literal. A series operator given a `'null` series and a plain
  value runs the operator's expression form with the value as a `lit`, so
  the two agree; `lit` has no `polars-null` literal. On a `'null` series
  `sum`, `mean`, `min`, `max`, `std` and `var` give `polars-null` and
  `n-unique` gives 1, as Python 1.42.1 does, through the expression engine
  (the typed `series_sum_*` have no Null case). A `'null` column does not
  vstack or join with a typed one, and `and`, `or`, `xor` and `not` refuse
  a `'null` series, as in Python.
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
  refused, since polars panics printing one. `lit`, and so every comparison,
  `is-between` and `is-in`, takes the same values as literals of the same
  dtypes (`expr_lit_temporal`, `expr_lit_datetime_tz`).
- A zoned datetime (#140, polars' `timezones` feature) is the datum
  `'(datetime unit "Zone/Name")`, with an explicit unit; its values are gregor
  `moment`s in the column's zone. `CompatDType`'s has-timezone flag carries no
  name, so the zone crosses as a string through its own exports
  (`series_time_zone`, the `_datetime_tz` cast / selector / literal entry
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
  when every entry is null.
- A regexp given to `col` / `exclude` keeps its Racket meaning:
  `polars/private/column-pattern.rkt` rewrites `#rx` and `#px` syntax into the
  Rust regex crate's, and the oracle test in `generic/selectors.rkt` checks
  the selection against `regexp-match?`. It never emits the crate's `(?i`,
  whose Unicode folding differs from Racket's; it expands case-insensitive
  literals and ranges itself. `\p{...}` classes follow each side's Unicode
  tables, and Racket misjudges some classes above U+00FF (#85), so the
  oracle's names stay out of both. Lookaround, backreferences, atomic groups
  and conditionals, which the crate lacks, are rejected by `col` and
  `exclude`, naming the construct (#151).

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
  changes an example adds a test in the module's `test` submodule asserting
  the same result, or, for an `eval:error`, the failure and its `who:` (#152
  will run the examples themselves under `raco test`). An `eval:error` shows
  a failure that is the behaviour being documented, with a message that names
  the function the reader called; an example that errors because of a gap,
  or blames an internal binding, is a bug (#151).
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

- **`nix flake check` is the CI-equivalent** (six checks: cargo tests, the
  Racket build with docs, tests, guide scripts, examples and bench tests,
  `cargo fmt --check`, the Racket version floor, `no-syntax-rule`, and
  `release-toolchain`, the rustc pin).
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
