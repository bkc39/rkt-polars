#lang racket/base

;; Expr String Batch 1: string predicates and case conversion in lazy plans.
;;
;; The `.str` ops are prefix-free and data-first, and a bare column-name
;; string is auto-lifted to `(col ...)`, so they thread cleanly: the plan
;; is just scan-csv -> with-columns -> collect.
;;
;; Inside `nix develop`:
;;   racket examples/22-expr-string-batch1.rkt

(require racket/file              ; make-temporary-file
         polars)

(define csv-path (make-temporary-file "rkt-polars-expr-string-~a.csv"))

(with-output-to-file csv-path #:exists 'replace
  (lambda ()
    (displayln "name,value")
    (displayln "Alpha,1")
    (displayln "beta,2")
    (displayln "Gamma,3")
    (displayln "delta,4")))

(define result
  (~> (scan-csv csv-path)
      (with-columns
        (~> "name" str-to-lowercase (alias "lower_name"))
        (~> "name" str-to-uppercase (alias "upper_name"))
        (~> "name" (str-contains "a") (alias "has_a"))
        (~> "name" (str-starts-with "A") (alias "starts_a"))
        (~> "name" (str-ends-with "ta") (alias "ends_ta")))
      collect))

(displayln result)
(delete-file csv-path)
