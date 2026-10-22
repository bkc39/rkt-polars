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
         polars/private/generic/convert
         polars/private/generic/csv
         polars/private/generic/json
         polars/private/generic/parquet
         polars/private/generic/printing
         polars/private/generic/reductions
         polars/private/generic/operators
         polars/private/generic/math
         polars/private/generic/reshape
         polars/private/generic/combine
         polars/private/generic/strings
         polars/private/generic/datetime
         polars/private/generic/nullable
         polars/private/generic/predicates
         polars/private/generic/cumulative
         polars/private/generic/ordering
         polars/private/generic/describe
         polars/private/generic/selectors
         polars/private/generic/window
         polars/private/generic/meta
         (only-in polars/private/generic/dtype define-enum))

(provide series series? series->string
         dataframe dataframe? lazyframe?
         describe ref
         len shape shape/values dtype null-count define-enum
         width height column-name column-names
         write-csv read-csv write-parquet read-parquet write-ndjson read-ndjson
         write-json read-json scan-ndjson
         series->list series->vector series->f64vector in-series
         dataframe->columns dataframe->hash dataframe->f64vector in-dataframe-columns
         in-dataframe-rows dataframe->rows
         gen:has-ref has-ref?
         gen:sized sized?
         gen:has-shape has-shape?
         gen:has-dtype has-dtype?
         gen:has-null-count has-null-count?
         sum mean min max
         count n-unique first last median std var alias
         over
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
         group-by agg grouped? lazy collect explain scan-csv scan-parquet
         str-to-lowercase str-to-uppercase
         str-contains str-starts-with str-ends-with
         str-strip-chars str-strip-prefix str-strip-suffix
         str-replace str-replace-all str-extract
         str-len-bytes str-len-chars str-slice str-head str-tail
         str-find str-find-literal str-count-matches
         str->date str->datetime str->time
         dt-year dt-month dt-day dt-hour dt-minute dt-second
         dt-iso-year dt-quarter dt-week dt-weekday dt-ordinal-day
         dt-is-leap-year dt-date dt-time
         dt-millisecond dt-microsecond dt-nanosecond
         dt-timestamp dt-strftime dt-truncate
         dt-convert-time-zone dt-replace-time-zone
         rename rename! clone series-clone
         then otherwise else-when
         all exclude
         meta-output-name meta-root-names meta-eq?
         (rename-out [p-and and] [p-or or] [p-not not] [p-xor xor]
                     [p+ +] [p- -] [p* *] [p/ /] [p-when when]
                     [p-abs abs] [p-round round] [p-floor floor]
                     [p-sqrt sqrt] [p-exp exp] [p-log log]))

