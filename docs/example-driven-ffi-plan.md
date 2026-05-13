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
- Constructors: `series-new-i8` / `-i16` / `-i32` / `-i64` / `-u8` / `-u16` / `-u32` / `-u64` / `-f32` / `-f64` / `-str` / `-bool` / `-ymdhms` (+ Racket gregor wrapper `series-new-datetime`), all accepting `polars-null`
- Value access: `series-ref`, returning typed Racket values or `polars-null`
  (including Gregor values for date/datetime/time and Gregor time-periods for duration)
- Comparisons (scalar RHS): `series-{lt,le,gt,ge,eq,ne}-{i32,f64}`, `series-{eq,ne}-str`
- Comparisons (Series RHS): `series-{lt,le,gt,ge,eq,ne}`
- Arithmetic (Series RHS): `series-{add,sub,mul,div,mod}`
- Arithmetic (scalar RHS): `series-{add,sub,mul,div,mod}-{i32,i64,u32,u64,f64}`
- Boolean ops: `series-and`, `series-or`, `series-xor`, `series-not`, `series-is-null`, `series-is-not-null`
- Reductions: `series-{sum,min,max,mean}-{i8,i16,i32,i64,u8,u16,u32,u64,f32,f64}`, `series-std`, `series-var`, `series-n-unique`
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
- Joins / stack: `dataframe-join` (`#:how 'inner|'left|'outer|'cross|'semi|'anti`, `#:on` or `#:left-on` + `#:right-on`), `dataframe-join-asof` (with `#:by` / `#:left-by` + `#:right-by` and `#:tolerance`), `dataframe-vstack`, `dataframe-hstack`
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
| Series scalar arithmetic | `polars/private/foreign.rkt` | `rust/examples/12_series_scalar_arithmetic.rs` | `examples/26-series-scalar-arithmetic.rkt` | `polars/private/foreign.rkt` |
| Series typed reductions | `polars/private/foreign.rkt` | `rust/examples/13_series_typed_reductions.rs` | `examples/27-series-typed-reductions.rkt` | `polars/private/foreign.rkt` |
| Series temporal refs | `polars/private/foreign.rkt` | `rust/examples/14_series_temporal_refs.rs` | `examples/28-series-temporal-ref.rkt` | `polars/private/foreign.rkt` |
| Series primitive dtypes | `polars/private/foreign.rkt` | `rust/examples/16_series_primitive_dtypes.rs` | `examples/30-series-primitive-dtypes.rkt` | `polars/private/foreign.rkt` |
| DataFrame batch 1 | `polars/private/foreign.rkt` | `rust/examples/05_dataframe_batch1.rs` | `examples/19-dataframe-batch1.rkt` | `polars/private/foreign.rkt` |
| DataFrame batch 2 | `polars/private/foreign.rkt` | `rust/examples/06_dataframe_batch2.rs` | `examples/20-dataframe-batch2.rkt` | `polars/private/foreign.rkt` |
| DataFrame asof options | `polars/private/foreign.rkt` | `rust/examples/15_dataframe_asof_options.rs` | `examples/29-dataframe-asof-options.rkt` | `polars/private/foreign.rkt` |
| Lazy IO batch 1 | `polars/private/expr.rkt` | `rust/examples/07_lazy_io_batch1.rs` | `examples/21-lazy-io-batch1.rkt` | `polars/private/expr.rkt` |
| Lazy scan options batch 1 | `polars/private/expr.rkt` | `rust/examples/11_lazy_scan_options_batch1.rs` | `examples/25-lazy-scan-options-batch1.rkt` | `polars/private/expr.rkt` |
| Expr string batch 1 | `polars/private/expr-str.rkt` via `expr.rkt` | `rust/examples/08_expr_string_batch1.rs` | `examples/22-expr-string-batch1.rkt` | `polars/private/expr.rkt` |
| Expr datetime batch 1 | `polars/private/expr-dt.rkt` via `expr.rkt` | `rust/examples/09_expr_datetime_batch1.rs` | `examples/23-expr-datetime-batch1.rkt` | `polars/private/expr.rkt` |
| Expr string batch 2 | `polars/private/expr-str.rkt` via `expr.rkt` | `rust/examples/10_expr_string_batch2.rs` | `examples/24-expr-string-batch2.rkt` | `polars/private/expr.rkt` |
| Expr string batch 3 | `polars/private/expr-str.rkt` via `expr.rkt` | `rust/examples/17_expr_string_batch3.rs` | `examples/31-expr-string-batch3.rkt` | `polars/private/expr.rkt` |
| Expr string-to-temporal | `polars/private/expr-str.rkt` via `expr.rkt` | `rust/examples/19_expr_string_to_temporal.rs` | `examples/33-expr-string-to-temporal.rkt` | `polars/private/expr.rkt` |
| Expr datetime batch 2 | `polars/private/expr-dt.rkt` via `expr.rkt` | `rust/examples/18_expr_datetime_batch2.rs` | `examples/32-expr-datetime-batch2.rkt` | `polars/private/expr.rkt` |
| Expr when/then | `polars/private/expr.rkt` | `rust/examples/20_expr_when_then.rs` | `examples/34-expr-when-then.rkt` | `polars/private/expr.rkt` |
| Expr null/NaN | `polars/private/expr.rkt` | `rust/examples/21_expr_null_nan.rs` | `examples/35-expr-null-nan.rkt` | `polars/private/expr.rkt` |
| Expr math | `polars/private/expr.rkt` | `rust/examples/22_expr_math.rs` | `examples/36-expr-math.rkt` | `polars/private/expr.rkt` |
| Expr predicates | `polars/private/expr.rkt` | `rust/examples/23_expr_predicates.rs` | `examples/37-expr-predicates.rkt` | `polars/private/expr.rkt` |
| Expr cumulative | `polars/private/expr.rkt` | `rust/examples/24_expr_cumulative.rs` | `examples/38-expr-cumulative.rkt` | `polars/private/expr.rkt` |
| Expr sort/select | `polars/private/expr.rkt` | `rust/examples/25_expr_sort_select.rs` | `examples/39-expr-sort-select.rkt` | `polars/private/expr.rkt` |
| Stabilization batch 1 | `expr-core.rkt`, `expr-str.rkt`, `expr-dt.rkt`, `expr.rkt` | no behavior change | public examples unchanged | direct module load plus `polars/private/expr.rkt` |

