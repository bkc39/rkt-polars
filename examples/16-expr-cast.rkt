#lang racket/base

;; Expr cast — change a column's dtype inside a lazy/with-columns plan.
;; Mirrors the canonical Polars Python flow:
;;   df.with_columns([
;;     col("x").cast(pl.Float64).alias("xf"),
;;     col("x").cast(pl.Utf8).alias("xs"),
;;     (col("x").cast(pl.Float64) / col("y")).alias("ratio"),
;;   ])
;;
;; Inside `nix develop`:
;;   racket examples/16-expr-cast.rkt

(require polars)

(define df
  (dataframe-new
   (list (series-new-i32 "x" '(10 20 30 40))
         (series-new-i32 "y" '(3 4 5 6)))))

(displayln "input (x and y are i32):")
(display-dataframe df)
(newline)

;; Promote both to f64 to get a real-valued ratio; tag with string label.
(define out
  (dataframe-with-columns
   df
   (list (expr-alias (expr-cast (col "x") 'float64) "xf")
         (expr-alias (expr-cast (col "x") 'string)  "xs")
         (expr-alias (expr-div (expr-cast (col "x") 'float64)
                               (expr-cast (col "y") 'float64))
                     "ratio"))))

(displayln "with_columns(cast x->f64, cast x->str, x/y as f64):")
(display-dataframe out)
(newline)

;; Datetime cast: interpret an i64 column as microsecond-resolution timestamps.
(define df-ts
  (dataframe-new
   (list (series-new-i64 "t" '(0 1000000 2000000 3000000)))))

(define ts
  (dataframe-with-columns
   df-ts
   (list (expr-alias (expr-cast (col "t") 'datetime) "ts"))))

(displayln "cast i64 -> datetime (defaults to microseconds):")
(display-dataframe ts)
