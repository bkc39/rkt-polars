#lang racket/base

;; Expr element-wise math: abs, sign, round, floor, ceil, clip, sqrt,
;; exp, log (with #:base), log1p, pow.
;;
;; Inside `nix develop`:
;;   racket examples/36-expr-math.rkt

(require polars)

(define df
  (dataframe-new (list (series-new-f64 "x" '(-2.5 -1.0 0.0 1.5 4.0)))))

(define out
  (dataframe-with-columns
   df
   (list (expr-alias (expr-abs (col "x")) "abs")
         (expr-alias (expr-sign (col "x")) "sign")
         (expr-alias (expr-round (col "x") #:decimals 1) "round1")
         (expr-alias (expr-floor (col "x")) "floor")
         (expr-alias (expr-ceil (col "x")) "ceil")
         (expr-alias (expr-clip (col "x") #:lower -1.0 #:upper 2.0) "clip")
         (expr-alias (expr-clip (col "x") #:lower 0.0) "clip_min")
         (expr-alias (expr-sqrt (expr-abs (col "x"))) "sqrt_abs")
         (expr-alias (expr-exp (col "x")) "exp")
         (expr-alias (expr-log (expr-abs (col "x")) #:base 2) "log2_abs")
         (expr-alias (expr-pow (expr-abs (col "x")) 2) "sq"))))

(display-dataframe out)