Expr / LazyFrame surface (Track A, re-exported from `polars/private/expr.rkt`):
- Leaves: `col`, `lit` (dispatches on Racket type), `expr-lit-{i32,i64,f64,bool,str}`, `expr-alias`
- Arithmetic: `expr-{add,sub,mul,div,mod}` (auto-lift Racket scalars via `->expr`)
- Comparison: `expr-{gt,lt,ge,le,eq,ne}`
- Boolean: `expr-{and,or,xor,not}`
- Unary: `expr-{neg,is-null,is-not-null}`
- Null / NaN: `expr-{drop-nulls,drop-nans,is-nan,is-not-nan,is-finite,is-infinite}`, `expr-fill-null`, `expr-fill-nan` (value auto-lifted via `->expr`), `expr-forward-fill` / `expr-backward-fill` (with `#:limit`)
- Math: `expr-{abs,sign,floor,ceil,sqrt,exp,log1p}`, `expr-round` (`#:decimals`, default 0), `expr-log` (`#:base`, default e), `expr-pow` (exponent auto-lifted), `expr-clip` (`#:lower` / `#:upper`, either may be omitted)
- Membership / distinct: `expr-is-in` (RHS = Expr, Series, or homogeneous Racket list), `expr-lit-series` (Series → literal Expr), `expr-is-between` (`#:closed` `'both|'left|'right|'none`), `expr-{is-unique,is-duplicated,is-first-distinct,is-last-distinct}`
- Cumulative / shift: `expr-{cum-sum,cum-prod,cum-min,cum-max,cum-count}` (each `#:reverse`), `expr-shift` (`#:n`, default 1; `#:fill-value` routes to `shift_and_fill`), `expr-diff` (`#:n`, `#:null-behavior` `'ignore|'drop`)
- Sort / select: `expr-reverse`, `expr-filter` (predicate Expr), `expr-gather` (indices = Expr / Series / int list), `expr-sort-by` (`#:by` string|Expr|list, `#:descending` bool|list), `expr-rank` (`#:method` `'average|'min|'max|'dense|'ordinal`, `#:descending`, `#:seed`), `expr-head` / `expr-tail` (`#:n`, default 10, `#f` = all), `expr-slice` (positional `offset` `length`, i64)
- String namespace: `expr-str-contains`, `expr-str-starts-with`, `expr-str-ends-with`, `expr-str-to-lowercase`, `expr-str-to-uppercase`, `expr-str-replace`, `expr-str-replace-all`, `expr-str-extract`, `expr-str-strip-chars`, `expr-str-strip-chars-start`, `expr-str-strip-chars-end`, `expr-str-strip-prefix`, `expr-str-strip-suffix`, `expr-str-len-bytes`, `expr-str-len-chars`, `expr-str-slice`, `expr-str-head`, `expr-str-tail`, `expr-str-find`, `expr-str-find-literal`, `expr-str-count-matches`, `expr-str-to-date`, `expr-str-to-datetime`, `expr-str-to-time`
- Datetime namespace: `expr-dt-year`, `expr-dt-month`, `expr-dt-day`, `expr-dt-hour`, `expr-dt-minute`, `expr-dt-second`, `expr-dt-iso-year`, `expr-dt-quarter`, `expr-dt-week`, `expr-dt-weekday`, `expr-dt-ordinal-day`, `expr-dt-is-leap-year`, `expr-dt-date`, `expr-dt-time`, `expr-dt-millisecond`, `expr-dt-microsecond`, `expr-dt-nanosecond`, `expr-dt-timestamp`, `expr-dt-strftime`, `expr-dt-truncate`
- Type conversion: `expr-cast` (accepts symbol or `(datetime <unit>)` / `(duration <unit>)`; lifts via `->compat-dtype`)
- Aggregations: `expr-{sum,mean,min,max,count,n-unique,first,last,median}`, `expr-{std,var}` (with `#:ddof`, default 1)
- Conditional: `expr-when` (takes `(list (list pred value) ...)` plus `#:otherwise`; preds/values auto-lifted via `->expr`; lowered as chained `when().then()...otherwise()`)
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