(module+ test
  (require rackunit
           (only-in polars/private/expr-core
                    Expr-ptr? LazyFrame-ptr? col expr-drop expr-drop-count lazyframe-drop
                    lazyframe-drop-count)
           (only-in polars/private/expr dataframe-lazy expr-alias lazyframe-collect)
           (only-in polars/private/foreign
                    DataFrame-ptr? Series-ptr? dataframe-drop dataframe-drop-count dataframe-height
                    dataframe-new series-drop series-drop-count series-len series-new-i64)
           (only-in polars/private/test-helpers contract-violation-of drops-once))

  (define-check (check-dropped thunk who noun)
    (define expected (format "~a: ~a has been dropped" who noun))
    (define actual (with-handlers ([exn:fail:contract? exn-message]) (thunk) #f))
    (with-check-info (['expected expected] ['actual actual])
      (unless (equal? actual expected) (fail-check))))

  (define ((drop-twice drop noun) v)
    (drop v)
    (check-dropped (lambda () (drop v)) (object-name drop) noun))

  (check-equal? (drops-once series-drop-count (drop-twice series-drop 'series)
                            (lambda () (series '(1 2))))
                1)
  (check-equal? (drops-once series-drop-count (drop-twice series-drop 'series)
                            (lambda () (series-new-i64 "raw" '(1 2))))
                1)
  (check-equal? (drops-once series-drop-count (drop-twice series-drop 'series)
                            (lambda () (wrap-series (wrap-series (series-new-i64 "x" '(1))))))
                1)
  (check-equal? (drops-once dataframe-drop-count (drop-twice dataframe-drop 'dataframe)
                            (lambda () (dataframe (list (series '(1 2) #:name "a")))))
                1)
  (check-equal? (drops-once dataframe-drop-count (drop-twice dataframe-drop 'dataframe)
                            (lambda () (dataframe-new (list (series '(1 2) #:name "a")))))
                1)
  (check-equal? (drops-once expr-drop-count (drop-twice expr-drop "expression")
                            (lambda () (col "x")))
                1)
  (for ([make (list (lambda () (lazy (dataframe (list (series '(1) #:name "a")))))
                    (lambda () (dataframe-lazy (dataframe-new (list (series '(1)))))))])
    (check-equal? (drops-once lazyframe-drop-count (drop-twice lazyframe-drop 'lazyframe) make) 1))
  (for ([drop (list series-drop dataframe-drop lazyframe-drop expr-drop)])
    (check-exn (contract-violation-of (object-name drop)) (lambda () (drop "a"))))

  (define temps (series '(21.5 23.0 19.8) #:name "temp"))
  (series-drop temps)
  (check-equal? (format "~v" temps) "#<series: dropped>")
  (check-pred series? temps)
  (check-pred Series-ptr? temps)
  (check-dropped (lambda () (len temps)) 'series 'series)
  (check-dropped (lambda () (ref temps 0)) 'series 'series)
  (check-dropped (lambda () (series-len temps)) 'series 'series)
  (check-dropped (lambda () (dataframe (list temps))) 'series 'series)
  (check-dropped (lambda () (sort temps)) 'series 'series)
  (check-dropped (lambda () (is-in "v" temps)) 'series 'series)

  (define raw-series (series-new-i64 "raw" '(1)))
  (series-drop raw-series)
  (check-dropped (lambda () (series-len raw-series)) 'series 'series)

  (define raw-frame (dataframe-new (list (series-new-i64 "v" '(1)))))
  (dataframe-drop raw-frame)
  (check-dropped (lambda () (dataframe-height raw-frame)) 'dataframe 'dataframe)

  (define raw-query (dataframe-lazy (dataframe-new (list (series-new-i64 "v" '(1))))))
  (lazyframe-drop raw-query)
  (check-dropped (lambda () (lazyframe-collect raw-query)) 'lazyframe 'lazyframe)

  (define inner-series (series '(4 5)))
  (series-drop (wrap-series inner-series))
  (check-dropped (lambda () (len inner-series)) 'series 'series)
  (check-dropped (lambda () (series-drop inner-series)) 'series-drop 'series)

  (define shared-raw (series-new-i64 "shared" '(1 2)))
  (define first-holder (wrap-series shared-raw))
  (define second-holder (wrap-series shared-raw))
  (series-drop first-holder)
  (check-equal? (format "~a" second-holder) "#<series: dropped>")
  (check-dropped (lambda () (len second-holder)) 'series 'series)
  (check-dropped (lambda () (series-drop second-holder)) 'series-drop 'series)

  (define readings (dataframe (list (series '(3 1 2) #:name "v"))))
  (dataframe-drop readings)
  (check-equal? (format "~v" readings) "#<dataframe: dropped>")
  (check-pred dataframe? readings)
  (check-pred DataFrame-ptr? readings)
  (check-dropped (lambda () (height readings)) 'dataframe 'dataframe)
  (check-dropped (lambda () (sort readings "v")) 'dataframe 'dataframe)
  (check-dropped (lambda () (write-csv readings (build-path (find-system-path 'temp-dir)
                                                           "rkt-polars-dropped-131.csv")))
                 'dataframe 'dataframe)

  (define query (lazy (dataframe (list (series '(3 1 2) #:name "v")))))
  (lazyframe-drop query)
  (check-equal? (format "~v" query) "#<lazyframe: dropped>")
  (check-pred lazyframe? query)
  (check-pred LazyFrame-ptr? query)
  (check-dropped (lambda () (collect query)) 'lazyframe 'lazyframe)
  (check-dropped (lambda () (lazyframe-collect query)) 'lazyframe 'lazyframe)
  (check-dropped (lambda () (sort query "v")) 'lazyframe 'lazyframe)

  (define threshold (> (col "v") 2))
  (expr-drop threshold)
  (check-equal? (format "~v" threshold) "#<expr: dropped>")
  (check-pred Expr-ptr? threshold)
  (check-dropped (lambda () (filter (dataframe (list (series '(1 3) #:name "v"))) threshold))
                 'expr "expression")
  (check-dropped (lambda () (expr-drop threshold)) 'expr-drop "expression")
  (check-dropped (lambda () (expr-alias threshold "w")) 'expr "expression")
  (check-dropped (lambda () (sort threshold)) 'expr "expression")
  (check-dropped (lambda () (is-in "v" threshold)) 'expr "expression"))
