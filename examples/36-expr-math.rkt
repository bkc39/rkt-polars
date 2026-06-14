#lang racket/base

;; Expr element-wise math: abs, sign, round, floor, ceil, clip, sqrt,
;; exp, log (with #:base), log1p, pow.
;;
;; Inside `nix develop`:
;;   racket examples/36-expr-math.rkt

(require polars)

(define df
  (dataframe (list (series '(-2.5 -1.0 0.0 1.5 4.0) #:name "x" #:dtype 'f64))))

(define out
  (~> df
      (with-columns
        (alias (abs (col "x")) "abs")
        (alias (sign (col "x")) "sign")
        (alias (round (col "x") #:decimals 1) "round1")
        (alias (floor (col "x")) "floor")
        (alias (ceil (col "x")) "ceil")
        (alias (clip (col "x") #:lower -1.0 #:upper 2.0) "clip")
        (alias (clip (col "x") #:lower 0.0) "clip_min")
        (alias (sqrt (abs (col "x"))) "sqrt_abs")
        (alias (exp (col "x")) "exp")
        (alias (log (abs (col "x")) #:base 2) "log2_abs")
        (alias (pow (abs (col "x")) 2) "sq"))))

(displayln out)
