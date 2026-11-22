#lang racket/base

(require (only-in polars/private/expr
                  Expr-ptr? col dtype-spec? expr->string expr-drop lit multi-column-expr?)
         (only-in polars/private/foreign polars-null polars-null? series-name time-zone-name/c)
         polars/private/generic
         (only-in threading ~> ~>> lambda~> lambda~>>))

(provide
 ~> ~>> lambda~> lambda~>>

 Expr-ptr? col lit expr->string expr-drop dtype-spec? multi-column-expr?

 time-zone-name/c polars-null polars-null? series-name

 all exclude meta-output-name meta-root-names meta-eq?
 > < >= <= = != and or not xor + - * / mod
 when then else-when otherwise
 filter sort sort-by select with-columns cast vstack hstack with-column
 head tail slice reverse unique drop-nulls drop pivot unpivot join join-asof
 read-csv scan-csv write-csv read-parquet scan-parquet write-parquet
 read-json write-json read-ndjson scan-ndjson write-ndjson
 lazy lazyframe? collect explain group-by agg grouped? over
 rank gather shift diff forward-fill backward-fill
 sum mean min max count n-unique median std var alias first last
 abs sqrt exp log log1p floor ceil round pow sign clip
 is-null is-not-null is-nan is-not-nan is-finite is-infinite
 fill-null fill-nan drop-nans
 is-between is-in is-unique is-duplicated is-first-distinct is-last-distinct
 cum-sum cum-prod cum-min cum-max cum-count
 dt-year dt-month dt-day dt-hour dt-minute dt-second
 dt-iso-year dt-quarter dt-week dt-weekday dt-ordinal-day dt-is-leap-year
 dt-date dt-time dt-millisecond dt-microsecond dt-nanosecond
 dt-timestamp dt-strftime dt-truncate dt-convert-time-zone dt-replace-time-zone
 str-to-lowercase str-to-uppercase str-contains str-starts-with str-ends-with
 str-strip-chars str-strip-prefix str-strip-suffix str-replace str-replace-all
 str-len-bytes str-len-chars str-head str-tail str-slice
 str-find str-find-literal str-count-matches str-extract
 str->date str->time str->datetime
 series series? series->string dtype len null-count rename rename! clone series-clone
 series->list series->vector series->f64vector in-series define-enum
 dataframe dataframe? shape shape/values height width column-names column-name
 ref describe
 dataframe->columns dataframe->hash in-dataframe-columns in-dataframe-rows
 dataframe->rows dataframe->f64vector
 gen:has-ref has-ref? gen:sized sized? gen:has-shape has-shape?
 gen:has-dtype has-dtype? gen:has-null-count has-null-count?)
