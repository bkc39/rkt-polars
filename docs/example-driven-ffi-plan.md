# Example-Driven FFI Plan

This project should grow the Racket API by reproducing small, concrete Polars programs in Rust first, then exposing only the FFI needed to match those programs in Racket.

## Current State

The four-example sequence is complete and the Series API has been
filled out via a five-phase expansion plan.

Series surface (Racket-side names):
- Lifecycle: `series-empty`, `series-drop`
- Metadata: `series-name`, `series-rename`, `series-len`, `series-null-count`, `series-dtype`
- Constructors: `series-new-i32` / `-i64` / `-u32` / `-u64` / `-f64` / `-str` / `-bool` / `-ymdhms` (+ Racket gregor wrapper `series-new-datetime`)
- Comparisons (scalar RHS): `series-{lt,le,gt,ge,eq,ne}-{i32,f64}`, `series-{eq,ne}-str`
- Boolean ops: `series-and`, `series-or`, `series-xor`, `series-not`, `series-is-null`, `series-is-not-null`
- Reductions: `series-{sum,min,max,mean}-i32`, `series-{sum,min,max,mean}-f64`, `series-n-unique`
- Reshaping: `series-head`, `series-tail`, `series-slice`, `series-reverse`, `series-drop-nulls`, `series-unique`, `series-sort` (with `#:descending`)

DataFrame surface (Racket-side names):
- Lifecycle: `dataframe-make`, `dataframe-empty`, `dataframe-drop`
- Construction: `dataframe-new`
- Metadata: `dataframe-shape`, `dataframe-height`, `dataframe-width`
- Column access: `dataframe-column-name`, `dataframe-column`
- Eager ops: `dataframe-filter`, `dataframe-sort` (with `#:descending`), `dataframe-group-by-sum` (with `#:by` / `#:agg`)
- IO: `dataframe-write-csv`, `dataframe-read-csv`
- Display: `dataframe->string`, `display-dataframe`

Notable remaining gaps:
- Series-side: element access (`series-ref`), series-series comparisons, element-wise arithmetic, type casting, additional reductions (std/var/median), null-aware constructors
- DataFrame-side: more aggregations beyond `sum`, joins, additional IO formats
- Cross-cutting: nested dtype payloads still surface as TODO placeholders; no `prop:custom-write` wrapper yet so dataframes don't auto-pretty-print at the REPL

## Development Rule

For each new capability:

1. Write or adopt a tiny Rust example that demonstrates the feature.
2. Run the example directly in Rust.
3. Add the minimum FFI surface needed to reproduce the behavior in Racket.
4. Add Racket tests or example code that mirrors the Rust behavior.

Avoid designing a large generic FFI before there is an example that requires it.

## Example Sequence

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

## Likely Next Bindings

Recommended near-term order:

1. Bind missing existing exports in Racket:
   - `series-null-count`
   - `dataframe-empty`
2. Add series introspection:
   - `series-dtype`
3. Add dataframe construction and basic inspection:
   - `dataframe-new`
   - `dataframe-height`
   - `dataframe-width`
   - `dataframe-column`
4. Add CSV IO:
   - `dataframe-read-csv`
   - `dataframe-write-csv`
5. Add basic eager dataframe transforms:
   - filter
   - sort
   - group-by + simple aggregations

## Review Method

When reviewing Rust code for a new feature, check:

- ownership and drop rules for returned pointers
- behavior on null pointers
- shape and dtype invariants
- whether the exported function is eager and easy to mirror in Racket
- whether the example requires more generic API than we actually want to commit to
