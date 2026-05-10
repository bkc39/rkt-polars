# Example-Driven FFI Plan

This project should grow the Racket API by reproducing small, concrete Polars programs in Rust first, then exposing only the FFI needed to match those programs in Racket.

## Current State

The four-example sequence is complete, the Series and eager DataFrame
APIs are filled out, and the Expr / LazyFrame DSL has been built up
through Phase A10 (see "Continuing in a new session" below for what's
shipped vs. queued).

Series surface (Racket-side names):
- Lifecycle: `series-empty`, `series-drop`
- Metadata: `series-name`, `series-rename`, `series-len`, `series-null-count`, `series-dtype`
- Constructors: `series-new-i32` / `-i64` / `-u32` / `-u64` / `-f64` / `-str` / `-bool` / `-ymdhms` (+ Racket gregor wrapper `series-new-datetime`), all accepting `polars-null`
- Value access: `series-ref`, returning typed Racket values or `polars-null`
- Comparisons (scalar RHS): `series-{lt,le,gt,ge,eq,ne}-{i32,f64}`, `series-{eq,ne}-str`
- Comparisons (Series RHS): `series-{lt,le,gt,ge,eq,ne}`
- Arithmetic (Series RHS): `series-{add,sub,mul,div,mod}`
- Boolean ops: `series-and`, `series-or`, `series-xor`, `series-not`, `series-is-null`, `series-is-not-null`
- Reductions: `series-{sum,min,max,mean}-i32`, `series-{sum,min,max,mean}-f64`, `series-std`, `series-var`, `series-n-unique`
- Type conversion: `series-cast` (accepts symbol or `(datetime <unit>)` / `(duration <unit>)`)
- Reshaping: `series-head`, `series-tail`, `series-slice`, `series-reverse`, `series-drop-nulls`, `series-unique`, `series-sort` (with `#:descending`)

DataFrame surface (Racket-side names):
- Lifecycle: `dataframe-make`, `dataframe-empty`, `dataframe-drop`
- Construction: `dataframe-new`
- Metadata: `dataframe-shape`, `dataframe-height`, `dataframe-width`, `dataframe-column-names`
- Column access: `dataframe-column-name`, `dataframe-column`
- Row reshaping: `dataframe-head`, `dataframe-tail`, `dataframe-slice`
- Column ops: `dataframe-select`, `dataframe-drop-columns`, `dataframe-rename`, `dataframe-with-column`
- Eager ops: `dataframe-filter`, `dataframe-sort` (with `#:descending`)
- Group-by: `dataframe-group-by-{sum,mean,min,max,count}` (with `#:by` / `#:agg`)
- Dedup / null cleanup: `dataframe-unique`, `dataframe-drop-nulls`
- Joins / stack: `dataframe-join` (`#:how 'inner|'left|'outer|'cross|'semi|'anti`, `#:on` or `#:left-on` + `#:right-on`), `dataframe-join-asof`, `dataframe-vstack`, `dataframe-hstack`
- Reshaping: `dataframe-pivot`, `dataframe-unpivot`
- IO: `dataframe-write-csv`, `dataframe-read-csv`, `dataframe-write-parquet`, `dataframe-read-parquet`, `dataframe-write-json-lines`, `dataframe-read-json-lines`
- Display: `dataframe->string`, `display-dataframe`

The public low-level API is exported from `(require polars)`. The
`polars/private/*` modules remain implementation modules; examples
should require `polars` unless they are specifically testing internals.
That low-level API should stay stable, explicit, function-first, and
frame-first: `DataFrame`, `LazyFrame`, or `Series` arguments remain the
first argument so code works naturally with Racket threading macros.

## Batch Coverage Index

| Batch | Racket module(s) | Rust example | Racket example | Racket tests |
| --- | --- | --- | --- | --- |
| Series batch 2 | `polars/private/foreign.rkt` | n/a | `examples/18-series-batch2.rkt` | `polars/private/foreign.rkt` |
| DataFrame batch 1 | `polars/private/foreign.rkt` | `rust/examples/05_dataframe_batch1.rs` | `examples/19-dataframe-batch1.rkt` | `polars/private/foreign.rkt` |
| DataFrame batch 2 | `polars/private/foreign.rkt` | `rust/examples/06_dataframe_batch2.rs` | `examples/20-dataframe-batch2.rkt` | `polars/private/foreign.rkt` |
| Lazy IO batch 1 | `polars/private/expr.rkt` | `rust/examples/07_lazy_io_batch1.rs` | `examples/21-lazy-io-batch1.rkt` | `polars/private/expr.rkt` |
| Lazy scan options batch 1 | `polars/private/expr.rkt` | `rust/examples/11_lazy_scan_options_batch1.rs` | `examples/25-lazy-scan-options-batch1.rkt` | `polars/private/expr.rkt` |
| Expr string batch 1 | `polars/private/expr-str.rkt` via `expr.rkt` | `rust/examples/08_expr_string_batch1.rs` | `examples/22-expr-string-batch1.rkt` | `polars/private/expr.rkt` |
| Expr datetime batch 1 | `polars/private/expr-dt.rkt` via `expr.rkt` | `rust/examples/09_expr_datetime_batch1.rs` | `examples/23-expr-datetime-batch1.rkt` | `polars/private/expr.rkt` |
| Expr string batch 2 | `polars/private/expr-str.rkt` via `expr.rkt` | `rust/examples/10_expr_string_batch2.rs` | `examples/24-expr-string-batch2.rkt` | `polars/private/expr.rkt` |
| Stabilization batch 1 | `expr-core.rkt`, `expr-str.rkt`, `expr-dt.rkt`, `expr.rkt` | no behavior change | public examples unchanged | direct module load plus `polars/private/expr.rkt` |

