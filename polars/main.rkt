#lang racket/base

(require polars/private/expr
         polars/private/foreign
         polars/private/generic
         polars/private/series
         (only-in threading ~> ~>> lambda~> lambda~>>))

;; Re-provide the thread-first macro so `(require polars)` yields `~>`, the
;; Racket spelling of Python/Polars method chaining:
;;   (~> df (filter (> (col "value") 15)) (group-by "group") (agg (sum (col "value"))))
(provide (all-from-out polars/private/expr)
         (all-from-out polars/private/foreign)
         (all-from-out polars/private/generic)
         (all-from-out polars/private/series)
         ~> ~>> lambda~> lambda~>>)
