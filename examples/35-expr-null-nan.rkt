#lang racket/base

;; Expr null / NaN handling: fill-null, forward/backward fill, fill-nan,
;; drop-nulls, and the is-null / is-nan / is-finite / is-infinite tests.
;;
;; Inside `nix develop`:
;;   racket examples/35-expr-null-nan.rkt

(require polars)

(define df
  (dataframe
   (list (series (list 1.0 polars-null 3.0 polars-null 5.0) #:name "x" #:dtype 'f64)
         (series (list 1.0 +nan.0 3.0 +inf.0 -1.0)          #:name "y" #:dtype 'f64))))

(define out
  (~> df
      (with-columns
        (alias (fill-null "x" 0.0) "x_filled")
        (alias (forward-fill "x") "x_ffill")
        (alias (backward-fill "x") "x_bfill")
        (alias (is-null "x") "x_is_null")
        (alias (fill-nan "y" -99.0) "y_no_nan")
        (alias (is-nan "y") "y_is_nan")
        (alias (is-finite "y") "y_is_finite")
        (alias (is-infinite "y") "y_is_inf"))))

(displayln out)

;; drop-nulls on an Expr collapses the column length (used inside select)
(displayln (~> df (select (alias (drop-nulls (col "x")) "x_no_null"))))