Expr / LazyFrame surface (Track A, re-exported from `polars/private/expr.rkt`):
- Leaves: `col`, `lit` (dispatches on Racket type), `expr-lit-{i32,i64,f64,bool,str}`, `expr-alias`
- Arithmetic: `expr-{add,sub,mul,div,mod}` (auto-lift Racket scalars via `->expr`)
- Comparison: `expr-{gt,lt,ge,le,eq,ne}`
- Boolean: `expr-{and,or,xor,not}`
- Unary: `expr-{neg,is-null,is-not-null}`
- String namespace: `expr-str-contains`, `expr-str-starts-with`, `expr-str-ends-with`, `expr-str-to-lowercase`, `expr-str-to-uppercase`, `expr-str-replace`, `expr-str-replace-all`, `expr-str-extract`, `expr-str-strip-chars`, `expr-str-strip-chars-start`, `expr-str-strip-chars-end`, `expr-str-strip-prefix`, `expr-str-strip-suffix`
- Datetime namespace: `expr-dt-year`, `expr-dt-month`, `expr-dt-day`, `expr-dt-hour`, `expr-dt-minute`, `expr-dt-second`
- Type conversion: `expr-cast` (accepts symbol or `(datetime <unit>)` / `(duration <unit>)`; lifts via `->compat-dtype`)
- Aggregations: `expr-{sum,mean,min,max,count,n-unique,first,last,median}`, `expr-{std,var}` (with `#:ddof`, default 1)
- Window / sort: `expr-over` (string keys auto-lifted via `->key-expr`), `expr-sort` (with `#:descending`)
- LazyFrame plumbing: `dataframe-lazy`, `lazyframe-with-columns`, `lazyframe-select`, `lazyframe-filter`, `lazyframe-group-by-agg`, `lazyframe-sort` (with `#:descending`), `lazyframe-unique`, `lazyframe-drop-nulls`, `lazyframe-{head,tail,slice}`, `lazyframe-join` (`#:how`, `#:on` or `#:left-on`/`#:right-on`), `lazyframe-collect`
- Lazy IO: `lazyframe-scan-csv` (with `#:has-header`, `#:separator`, `#:skip-rows`, `#:n-rows`), `lazyframe-scan-parquet` (with `#:n-rows`)
- Eager wrappers: `dataframe-with-columns`, `dataframe-select-exprs`, `dataframe-filter-expr`, `dataframe-group-by-agg`, `dataframe-sort-exprs`

The namespace-specific Expr bindings are split into leaf modules:
- `polars/private/expr-core.rkt`: shared Expr/LazyFrame pointer types,
  `define-compat`, scalar literals, `col`, `lit`, and `->expr`
- `polars/private/expr-str.rkt`: `expr-str-*`
- `polars/private/expr-dt.rkt`: `expr-dt-*`

Group-by remains exposed as fused operations such as
`lazyframe-group-by-agg` and `dataframe-group-by-agg`. Do not expose
Rust-backed eager `GroupBy` or `LazyGroupBy` pointers from `(require
polars)` for now: Rust-side group-by ownership is awkward across FFI,
and long query chains do not need those intermediate objects. A future
`polars/dsl` convenience layer can use ordinary Racket structs for
group-by builders and lower them back to the fused calls.

