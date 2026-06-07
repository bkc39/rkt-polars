#lang racket/base

;; Expr membership / distinct predicates: is-in (against a list, Series,
;; or Expr), is-between (#:closed), is-unique / is-duplicated /
;; is-first-distinct / is-last-distinct.
;;
;; Inside `nix develop`:
;;   racket examples/37-expr-predicates.rkt

(require polars)

(define df
  (dataframe (list (series '(1 2 2 3 5 5 8) #:name "x" #:dtype 'i64))))

(define out
  (~> df
      (with-columns
        (alias (is-in "x" '(2 3 8)) "in_allowed")
        (alias (is-between "x" 2 5) "in_2_5_both")
        (alias (is-between "x" 2 5 #:closed 'left) "in_2_5_left")
        (alias (is-unique "x") "uniq")
        (alias (is-duplicated "x") "dup")
        (alias (is-first-distinct "x") "first")
        (alias (is-last-distinct "x") "last"))))

(displayln out)
