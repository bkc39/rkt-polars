#lang racket/base

;; Expr cast — change a column's dtype inside a with_columns plan.  Each derived
;; column threads:  (~> (col "x") (cast 'float64) (alias "xf")) mirrors
;; col("x").cast(pl.Float64).alias("xf").
;;
;; Inside `nix develop`:
;;   racket examples/16-expr-cast.rkt

(require polars)

(define df
  (dataframe (list (series '(10 20 30 40) #:name "x" #:dtype 'i32)
                   (series '(3 4 5 6)      #:name "y" #:dtype 'i32))))

(displayln "input (x and y are i32):")
(displayln df)
(newline)

;; Promote to f64 for a real-valued ratio; tag x with a string label too.
(displayln "with_columns(cast x->f64, cast x->str, x/y as f64):")
(displayln (~> df
               (with-columns
                 (~> (col "x") (cast 'float64) (alias "xf"))
                 (~> (col "x") (cast 'string)  (alias "xs"))
                 (~> (col "x")
                     (cast 'float64)
                     (/ (cast (col "y") 'float64))
                     (alias "ratio")))))
(newline)

;; Datetime cast: interpret an i64 column as microsecond-resolution timestamps.
(define df-ts
  (dataframe (list (series '(0 1000000 2000000 3000000) #:name "t" #:dtype 'i64))))

(displayln "cast i64 -> datetime (defaults to microseconds):")
(displayln (~> df-ts (with-columns (~> (col "t") (cast 'datetime) (alias "ts")))))
