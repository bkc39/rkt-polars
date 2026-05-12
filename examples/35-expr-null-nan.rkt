#lang racket/base

;; Expr null / NaN handling: fill_null, forward/backward fill, fill_nan,
;; drop_nulls / drop_nans, and the is-nan / is-finite / is-infinite tests.
;;
;; Inside `nix develop`:
;;   racket examples/35-expr-null-nan.rkt

(require polars)

(define df
  (dataframe-new
   (list (series-new-f64 "x" (list 1.0 polars-null 3.0 polars-null 5.0))
         (series-new-f64 "y" (list 1.0 +nan.0 3.0 +inf.0 -1.0)))))

(define out
  (dataframe-with-columns
   df
   (list (expr-alias (expr-fill-null (col "x") 0.0) "x_filled")
         (expr-alias (expr-forward-fill (col "x")) "x_ffill")
         (expr-alias (expr-backward-fill (col "x")) "x_bfill")
         (expr-alias (expr-is-null (col "x")) "x_is_null")
         (expr-alias (expr-fill-nan (col "y") -99.0) "y_no_nan")
         (expr-alias (expr-is-nan (col "y")) "y_is_nan")
         (expr-alias (expr-is-finite (col "y")) "y_is_finite")
         (expr-alias (expr-is-infinite (col "y")) "y_is_inf"))))

(display-dataframe out)

;; drop_nulls / drop_nans collapse the column length
(define dropped
  (dataframe-select-exprs
   df
   (list (expr-alias (expr-drop-nulls (col "x")) "x_no_null"))))

(display-dataframe dropped)
