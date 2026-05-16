#lang racket/base

;; Expr conditional: when / then / otherwise.
;;
;; Inside `nix develop`:
;;   racket examples/34-expr-when-then.rkt

(require polars)

(define df
  (dataframe-new
   (list (series-new-i32 "x" '(-3 0 4 12 7)))))

(define out
  (dataframe-with-columns
   df
   (list
    ;; single when/then/otherwise
    (expr-alias (expr-when (list (list (expr-gt (col "x") 0) "pos"))
                           #:otherwise "non-pos")
                "sign")
    ;; chained when/then ... otherwise, with auto-lifted numeric values
    (expr-alias (expr-when (list (list (expr-lt (col "x") 0) 0)
                                 (list (expr-eq (col "x") 0) 1)
                                 (list (expr-lt (col "x") 10) 2))
                           #:otherwise 3)
                "bucket"))))

(display-dataframe out)
