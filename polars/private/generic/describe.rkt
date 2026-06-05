#lang racket/base

;; describe: Polars' .describe() — returns a summary-statistics *dataframe*
;; (which prints as a table).  A series' describe adapts its rows to the dtype;
;; a dataframe's uses Polars' fixed nine-row layout for every column.  This is a
;; plain dispatching function (not a struct method), which lets it sit above and
;; reuse the public mean/min/max reductions instead of duplicating them.

(require (only-in gregor datetime? date? ~t)
         polars/private/foreign
         polars/private/generic/core
         polars/private/generic/reductions
         polars/private/generic/dtype)

(provide describe)

;; The nine statistic labels, in Polars' order.
(define describe-stat-names
  '("count" "null_count" "mean" "std" "min" "25%" "50%" "75%" "max"))

(define (->f64-or-null v) (if (polars-null? v) v (exact->inexact v)))

;; Render a min/max scalar as a string for the non-numeric describe path.
(define (->string-or-null v)
  (cond
    [(polars-null? v) v]
    [(datetime? v) (~t v "yyyy-MM-dd HH:mm:ss")]
    [(date? v) (~t v "yyyy-MM-dd")]
    [else (format "~a" v)]))

;; The nine numeric statistics for `s`, all as flonums (or polars-null), in
;; describe-stat-names order.  mean/min/max are the public reductions.
(define (numeric-describe-values s)
  (define n (series-len s))
  (define nulls (series-null-count s))
  (list (exact->inexact (- n nulls))
        (exact->inexact nulls)
        (->f64-or-null (mean s))
        (series-std s)
        (->f64-or-null (min s))
        (series-quantile s 0.25)
        (series-quantile s 0.50)
        (series-quantile s 0.75)
        (->f64-or-null (max s))))

;; Build the two-column (statistic, value) result frame.
(define (stats-frame names values)
  (dataframe (list (series names #:name "statistic")
                   (series values #:name "value"))))

(define (describe-series s)
  (define dt (series-dtype s))
  (define n (series-len s))
  (define nulls (series-null-count s))
  (define count (- n nulls))
  (cond
    [(numeric-dtype? dt)
     (stats-frame describe-stat-names (numeric-describe-values s))]
    [(eq? dt 'boolean)
     (define (bool->f v) (if (polars-null? v) v (if v 1.0 0.0)))
     (stats-frame '("count" "null_count" "mean" "min" "max")
                  (list (exact->inexact count) (exact->inexact nulls)
                        (->f64-or-null (mean s)) (bool->f (min s)) (bool->f (max s))))]
    [else
     (stats-frame '("count" "null_count" "min" "max")
                  (list (number->string count) (number->string nulls)
                        (->string-or-null (min s)) (->string-or-null (max s))))]))

;; One value column for a dataframe's describe: always nine rows, with nulls in
;; the slots the column's dtype has no statistic for.
(define (describe-column-values s)
  (define dt (series-dtype s))
  (define n (series-len s))
  (define nulls (series-null-count s))
  (define count (- n nulls))
  (cond
    [(numeric-dtype? dt) (numeric-describe-values s)]
    [(eq? dt 'boolean)
     (define (bool->f v) (if (polars-null? v) v (if v 1.0 0.0)))
     (list (exact->inexact count) (exact->inexact nulls) (->f64-or-null (mean s))
           polars-null (bool->f (min s)) polars-null polars-null polars-null (bool->f (max s)))]
    [else
     (list (number->string count) (number->string nulls)
           polars-null polars-null (->string-or-null (min s))
           polars-null polars-null polars-null (->string-or-null (max s)))]))

(define (describe-dataframe d)
  (define names (dataframe-column-names d))
  (define value-cols
    (for/list ([nm (in-list names)])
      (series (describe-column-values (wrap-series (dataframe-column d nm)))
              #:name nm)))
  (dataframe (cons (series describe-stat-names #:name "statistic") value-cols)))

(define (describe x)
  (cond
    [(series? x) (describe-series x)]
    [(dataframe? x) (describe-dataframe x)]
    [else (error 'describe "expected a series or dataframe, got ~v" x)]))

(module+ test
  (require rackunit
           polars/private/generic/core
           polars/private/generic/test-fixtures)
  ;; describe returns a Polars-style stats dataframe (matching .describe())
  (define sc (series '(10 25 18) #:name "score" #:dtype 'i32))
  (define sc-desc (describe sc))
  (check-pred dataframe? sc-desc)
  (check-equal? (column-names sc-desc) '("statistic" "value"))
  (check-equal? (height sc-desc) 9)
  (check-equal? (ref (ref sc-desc #:columns "statistic") 0) "count")
  (check-equal? (ref (ref sc-desc #:columns "value") 0) 3.0)   ; count
  (check-equal? (ref (ref sc-desc #:columns "value") 4) 10.0)  ; min
  (check-equal? (ref (ref sc-desc #:columns "value") 8) 25.0)  ; max
  (define fr-desc (describe frame))
  (check-pred dataframe? fr-desc)
  (check-equal? (height fr-desc) 9)
  (check-equal? (column-names fr-desc) '("statistic" "user" "score" "cost"))
  (check-equal? (ref (ref fr-desc #:columns "user") 0) "3")       ; string count
  (check-equal? (ref (ref fr-desc #:columns "user") 4) "alice")   ; string min
  (check-equal? (ref (ref fr-desc #:columns "user") 8) "carol")   ; string max
  (check-pred polars-null? (ref (ref fr-desc #:columns "user") 2)) ; mean -> null
  (check-equal? (ref (ref fr-desc #:columns "score") 4) 10.0))    ; numeric min