Examples covering the lazy DSL: `examples/11-expr-with-columns.rkt`,
`examples/12-lazy-group-by.rkt`, `examples/13-lazy-pipeline.rkt`
(filter → group_by_agg → sort, all in one lazy plan),
`examples/14-lazy-head-tail-slice.rkt` (lazy slicing without
intermediate `.collect()`),
`examples/15-lazy-join.rkt` (join → group_by_agg → sort in one
lazy plan, plus `#:left-on`/`#:right-on` and `'cross`),
`examples/16-expr-cast.rkt` (numeric/string casts inside
with_columns, plus i64 → datetime),
`examples/17-expr-std-var.rkt` (sample vs population std/var via
`#:ddof`, both at top-level and inside group_by_agg),
`examples/22-expr-string-batch1.rkt` (first string namespace batch),
`examples/23-expr-datetime-batch1.rkt` (first datetime namespace
batch), and `examples/24-expr-string-batch2.rkt` (string cleanup,
replacement, and regex extraction).

Rust mirror status: `rust/examples/01_*.rs` through
`rust/examples/04_*.rs` are the Rust proof examples. The Racket
examples 11-17 are Racket-only regression examples for the FFI layer;
their Polars behavior is covered by the Rust library tests and the
Racket examples/tests rather than one mirror Rust file per wrapper.

Notable remaining gaps:
- Series-side: scalar arithmetic, typed reductions for additional integer/float widths
- DataFrame-side: richer asof joins with by-groups/tolerance
- Expr / lazy: richer dt.* and str.* operations, schema/projection scan options
- Cross-cutting: nested dtype payloads still surface as TODO placeholders; no `prop:custom-write` wrapper yet so dataframes don't auto-pretty-print at the REPL

## Build / Iteration Loop

End-to-end rebuild during dev:

```
cd rust && cargo build --release
cp target/release/libcompat.dylib ../polars/native-libs/
otool -D ../polars/native-libs/libcompat.dylib
cd .. && raco test -x -c polars
```

`rust/.cargo/config.toml` sets the dylib's `LC_ID_DYLIB` to
`@rpath/libcompat.dylib` on darwin (both aarch64 and x86_64). Without
that, cargo bakes in the absolute build-tree path, and copying the
dylib to `polars/native-libs/` and `dlopen`ing it from the new location
crashes at load (Racket exits 137 with no output). Nix's fixupPhase
handles this for `nix build`; the cargo config makes the same fix
apply to plain `cargo build` outside Nix. If you ever see
`raco test` exit 137 with the test runner header but no test count,
suspect a stale dylib whose install_name is wrong — `otool -D
polars/native-libs/libcompat.dylib` should print `@rpath/libcompat.dylib`.

## Continuing in a new session

Phase A1-A10 of the Expr / LazyFrame DSL are shipped; 346 tests passed
at the time String batch 2 shipped. The next work should harden the
public low-level API before adding more Expr namespaces or any
high-level Racket DSL.

Series batch 1 is shipped:
- `polars-null`
- null-aware constructors
- `series-ref` as the standard value assertion helper

Series batch 2 is shipped:
- `series-cast`
- `series-std` / `series-var`
- series-series comparisons
- element-wise arithmetic

DataFrame batch 1 is shipped:
- `dataframe-hstack`
- Parquet roundtrip
- JSON Lines roundtrip
- semi / anti joins

DataFrame batch 2 is shipped:
- `dataframe-join-asof`
- `dataframe-pivot`
- `dataframe-unpivot`

Lazy IO batch 1 is shipped:
- `lazyframe-scan-csv`
- `lazyframe-scan-parquet`

Lazy scan options batch 1 is shipped:
- `lazyframe-scan-csv` accepts `#:has-header`, `#:separator`, `#:skip-rows`, `#:n-rows`
- `lazyframe-scan-parquet` accepts `#:n-rows`

Expr string batch 1 is shipped:
- `expr-str-contains`
- `expr-str-starts-with`
- `expr-str-ends-with`
- `expr-str-to-lowercase`
- `expr-str-to-uppercase`

Expr string batch 2 is shipped:
- `expr-str-replace`
- `expr-str-replace-all`
- `expr-str-extract`
- `expr-str-strip-chars`
- `expr-str-strip-chars-start`
- `expr-str-strip-chars-end`
- `expr-str-strip-prefix`
- `expr-str-strip-suffix`

Expr datetime batch 1 is shipped:
- `expr-dt-year`
- `expr-dt-month`
- `expr-dt-day`
- `expr-dt-hour`
- `expr-dt-minute`
- `expr-dt-second`

Stabilization batch 1 is shipped:
- `polars/private/expr-core.rkt` owns shared Expr/LazyFrame FFI setup
- `polars/private/expr-str.rkt` owns string namespace wrappers
- `polars/private/expr-dt.rkt` owns datetime namespace wrappers
- `polars/private/expr.rkt` remains the public aggregation point for `(require polars)`

Candidate Series follow-up work:
- scalar arithmetic wrappers
- typed reductions for additional integer/float widths
- richer `series-ref` support for date, duration, time, and nested dtypes

