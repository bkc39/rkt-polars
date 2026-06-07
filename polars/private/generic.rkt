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
         polars/private/generic/reshape
         polars/private/generic/strings
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
         filter sort
         head tail slice reverse unique drop-nulls
         select drop with-column with-columns cast join vstack hstack
         join-asof pivot unpivot
         group-by agg grouped? lazy collect scan-csv scan-parquet
         str-to-lowercase str-to-uppercase
         str-contains str-starts-with str-ends-with
         rename rename! clone series-clone
         then otherwise
         (rename-out [p-and and] [p-or or] [p-not not] [p-xor xor]
                     [p+ +] [p- -] [p* *] [p/ /] [p-when when]))
