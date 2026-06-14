#lang racket/base

;; Expr cumulative ops + shift / diff: cum-sum / cum-prod / cum-min /
;; cum-max / cum-count (each with #:reverse), shift (#:n, #:fill-value),
;; diff (#:n, #:null-behavior).
;;
;; Inside `nix develop`:
;;   racket examples/38-expr-cumulative.rkt

(require polars)

(define df
  (dataframe (list (series '(1 2 3 4 5) #:name "x" #:dtype 'i64))))

(define out
  (~> df
      (with-columns
        (alias (cum-sum "x") "cumsum")
        (alias (cum-sum "x" #:reverse #t) "cumsum_rev")
        (alias (cum-prod "x") "cumprod")
        (alias (cum-min "x") "cummin")
        (alias (cum-max "x") "cummax")
        (alias (cum-count "x") "cumcount")
        (alias (shift "x" #:n 1) "shift1")
        (alias (shift "x" #:n -1) "shift_m1")
        (alias (shift "x" #:n 1 #:fill-value 0) "shift1_fill0")
        (alias (diff "x" #:n 1) "diff1"))))

(displayln out)
