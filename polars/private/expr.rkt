#lang racket/base

(require (except-in polars/private/expr-core lazyframe-explain)
         polars/private/expr-dt
         polars/private/expr-ops
         polars/private/expr-select
         polars/private/expr-str
         polars/private/lazyframe)

(provide _Expr-ptr Expr-ptr?
         _LazyFrame-ptr LazyFrame-ptr?
         expr-drop lazyframe-drop
         expr-col expr-lit-i32 expr-lit-i64 expr-lit-u64 expr-lit-f64 expr-lit-bool expr-lit-str
         expr-alias
         expr->string
         lit lit/who col ->expr ->expr/who ->key-expr
         expr-all expr-exclude expr-dtype-col multi-column-expr? dtype-spec?
         expr-add expr-sub expr-mul expr-div expr-mod
         expr-gt expr-lt expr-ge expr-le expr-eq expr-ne
         expr-and expr-or expr-xor
         expr-str-contains expr-str-starts-with expr-str-ends-with
         expr-str-to-lowercase expr-str-to-uppercase
         expr-str-replace expr-str-replace-all expr-str-extract
         expr-str-strip-chars expr-str-strip-chars-start expr-str-strip-chars-end
         expr-str-strip-prefix expr-str-strip-suffix
         expr-str-len-bytes expr-str-len-chars
         expr-str-slice expr-str-head expr-str-tail
         expr-str-find expr-str-find-literal expr-str-count-matches
         expr-str->date expr-str->datetime expr-str->time
         expr-dt-year expr-dt-month expr-dt-day
         expr-dt-hour expr-dt-minute expr-dt-second
         expr-dt-iso-year expr-dt-quarter expr-dt-week
         expr-dt-weekday expr-dt-ordinal-day expr-dt-is-leap-year
         expr-dt-date expr-dt-time
         expr-dt-millisecond expr-dt-microsecond expr-dt-nanosecond
         expr-dt-timestamp expr-dt-strftime expr-dt-truncate
         expr-not expr-neg expr-name-keep expr-is-null expr-is-not-null
         expr-drop-nulls expr-drop-nans
         expr-is-nan expr-is-not-nan expr-is-finite expr-is-infinite
         expr-fill-null expr-fill-nan
         expr-abs expr-sign expr-floor expr-ceil expr-sqrt expr-exp expr-log1p
         expr-log expr-pow expr-clip
         expr-lit-series expr-is-between
         expr-is-unique expr-is-duplicated
         expr-is-first-distinct expr-is-last-distinct
         expr-cum-sum expr-cum-prod expr-cum-min expr-cum-max expr-cum-count
         expr-reverse expr-filter
         index-list/c membership-list/c
         expr-sum expr-mean expr-min expr-max
         expr-count expr-n-unique expr-first expr-last expr-median
         expr-over
         expr-when
         null-behavior/c rank-method/c
         dataframe-lazy
         lazyframe-with-columns lazyframe-collect lazyframe-collect/raw
         lazyframe-filter lazyframe-select
         lazyframe-group-by-agg
         lazyframe-unique lazyframe-drop-nulls
         expr-forward-fill expr-backward-fill expr-round expr-shift expr-diff expr-rank
         expr-head expr-tail expr-slice expr-is-in expr-gather expr-std expr-var
         lazyframe-explain lazyframe-join
         expr-cast-to
         dataframe-with-columns dataframe-select-exprs dataframe-filter-expr
         dataframe-group-by-agg
         expr-meta-output-name expr-meta-output-name/raw expr-meta-output-name/who
         expr-meta-root-names expr-meta-eq?
         expr-sort expr-sort-by lazyframe-sort dataframe-sort-exprs expr-cast
         lazyframe-head lazyframe-tail lazyframe-slice)

(module+ internal
  (require (only-in (submod polars/private/expr-ops internal)
                    expr-cast-datetime-tz/raw expr-diff expr-forward-fill expr-round expr-shift)
           (only-in (submod polars/private/expr-select internal)
                    expr-head expr-rank expr-slice expr-sort expr-sort-by expr-std expr-tail
                    expr-var rank-methods)
           (only-in (submod polars/private/lazyframe internal)
                    call-with-plan collect-plan/who lazyframe-collect/who lazyframe-explain
                    lazyframe-head lazyframe-join lazyframe-join/who lazyframe-slice
                    lazyframe-sort lazyframe-tail))
  (provide call-with-plan collect-plan/who expr-diff expr-forward-fill expr-head expr-rank
           expr-round expr-shift expr-slice expr-sort expr-sort-by expr-std expr-tail expr-var
           lazyframe-collect/who lazyframe-explain lazyframe-head lazyframe-join lazyframe-join/who
           lazyframe-slice
           lazyframe-sort lazyframe-tail rank-methods
           expr-cast-datetime-tz/raw))