## Deferred / queued work (single source of truth)

Everything below is intentionally NOT done yet. This is the consolidated
backlog — other "next planned" notes in this file just point here.

Next up (small, self-contained):
- `prop:custom-write` REPL pretty-print pass: make `DataFrame` /
  `Series` / `LazyFrame` print via `dataframe->string` (and add
  `series->string` / `lazyframe->string` if missing) at the REPL. Pure
  Racket-side, no Rust changes. (This was "Batch N+7" in the Expr-wave
  plan.)

Expr / lazy DSL:
- More `.str` ops: `split`, `pad_start` / `zfill`, `json_decode`,
  `concat`, `reverse`, `to_titlecase` ("string batch 4").
- More `.dt` ops: `offset_by`, `month_start` / `month_end`, `dt.round`,
  `combine`, time-zone ops, duration `total_*`.
- `.list` / `.arr` and `.struct` namespaces — blocked on the nested
  dtype payload ABI work below.
- `top_k` / `bottom_k`: the polars `top_k` feature drags in
  `polars-ops` code that needs `dtype-decimal`, and enabling
  `dtype-decimal` adds a `DataType::Decimal` variant that must be
  threaded through `compat_dtype_from_polars` / `polars_dtype_from_compat`.
  Do that dtype work first (or accept the cost) before adding these.
- Expression name namespace: `name.suffix` / `name.prefix` / `name.map`
  / `name.to_uppercase` etc. — handy for bulk-renaming derived columns.
- Schema / projection scan options for `scan_csv` / `scan_parquet`.

Series:
- Scalar arithmetic and scalar comparisons for the remaining
  integer/float widths.

Cross-cutting / post-MVP:
- Nested dtype payloads in the dtype descriptor ABI so `list`, `array`,
  and `struct` preserve inner-dtype info instead of surfacing TODO
  placeholders. Also unblocks the `.list` / `.struct` namespaces and
  makes `dtype-decimal` (hence `top_k`) tractable.
- Explicit conversion helpers between Gregor values (Racket) and
  `chrono::NaiveDate` / `NaiveDateTime` (Rust).

Rust-side test coverage (R1–R9, see
`~/.claude/plans/consult-our-plan-for-wild-babbage.md`): the Rust crate
currently lags the Racket-side surface in unit coverage. Plan grows
`#[cfg(test)] mod tests` in `rust/src/lib.rs` in nine small batches that
mirror the FFI batches.
- R1 — test helpers + ABI round trips: **shipped** (`mod test_util`,
  `mod abi`, `mod test_util_smoke`; 25 new tests; `cargo test --release`
  → 64 passed)
- R2 — Series constructors + value access
- R3 — Series ops (cmp / arith / bool / reductions / reshape / cast)
- R4 — DataFrame core
- R5 — DataFrame group-by + joins + reshape + IO (needs `tempfile` in
  `[dev-dependencies]`)
