#lang racket/base

;; Expr sorting / selection helpers: rank, reverse, sort-by, head, tail,
;; slice, filter, gather.
;;
;; Inside `nix develop`:
;;   racket examples/39-expr-sort-select.rkt

(require polars)

(define df
  (dataframe-new (list (series-new-i64 "x" '(30 10 50 20 40))
                       (series-new-str "g" '("b" "a" "b" "a" "b")))))

;; length-preserving ops: rank, reverse
(define ranked
  (dataframe-with-columns
   df
   (list (expr-alias (expr-rank (col "x") #:method 'dense) "rank_dense")
         (expr-alias (expr-reverse (col "x")) "x_rev"))))
(display-dataframe ranked)

;; sort one column by another
(define sorted
  (dataframe-select-exprs
   df
   (list (expr-alias (expr-sort-by (col "x") #:by "x") "x_sorted")
         (expr-alias (expr-sort-by (col "g") #:by "x") "g_by_x"))))
(display-dataframe sorted)

;; head / tail / slice (each select's columns must share a length)
(define windowed
  (dataframe-select-exprs
   df
   (list (expr-alias (expr-head (col "x") #:n 2) "x_head2")
         (expr-alias (expr-tail (col "x") #:n 2) "x_tail2")
         (expr-alias (expr-slice (col "x") 1 2) "x_slice"))))
(display-dataframe windowed)

;; filter + gather
(display-dataframe
 (dataframe-select-exprs
  df (list (expr-alias (expr-filter (col "x") (expr-gt (col "x") 25)) "x_big"))))
(display-dataframe
 (dataframe-select-exprs
  df (list (expr-alias (expr-gather (col "x") '(0 2 4)) "x_gathered"))))
