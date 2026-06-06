#lang racket/base

;; Expr String Batch 1: string predicates and case conversion in lazy plans.
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
  (lazyframe-collect
   (lazyframe-with-columns
    (lazyframe-scan-csv csv-path)
    (list (expr-alias (expr-str-to-lowercase (col "name")) "lower_name")
          (expr-alias (expr-str-to-uppercase (col "name")) "upper_name")
          (expr-alias (expr-str-contains (col "name") "a") "has_a")
          (expr-alias (expr-str-starts-with (col "name") "A") "starts_a")
          (expr-alias (expr-str-ends-with (col "name") "ta") "ends_ta")))))

(display-dataframe result)
(delete-file csv-path)
