#lang racket/base

;; Mirror of rust/examples/02_dataframe_from_series.rs.
;;
;; Inside `nix develop`:
;;   racket examples/02-dataframe-from-series.rkt

(require gregor
         polars)

;; Build each column with the generic `series` constructor (see example 01).
(define users
  (series '("alice" "bob" "carol" "dora") #:name "user"))

(define scores
  (series '(10 25 18 41) #:name "score" #:dtype 'i32))

(define costs
  (series '(1.2 3.5 2.0 8.4) #:name "cost"))

(define created-at
  (series
   (list (datetime 2024 1 1 8 0 0)
         (datetime 2024 1 2 8 0 0)
         (datetime 2024 1 3 8 0 0)
         (datetime 2024 1 4 8 0 0))
   #:name "created_at"))

;; `dataframe` is the smart constructor: it wraps the columns in a dataframe
;; value (`dataframe?`) that prints like Polars, mirroring the series wrapper.
(define df
  (dataframe (list users scores costs created-at)))

;; shape / height / width are generic accessors (no dataframe- prefix needed).
;; shape returns the dimensions as a list; shape/values is the values variant.
(printf "shape=~a height=~a width=~a\n"
        (shape df)
        (height df)
        (width df))

(printf "column names=~a\n" (column-names df))

;; `ref` selects a column by name (#:columns), and `dtype` reads its dtype.
(for ([name (in-list (column-names df))])
  (printf "schema ~a => ~a\n" name (dtype (ref df #:columns name))))

(define score (ref df #:columns "score"))
(printf "score column dtype=~a len=~a nulls=~a\n"
        (dtype score)
        (len score)
        (null-count score))

(newline)
(displayln "DataFrame:")
;; The dataframe prints itself (custom-write), so plain display / ~a suffice.
(displayln df)
