#lang racket/base

(require (only-in polars/private/csv dataframe-read-csv dataframe-write-csv lazyframe-scan-csv)
         (only-in polars/private/json
                  dataframe-read-json dataframe-write-json dataframe-read-json-lines
                  dataframe-write-json-lines lazyframe-scan-json-lines)
         (only-in polars/private/parquet
                  dataframe-read-parquet dataframe-write-parquet lazyframe-scan-parquet)
         polars/private/expr
         polars/private/foreign
         polars/private/generic
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
(provide dataframe-read-csv dataframe-write-csv lazyframe-scan-csv
         dataframe-read-json dataframe-write-json dataframe-read-json-lines
         dataframe-write-json-lines lazyframe-scan-json-lines
         dataframe-read-parquet dataframe-write-parquet lazyframe-scan-parquet
         (except-out (all-from-out polars/private/expr) expr-cast-to expr-meta-output-name/raw)
         (except-out (all-from-out polars/private/foreign)
                     allocator/or-fail call/foreign-error check-enum-categories
                     dataframe-drop-count decimal-ref last-error-message owned-pointer-accessor
                     owned-pointer-arg owned-pointer? prop:owned-pointer series-drop-count
                     dataframe-sort/raw frame-sort/c series-copy-decimal series-copy-str
                     series-new-str/raw series-sort/raw series-str-byte-len sort-flags
                     sort-flags/c sort-flags-mismatch string-has-nul?
                     dtype-short-names
                     series-cast-to series-cast-datetime-tz series-cast-datetime-tz/raw
                     series-dt-convert-time-zone series-dt-convert-time-zone/raw
                     series-dt-replace-time-zone series-dt-replace-time-zone/raw
                     series-time-zone replace-zone-failure zoned-datetime-dtype?)
         (all-from-out polars/private/generic)
         ~> ~>> lambda~> lambda~>>
         (rename-out [polars:and and] [polars:or or]
                     [polars:not not] [polars:xor xor]
                     [polars:+ +] [polars:- -] [polars:* *] [polars:/ /]
                     [polars:when when]
                     [polars:abs abs] [polars:round round] [polars:floor floor]
                     [polars:sqrt sqrt] [polars:exp exp] [polars:log log]))

(module+ test
  (require rackunit)
  (define-values (variables syntaxes) (module->exports 'polars))
  (define exported
    (for*/list ([phase+names (in-list (append variables syntaxes))]
                #:when (eqv? (car phase+names) 0)
                [name (in-list (cdr phase+names))])
      (car name)))
  (check-not-false (memq 'cast exported))
  (check-not-false (memq 'series-new-str exported))
  (for ([internal '(dtype-short-names expr-meta-output-name/raw allocator/or-fail
                    call/foreign-error prop:owned-pointer sort-flags-mismatch
                    check-enum-categories decimal-ref series-copy-decimal series-copy-str
                    series-new-str/raw series-str-byte-len string-has-nul?)])
    (check-false (memq internal exported) (format "~a is internal" internal))))
