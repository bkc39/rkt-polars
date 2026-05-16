#lang racket/base

;; Expr cumulative ops + shift / diff: cum-sum / cum-prod / cum-min /
;; cum-max / cum-count (each with #:reverse), expr-shift (#:n,
;; #:fill-value), expr-diff (#:n, #:null-behavior).
;;
;; Inside `nix develop`:
;;   racket examples/38-expr-cumulative.rkt

(require polars)

(define df
  (dataframe-new (list (series-new-i64 "x" '(1 2 3 4 5)))))

(define out
  (dataframe-with-columns
   df
   (list (expr-alias (expr-cum-sum (col "x")) "cumsum")
         (expr-alias (expr-cum-sum (col "x") #:reverse #t) "cumsum_rev")
         (expr-alias (expr-cum-prod (col "x")) "cumprod")
         (expr-alias (expr-cum-min (col "x")) "cummin")
         (expr-alias (expr-cum-max (col "x")) "cummax")
         (expr-alias (expr-cum-count (col "x")) "cumcount")
         (expr-alias (expr-shift (col "x") #:n 1) "shift1")
         (expr-alias (expr-shift (col "x") #:n -1) "shift_m1")
         (expr-alias (expr-shift (col "x") #:n 1 #:fill-value 0) "shift1_fill0")
         (expr-alias (expr-diff (col "x") #:n 1) "diff1"))))

(display-dataframe out)
