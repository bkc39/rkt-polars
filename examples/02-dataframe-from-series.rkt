#lang racket/base

;; Mirror of rust/examples/02_dataframe_from_series.rs.
;;
;; Inside `nix develop`:
;;   racket examples/02-dataframe-from-series.rkt

(require gregor
         polars/private/foreign
         polars/private/series)

(define users
  (series-new-str "user" '("alice" "bob" "carol" "dora")))

(define scores
  (series-new-i32 "score" '(10 25 18 41)))

(define costs
  (series-new-f64 "cost" '(1.2 3.5 2.0 8.4)))

(define created-at
  (series-new-datetime
   "created_at"
   (list (datetime 2024 1 1 8 0 0)
         (datetime 2024 1 2 8 0 0)
         (datetime 2024 1 3 8 0 0)
         (datetime 2024 1 4 8 0 0))))

(define df
  (dataframe-new (list users scores costs created-at)))

(printf "shape=~a height=~a width=~a\n"
        (call-with-values (lambda () (dataframe-shape df)) cons)
        (dataframe-height df)
        (dataframe-width df))

(printf "column names=~a\n"
        (for/list ([i (in-range (dataframe-width df))])
          (dataframe-column-name df i)))

(for ([i (in-range (dataframe-width df))])
  (define name (dataframe-column-name df i))
  (printf "schema ~a => ~a\n" name (series-dtype (dataframe-column df name))))

(define score (dataframe-column df "score"))
(printf "score column dtype=~a len=~a nulls=~a\n"
        (series-dtype score)
        (series-len score)
        (series-null-count score))

(newline)
(displayln "DataFrame:")
(display-dataframe df)