- R6 — Expr core + lazy plumbing
- R7 — Expr behavior batches (the work T3 added; verifies enum-byte
  mappings, `expr_when_then` lowering, `expr_clip` routing, etc.)
- R8 — Expr `.str` / `.dt` namespaces
- R9 — LazyFrame surface (incl. scan options)

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

Series scalar arithmetic is shipped:
- `series-{add,sub,mul,div,mod}-{i32,i64,u32,u64,f64}`

Series typed reductions are shipped:
- `series-{sum,min,max,mean}-{i64,u32,u64}` in addition to the existing `i32` / `f64` reductions

Series primitive dtypes are shipped:
- Constructors and `/vec` variants for `series-new-{i8,i16,u8,u16,f32}`
- `series-ref`, `series-dtype`, `series-cast`, and typed reductions for `int8`, `int16`, `uint8`, `uint16`, and `float32`

Series temporal refs are shipped:
- `series-ref` returns Gregor `date` values for Polars `Date`
- `series-ref` returns Gregor time values for Polars `Time`
- `series-ref` returns Gregor time-period values for Polars `Duration`

DataFrame batch 1 is shipped:
- `dataframe-hstack`
- Parquet roundtrip
- JSON Lines roundtrip
- semi / anti joins

DataFrame batch 2 is shipped:
- `dataframe-join-asof`
- `dataframe-pivot`
- `dataframe-unpivot`

DataFrame asof options are shipped:
- `dataframe-join-asof` accepts `#:by` or `#:left-by` / `#:right-by`
- `dataframe-join-asof` accepts numeric `#:tolerance` in the key column's units

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

Expr string batch 3 is shipped:
- `expr-str-len-bytes`
- `expr-str-len-chars`
- `expr-str-slice`
- `expr-str-head`
- `expr-str-tail`
- `expr-str-find`
- `expr-str-find-literal`
- `expr-str-count-matches`

Expr string-to-temporal is shipped:
- `expr-str-to-date`
- `expr-str-to-datetime`
- `expr-str-to-time`
- Parsing wrappers accept `#:format`, `#:strict`, `#:exact`, and `#:cache`.
  `expr-str-to-datetime` also accepts `#:unit` (`'nanoseconds`,
  `'microseconds`, or `'milliseconds`).

Expr datetime batch 1 is shipped:
- `expr-dt-year`
- `expr-dt-month`
- `expr-dt-day`
- `expr-dt-hour`
- `expr-dt-minute`
- `expr-dt-second`

Expr datetime batch 2 is shipped:
- `expr-dt-iso-year`
- `expr-dt-quarter`
- `expr-dt-week`
- `expr-dt-weekday`
- `expr-dt-ordinal-day`
- `expr-dt-is-leap-year`
- `expr-dt-date`
- `expr-dt-time`
- `expr-dt-millisecond`
- `expr-dt-microsecond`
- `expr-dt-nanosecond`
- `expr-dt-timestamp`
- `expr-dt-strftime`
- `expr-dt-truncate`

Stabilization batch 1 is shipped:
- `polars/private/expr-core.rkt` owns shared Expr/LazyFrame FFI setup
- `polars/private/expr-str.rkt` owns string namespace wrappers
- `polars/private/expr-dt.rkt` owns datetime namespace wrappers
- `polars/private/expr.rkt` remains the public aggregation point for `(require polars)`

Expr when/then is shipped:
- `expr-when` builds chained `when().then()...otherwise()` from a list
  of `(list pred value)` clauses plus `#:otherwise`. The flat FFI
  (`expr_when_then`: parallel `conds` / `vals` arrays + `otherwise`)
  lowers it as nested
  `when(c0).then(v0).otherwise(when(c1).then(v1).otherwise(...)))`,
  so no `When` / `Then` builder pointers cross the FFI.

Expr null/NaN is shipped:
- `expr-drop-nulls` / `expr-drop-nans`, `expr-is-nan` / `expr-is-not-nan`,
  `expr-is-finite` / `expr-is-infinite` (`expr_unop!`)
- `expr-fill-null` / `expr-fill-nan` (`expr_binop!`; Racket value auto-lifted)
- `expr-forward-fill` / `expr-backward-fill` (`#:limit`; FFI takes
  `has_limit: u8` + `limit: u32` since `forward_fill` wants `Option<u32>`)

Expr math is shipped:
- `expr-abs` / `expr-sign` / `expr-floor` / `expr-ceil` / `expr-sqrt` /
  `expr-exp` / `expr-log1p` (`expr_unop!`)
