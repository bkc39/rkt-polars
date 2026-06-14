#lang racket/base

;; Expr ordering / selection ops that pair with select / with-columns:
;; sort-by (order a column by other column(s)), rank, and gather (positional
;; pick).  Each takes an Expr or a bare column-name string (auto-lifted via col).
;; The length-preserving ones (rank) fit with-columns; the length-changing ones
;; (gather, and sort-by when the key differs in length) belong in a select where
;; every produced column shares a length.

(require polars/private/foreign
         polars/private/expr
         polars/private/generic/expr-util)

(provide sort-by rank gather)

;; sort-by: reorder x by #:by (a column name / Expr / list of them); #:descending
;; is a bool or a per-key list of bools.
(define (sort-by x #:by by #:descending [descending #f])
  (expr-sort-by (->col-expr 'sort-by x) #:by by #:descending descending))

;; rank: #:method 'average | 'min | 'max | 'dense | 'ordinal, #:descending, #:seed.
(define (rank x #:method [method 'average] #:descending [descending #f] #:seed [seed #f])
  (expr-rank (->col-expr 'rank x) #:method method #:descending descending #:seed seed))

;; gather: pick rows by position (an Expr, a Series, or a list of ints).
(define (gather x indices)
  (expr-gather (->col-expr 'gather x) indices))

(module+ test
  (require rackunit (only-in threading ~>)
           polars/private/generic/core
           polars/private/generic/reductions   ; alias
           polars/private/generic/reshape)     ; with-columns / select
  (define df (dataframe (list (series '(30 10 50 20 40) #:name "x" #:dtype 'i64)
                              (series '("b" "a" "b" "a" "b") #:name "g"))))
  ;; rank is length-preserving -> with-columns
  (define ranked (~> df (with-columns (alias (rank "x" #:method 'dense) "r"))))
  ;; x = (30 10 50 20 40) -> dense ranks (3 1 5 2 4)
  (check-equal? (for/list ([i (in-range 5)]) (ref (ref ranked #:columns "r") i))
                '(3 1 5 2 4))
  ;; sort-by / gather collapse or reorder -> select (all columns share a length)
  (define sorted (select df (alias (sort-by "x" #:by "x") "xs")))
  (check-equal? (for/list ([i (in-range 5)]) (ref (ref sorted #:columns "xs") i))
                '(10 20 30 40 50))
  (define gathered (select df (alias (gather "x" '(0 2 4)) "xg")))
  (check-equal? (for/list ([i (in-range 3)]) (ref (ref gathered #:columns "xg") i))
                '(30 50 40)))