#lang racket/base

(require polars/private/expr
         polars/private/foreign
         polars/private/generic
         polars/private/series
         (only-in threading ~> ~>> lambda~> lambda~>>)
         ;; generic exports its dispatching and/or/not/xor via `rename-out`, and
         ;; `all-from-out` below silently drops those (they collide with this
         ;; module language's own racket/base `and`/`or`/`not`).  Pull them in
         ;; under private aliases so we can re-export them explicitly.
         (only-in polars/private/generic
                  [and polars:and] [or polars:or]
                  [not polars:not] [xor polars:xor]
                  [+ polars:+] [- polars:-] [* polars:*] [/ polars:/]
                  [when polars:when]))

;; Re-provide the thread-first macro so `(require polars)` yields `~>`, the
;; Racket spelling of Python/Polars method chaining:
;;   (~> df (filter (> (col "value") 15)) (group-by "group") (agg (sum (col "value"))))
(provide (all-from-out polars/private/expr)
         (all-from-out polars/private/foreign)
         (all-from-out polars/private/generic)
         (all-from-out polars/private/series)
         ~> ~>> lambda~> lambda~>>
         (rename-out [polars:and and] [polars:or or]
                     [polars:not not] [polars:xor xor]
                     [polars:+ +] [polars:- -] [polars:* *] [polars:/ /]
                     [polars:when when]))
