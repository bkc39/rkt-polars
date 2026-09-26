#lang racket/base

(require racket/contract/base)

(provide
 (all-from-out lint/macros)
 (contract-out
  [polars-style refactoring-suite?]))

(require racket/list
         lint/macros
         resyntax/base
         resyntax/default-recommendations)

(define disabled-default-rules
  '(;; It recommends define-syntax-rule, which this project replaces with
    ;; define-syntax-parse-rule (syntax-parse-migrations).
    define-syntax-syntax-rules-to-define-syntax-rule
    ;; This project maps a function over one list with `map`, not `for/list`.
    map-to-for))

(define polars-style
  (refactoring-suite
   #:name 'polars-style
   #:rules (append (refactoring-suite-rules syntax-parse-migrations)
                   (filter-not (λ (rule) (memq (object-name rule) disabled-default-rules))
                               (refactoring-suite-rules default-recommendations)))))
