#lang racket/base

;; Expr membership / distinct predicates: is-in (against a list, Series,
;; or Expr), is-between (#:closed), is-unique / is-duplicated /
;; is-first-distinct / is-last-distinct.
;;
;; Inside `nix develop`:
;;   racket examples/37-expr-predicates.rkt

(require polars)

(define df
  (dataframe-new (list (series-new-i64 "x" '(1 2 2 3 5 5 8)))))

(define out
  (dataframe-with-columns
   df
   (list (expr-alias (expr-is-in (col "x") '(2 3 8)) "in_allowed")
         (expr-alias (expr-is-between (col "x") 2 5) "in_2_5_both")
         (expr-alias (expr-is-between (col "x") 2 5 #:closed 'left) "in_2_5_left")
         (expr-alias (expr-is-unique (col "x")) "uniq")
         (expr-alias (expr-is-duplicated (col "x")) "dup")
         (expr-alias (expr-is-first-distinct (col "x")) "first")
         (expr-alias (expr-is-last-distinct (col "x")) "last"))))

(display-dataframe out)
