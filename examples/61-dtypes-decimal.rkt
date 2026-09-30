#lang racket/base

;; Decimal columns.
;;
;; A '(decimal precision scale) column holds exact decimals; ref and the
;; conversions read them as exact rationals, so sums stay exact. describe
;; treats one as numeric, as Python does, and cast turns it into a float or
;; string column. There is no #:dtype spelling for Decimal: the column here
;; comes from Parquet.
;;
;; Inside `nix develop`:
;;   racket examples/61-dtypes-decimal.rkt

(require racket/runtime-path
         polars)

(define-runtime-path produce-parquet "../polars/scribblings/data/produce.parquet")

(define prices (ref (read-parquet produce-parquet) "price"))

(printf "dtype: ~s\n" (dtype prices))
(printf "values: ~s\n" (series->list prices))
(printf "row 3: ~s\n" (ref prices 3))
(printf "exact total: ~s\n"
        (for/sum ([p (in-series prices #:null 0)]) p))
(printf "as float64: ~s\n" (series->list (cast prices 'float64)))
(printf "as string: ~s\n" (series->list (cast prices 'string)))
(displayln (describe prices))
