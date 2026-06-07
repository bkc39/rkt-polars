#lang racket/base

;; Expr sorting / selection helpers: rank, reverse, sort-by, head, tail,
;; slice, filter, gather.
;;
;; Length-preserving ops (rank, reverse) fit with-columns; length-changing
;; ops (sort-by, head, tail, slice, filter, gather) go in a select where every
;; produced column shares a length.
;;
;; Inside `nix develop`:
;;   racket examples/39-expr-sort-select.rkt

(require polars)

(define df
  (dataframe (list (series '(30 10 50 20 40) #:name "x" #:dtype 'i64)
                   (series '("b" "a" "b" "a" "b") #:name "g"))))

;; length-preserving ops: rank, reverse
(displayln
 (~> df (with-columns
          (alias (rank (col "x") #:method 'dense) "rank_dense")
          (alias (reverse (col "x")) "x_rev"))))

;; sort one column by another
(displayln
 (~> df (select (alias (sort-by (col "x") #:by "x") "x_sorted")
                (alias (sort-by (col "g") #:by "x") "g_by_x"))))

;; head / tail / slice (each select's columns must share a length)
(displayln
 (~> df (select (alias (head (col "x") 2) "x_head2")
                (alias (tail (col "x") 2) "x_tail2")
                (alias (slice (col "x") 1 2) "x_slice"))))

;; filter + gather
(displayln
 (~> df (select (alias (filter (col "x") (> (col "x") 25)) "x_big"))))
(displayln
 (~> df (select (alias (gather (col "x") '(0 2 4)) "x_gathered"))))
