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
         syntax/parse/define
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

(define-syntax-parse-rule (provide-public #:internal internal:id [mod:id name:id ...] ...)
  (begin
    (provide (except-out (all-from-out mod) name ...) ...)
    (module+ test (define internal '(name ... ...)))))

(provide-public
 #:internal internal-names
 [polars/private/expr ->expr/who expr-cast-to expr-lit-u64 expr-meta-output-name/raw
  expr-name-keep index-list/c lit/who lazyframe-collect/raw membership-list/c null-behavior/c
  rank-method/c]
 [polars/private/foreign
  allocator/or-fail call/foreign-error call/polars-reason check-enum-categories
  dataframe-drop-count dataframe-drop/raw dataframe-dropped decimal-ref
  define-owned-cpointer-type dropped? last-error-message
  _c-string _c-string/null _c-string-result _rsstr _rsstr-list str-block-drop
  str-block-drop-count
  owned-cpointer-types owned-pointer-accessor owned-pointer-arg
  owned-pointer? prop:owned-pointer raise-dropped release-owned
  series-drop-count series-drop/raw series-dropped write-owned
  dataframe-sort/raw frame-sort/c series-binary-byte-len series-copy-binary
  series-copy-decimal series-copy-str series-ref-bytes
  series-new-str/raw series-sort/raw series-str-byte-len sort-flags
  sort-flags/c sort-flags-mismatch string-has-nul?
  dtype-short-names
  series-cast-to series-cast-datetime-tz series-cast-datetime-tz/raw
  series-dt-convert-time-zone series-dt-convert-time-zone/raw
  series-dt-replace-time-zone series-dt-replace-time-zone/raw
  series-time-zone replace-zone-failure zoned-datetime-dtype?
  dataframe->string/raw printed-or-placeholder pivot-frame unpivot-frame series-value
  series-copy-i8 series-copy-i16 series-copy-i32 series-copy-i64 series-copy-u8 series-copy-u16
  series-copy-u32 series-copy-u64 series-copy-f32 series-copy-f64 series-copy-bool
  series-add/raw series-sub/raw series-mul/raw series-div/raw series-mod/raw
  series-eq/raw series-ne/raw series-gt/raw series-ge/raw series-lt/raw series-le/raw
  series-and/raw series-or/raw series-xor/raw series-not/raw
  series-add/who series-sub/who series-mul/who series-div/who series-mod/who
  series-eq/who series-ne/who series-gt/who series-ge/who series-lt/who series-le/who
  series-and/who series-or/who series-xor/who series-not/who
  dataframe-vstack/raw dataframe-hstack/raw
  dataframe-select/c dataframe-drop-columns/c dataframe-rename/raw
  dataframe-with-column/raw dataframe-new/raw provide-row-windows])

;; Re-provide the thread-first macro so `(require polars)` yields `~>`, the
;; Racket spelling of Python/Polars method chaining:
;;   (~> df (filter (> (col "value") 15)) (group-by "group") (agg (sum (col "value"))))
(provide dataframe-read-csv dataframe-write-csv lazyframe-scan-csv
         dataframe-read-json dataframe-write-json dataframe-read-json-lines
         dataframe-write-json-lines lazyframe-scan-json-lines
         dataframe-read-parquet dataframe-write-parquet lazyframe-scan-parquet
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
  (define (phase-0-exports mod)
    (define-values (variables syntaxes) (module->exports mod))
    (for*/list ([phase+names (in-list (append variables syntaxes))]
                #:when (eqv? (car phase+names) 0)
                [name (in-list (cdr phase+names))])
      (car name)))
  (define exported (phase-0-exports 'polars))
  (define c-integer-contracts
    (for/list ([name (in-list (phase-0-exports 'polars/private/c-integer))]
               #:when (regexp-match? #rx"/c$" (symbol->string name)))
      name))
  (check-not-false (memq 'cast exported))
  (check-not-false (memq 'series-new-str exported))
  (check-not-false (memq 'uint32/c c-integer-contracts))
  (for ([internal (in-list (append internal-names
                                    c-integer-contracts
                                    '(drop-owned owned-drop-registry register-owned-drop!
                                      expr-drop/raw expr-dropped
                                      lazyframe-drop/raw lazyframe-dropped
                                      define-frame-op/reason define-reasoned
                                      dataframe-select/c dataframe-drop-columns/c
                                      dataframe-rename/raw dataframe-with-column/raw
                                      dataframe-new/raw expr-lit-u64 null-behavior/c
                                      rank-method/c provide-row-windows)))])
    (check-false (memq internal exported) (format "~a is internal" internal)))
  (for ([name (in-list exported)])
    (check-false (regexp-match? #rx"^series-copy-|-byte-len$|^series-ref-bytes$"
                                (symbol->string name))
                 (format "~a is internal" name))))

(module+ test
  (require racket/match
           racket/runtime-path
           (only-in setup/getinfo get-info/full)
           (only-in version/utils valid-version?))
  (define-runtime-path collection-dir ".")
  (define-runtime-path package-dir "..")
  (define polars-version ((get-info/full collection-dir) 'version))
  (check-pred valid-version? polars-version)
  (match (get-info/full package-dir)
    [#f (void)]
    [root-info (check-equal? (root-info 'version) polars-version)]))