- `expr-round` (`#:decimals`; new `expr_unop_u32!` macro), `expr-log`
  (`#:base`, `f64` extern), `expr-pow` (`expr_binop!`, exponent lifted),
  `expr-clip` (`#:lower` / `#:upper`; FFI `expr_clip(e, has_min, min,
  has_max, max)` routes to `clip` / `clip_min` / `clip_max`)
- Cargo.toml: added the `abs`, `round_series`, `sign`, `log` polars
  features (there is no `pow` feature — `Expr::pow` is always available)

Expr predicates is shipped:
- `expr-lit-series` (`expr_lit_series`: clone a Series into a literal Expr)
- `expr-is-in` (`expr_binop!`; Racket RHS may be an Expr, a Series, or a
  homogeneous list of ints/reals/strings/booleans, sniffed into a Series)
- `expr-is-unique` / `expr-is-duplicated` / `expr-is-first-distinct` /
  `expr-is-last-distinct` (`expr_unop!`)
- `expr-is-between` (`#:closed`; FFI `expr_is_between(e, lo, hi, closed: u8)`
  mapping 0/1/2/3 → `ClosedInterval::{Both,Left,Right,None}`)
- Cargo.toml: added `is_in`, `is_unique`, `is_first_distinct`,
  `is_last_distinct`, `is_between` polars features

Expr cumulative is shipped:
- `expr-cum-sum` / `expr-cum-prod` / `expr-cum-min` / `expr-cum-max` /
  `expr-cum-count` (each `#:reverse`; FFI is the `_uint8` reverse flag,
  built with a small `define-cum` Racket macro that passes the explicit
  `/raw` binding name + c-id since `define-syntax-rule` can't splice ids)
- `expr-shift` (`#:n`; `#:fill-value` switches to `expr_shift_and_fill`)
- `expr-diff` (`#:n`, `#:null-behavior`; FFI `expr_diff(e, n: i64, nb: u8)`
  → `polars::series::ops::NullBehavior::{Ignore,Drop}`)
- Cargo.toml: added `cum_agg` and `diff` polars features

Expr sort/select is shipped:
- `expr-reverse` (`expr_unop!`), `expr-filter` / `expr-gather` (`expr_binop!`;
  `expr-gather` reuses `->membership-expr` so an int list becomes an i64
  index Series)
- `expr-sort-by` (`expr_sort_by`: parallel `by` Expr array + `descending`
  u8 array; uses `SortMultipleOptions::default().with_order_descending_multi`)
- `expr-rank` (`expr_rank(e, method: u8, descending: u8, has_seed: u8,
  seed: u64)` → `RankOptions { method, descending }`; method 0..4 →
  `RankMethod::{Average,Min,Max,Dense,Ordinal}`)
- `expr-head` / `expr-tail` (`expr_head` / `expr_tail` take `has_len: u8`
  + `len: usize` since `Expr::head` wants `Option<usize>`), `expr-slice`
  (`expr_slice(e, offset: i64, length: i64)`)
- Cargo.toml: added the `rank` polars feature. `top_k` / `bottom_k` were
  intentionally **deferred**: the `top_k` feature pulls `polars-ops` code
  that needs `dtype-decimal`, and enabling `dtype-decimal` adds a
  `DataType::Decimal` variant we'd have to thread through
  `compat_dtype_from_polars` / `polars_dtype_from_compat` — out of scope
  for this batch.

Reminders: length-changing Expr ops (`filter`, `gather`, `head`, `tail`,
`slice`, `sort_by` of mixed lengths) must go through `select` /
`dataframe-select-exprs`, and every column produced in a single `select`
must end up the same length — see `examples/39-expr-sort-select.rkt`.

For everything still outstanding (the `prop:custom-write` pass, more
`.str` / `.dt`, `.list` / `.struct`, `top_k` / `bottom_k`, nested dtype
ABI, scan options, etc.) see the consolidated **"Deferred / queued work
(single source of truth)"** section above — that is the canonical
backlog.

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

See the consolidated **"Deferred / queued work (single source of truth)"**
section near the top of this file. (Racket-side temporal values are now
`gregor` — that earlier TODO is done.)

## Review Method

When reviewing Rust code for a new feature, check:

- ownership and drop rules for returned pointers
- behavior on null pointers
- shape and dtype invariants
- whether the exported function is eager and easy to mirror in Racket
- whether the example requires more generic API than we actually want to commit to