Near-term DataFrame targets:
- asof join `#:by` groups and tolerance

Expr / LazyFrame work after the low-level surface has public examples
and tests:
- more `expr-str-*` operations: lengths, slicing, find/count, split
- more `expr-dt-*` operations: week, weekday, ordinal day, truncate
- schema/projection scan options for CSV / Parquet

Keep any high-level Racket DSL in a later `polars/dsl` track. Do not
make `(require polars)` grow a new high-level query language until core
Series/DataFrame workflows have public low-level examples and tests.

A8 surprise worth remembering: `LazyFrame::cross_join` is gated by the
polars `cross_join` feature (now enabled in `rust/Cargo.toml`).
Without it, falling back to `join_builder` + `JoinType::Cross` with
empty key vecs panics inside `arg_sort_multiple` during collect — so
prefer the dedicated method when adding new join variants.

A9 design note: `expr-cast` reuses the existing `CompatDType` cstruct
(input mirror of `series-dtype` output). The Racket-side
`->compat-dtype` lifts symbols (`'int64`, `'float64`, `'string`, ...)
and `(datetime <unit>)` / `(duration <unit>)` lists into the cstruct.
List/Array/Struct/Decimal/Categorical/Enum tags are accepted on
*output* but not on *input* — `polars_dtype_from_compat` returns None
and the Racket wrapper raises rather than panics. When future phases
need typed scan_csv overrides or `lit`-with-dtype, lean on
`->compat-dtype` rather than introducing a parallel descriptor.

A10 added an `expr_unop_u8!` macro alongside `expr_unop!` for
externs that take a single `u8` extra arg. `expr-std`/`expr-var`
default `#:ddof` to 1 (sample), matching polars and pandas. Use the
same macro shape if any future Expr unop needs a small fixed-size
extra arg.

When `str.*` / `dt.*` work resumes, extend
`polars/private/expr-str.rkt` and `polars/private/expr-dt.rkt` instead
of growing `expr.rkt`.

## Development Rule

For each new capability:

1. Write or adopt a tiny Rust example that demonstrates the feature.
2. Run the example directly in Rust.
3. Add the minimum FFI surface needed to reproduce the behavior in Racket.
4. Add Racket tests or example code that mirrors the Rust behavior.

Avoid designing a large generic FFI before there is an example that requires it.

## Example Sequence (historical)

The four examples below are the original "minimal Rust example, then
mirror in Racket" seed; they are all shipped (`examples/01-…` through
`examples/04-…` in Racket, plus the corresponding `rust/examples/`
files). Kept here so newcomers can see the original scope sketch — do
not treat any of this as outstanding work.

### 1. Series Basics

Rust example: `rust/examples/01_series_basics.rs`

Goals:

- construct integer, float, string, and datetime series
- inspect name, length, dtype, null count
- rename a series
- compute simple reductions

FFI likely needed:

- `series-null-count`
- `series-dtype`
- numeric reductions such as `series-sum-i32`, `series-sum-f64`, `series-mean-f64`

### 2. DataFrame From Series

Rust example: `rust/examples/02_dataframe_from_series.rs`

Goals:

- construct a dataframe from several series
- inspect shape, columns, schema
- fetch a column back out by name

FFI likely needed:

- `dataframe-new`
- `dataframe-height`
- `dataframe-width`
- `dataframe-column-count`
- `dataframe-column-name`
- `dataframe-column`

### 3. DataFrame Operations

Rust example: `rust/examples/03_dataframe_ops.rs`

Goals:

- filter rows by a boolean mask
- sort by one or more columns
- group by a key and aggregate a numeric column

FFI likely needed:

- series boolean comparison ops or dataframe column predicate helpers
- `dataframe-filter`
- `dataframe-sort`
- `dataframe-group-by-sum`

Keep this eager and minimal before considering a lazy/expression API.

### 4. CSV Round Trip

Rust example: `rust/examples/04_csv_roundtrip.rs`

Goals:

- write a dataframe to CSV
- read the CSV back
- verify shape, names, and representative values

FFI likely needed:

- `dataframe-write-csv`
- `dataframe-read-csv`

## TODO

- Add nested dtype support to the dtype descriptor ABI so `list`, `array`, and `struct`
  can preserve inner dtype information instead of surfacing TODO placeholders.
- Represent temporal values on the Racket side with `gregor`.
- Add explicit conversion helpers between Gregor values in Racket and
  `chrono::NaiveDate` / `chrono::NaiveDateTime` in Rust.

## Review Method

When reviewing Rust code for a new feature, check:

- ownership and drop rules for returned pointers
- behavior on null pointers
- shape and dtype invariants
- whether the exported function is eager and easy to mirror in Racket
- whether the example requires more generic API than we actually want to commit to
