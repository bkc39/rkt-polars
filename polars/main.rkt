#lang racket/base

(require (only-in polars/private/csv dataframe-read-csv lazyframe-scan-csv)
         polars/private/expr
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
                  [when polars:when]
                  [abs polars:abs] [round polars:round] [floor polars:floor]
                  [sqrt polars:sqrt] [exp polars:exp] [log polars:log]))

;; Re-provide the thread-first macro so `(require polars)` yields `~>`, the
;; Racket spelling of Python/Polars method chaining:
;;   (~> df (filter (> (col "value") 15)) (group-by "group") (agg (sum (col "value"))))
(provide dataframe-read-csv lazyframe-scan-csv
         (all-from-out polars/private/expr)
         (except-out (all-from-out polars/private/foreign)
                     allocator/or-fail call/foreign-error check-enum-categories
                     dataframe-drop-count decimal-ref last-error-message owned-pointer-accessor
                     owned-pointer-arg owned-pointer? prop:owned-pointer series-drop-count
                     dataframe-sort/raw frame-sort/c series-copy-decimal series-copy-str
                     series-new-str/raw series-sort/raw series-str-byte-len sort-flags
                     sort-flags/c sort-flags-mismatch string-has-nul?)
         (all-from-out polars/private/generic)
         (all-from-out polars/private/series)
         ~> ~>> lambda~> lambda~>>
         (rename-out [polars:and and] [polars:or or]
                     [polars:not not] [polars:xor xor]
                     [polars:+ +] [polars:- -] [polars:* *] [polars:/ /]
                     [polars:when when]
                     [polars:abs abs] [polars:round round] [polars:floor floor]
                     [polars:sqrt sqrt] [polars:exp exp] [polars:log log]))

(module+ test
  (require rackunit)

  (define exported
    (let-values ([(variables syntaxes) (module->exports 'polars)])
      (for*/list ([phase+names (in-list (append variables syntaxes))]
                  #:when (eqv? (car phase+names) 0)
                  [name+origins (in-list (cdr phase+names))])
        (car name+origins))))
  (check-not-false (memq 'series-new-str exported))
  (for ([internal (in-list '(check-enum-categories decimal-ref series-copy-decimal
                             series-copy-str series-new-str/raw series-str-byte-len
                             string-has-nul?))])
    (check-false (memq internal exported) (format "(require polars) exports ~a" internal))))
