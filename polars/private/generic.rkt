#lang racket/base

;; The high-level, "rackety" UX layer over the monomorphic Series / DataFrame
;; bindings in polars/private/foreign.  The implementation is split across
;; polars/private/generic/; this module is the aggregator that re-exports the
;; public surface.
;;
;; A series/dataframe is a wrapper struct (series? / dataframe?) carrying
;; prop:cpointer (so it still marshals as the raw FFI pointer everywhere) plus a
;; Polars-format prop:custom-write.  Dispatch uses small capability generics
;; (ref / len / shape / dtype / null-count); most operators are plain functions
;; that dispatch on series? / dataframe? / Expr-ptr?.
;;
;; The operators that shadow racket/base (+ - * / and or not xor when) are
;; defined in polars/private/generic/operators under p* spellings and renamed
;; here on the way out — `polars/main.rkt` re-imports them under private aliases
;; (all-from-out drops rename-out names that collide with the module language).

(require polars/private/generic/core
         polars/private/generic/printing
         polars/private/generic/reductions
         polars/private/generic/operators
         polars/private/generic/math
         polars/private/generic/reshape
         polars/private/generic/strings
         polars/private/generic/datetime
         polars/private/generic/nullable
         polars/private/generic/predicates
         polars/private/generic/cumulative
         polars/private/generic/ordering
         polars/private/generic/describe)

(provide series series? series->string
         dataframe dataframe? lazyframe?
         describe ref
         len shape shape/values dtype null-count
         width height column-name column-names
         write-csv read-csv write-parquet read-parquet write-ndjson read-ndjson
         gen:has-ref has-ref?
         gen:sized sized?
         gen:has-shape has-shape?
         gen:has-dtype has-dtype?
         gen:has-null-count has-null-count?
         sum mean min max
         count n-unique first last median std var alias
         > < >= <= = !=
         mod sign ceil log1p pow clip
         filter sort
         head tail slice reverse unique drop-nulls drop-nans
         is-null is-not-null is-nan is-not-nan is-finite is-infinite
         fill-null fill-nan forward-fill backward-fill
         is-in is-between
         is-unique is-duplicated is-first-distinct is-last-distinct
         cum-sum cum-prod cum-min cum-max cum-count shift diff
         sort-by rank gather
         select drop with-column with-columns cast join vstack hstack
         join-asof pivot unpivot
         group-by agg grouped? lazy collect scan-csv scan-parquet
         str-to-lowercase str-to-uppercase
         str-contains str-starts-with str-ends-with
         str-strip-chars str-strip-prefix str-strip-suffix
         str-replace str-replace-all str-extract
         str-len-bytes str-len-chars str-slice str-head str-tail
         str-find str-find-literal str-count-matches
         str-to-date str-to-datetime str-to-time
         dt-year dt-month dt-day dt-hour dt-minute dt-second
         dt-iso-year dt-quarter dt-week dt-weekday dt-ordinal-day
         dt-is-leap-year dt-date dt-time
         dt-millisecond dt-microsecond dt-nanosecond
         dt-timestamp dt-strftime dt-truncate
         rename rename! clone series-clone
         then otherwise else-when
         (rename-out [p-and and] [p-or or] [p-not not] [p-xor xor]
                     [p+ +] [p- -] [p* *] [p/ /] [p-when when]
                     [p-abs abs] [p-round round] [p-floor floor]
                     [p-sqrt sqrt] [p-exp exp] [p-log log]))
