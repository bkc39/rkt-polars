#lang racket/base

;; Lazy Scan Options Batch 1: high-value CSV options and Parquet row limits.
;;
;; Inside `nix develop`:
;;   racket examples/25-lazy-scan-options-batch1.rkt

(require polars)

(define csv-path
  (build-path (find-system-path 'temp-dir) "rkt-polars-lazy-scan-options.csv"))

(with-output-to-file csv-path #:exists 'replace
  (lambda ()
    (displayln "ignore;999")
    (displayln "group;value")
    (displayln "a;10")
    (displayln "a;25")
    (displayln "b;7")
    (displayln "b;30")))

(define csv-result
  (lazyframe-collect
   (lazyframe-filter
    (lazyframe-scan-csv csv-path
                        #:has-header #t
                        #:separator #\;
                        #:skip-rows 1
                        #:n-rows 3)
    (expr-gt (col "value") 10))))

(displayln "csv scan with options:")
(display-dataframe csv-result)
(newline)

(define parquet-source
  (dataframe-new
   (list (series-new-i32 "x" '(1 2 3 4))
         (series-new-f64 "y" '(0.5 1.5 2.5 3.5)))))

(define parquet-path
  (build-path (find-system-path 'temp-dir) "rkt-polars-lazy-scan-options.parquet"))

(dataframe-write-parquet parquet-source parquet-path)

(define parquet-result
  (lazyframe-collect
   (lazyframe-scan-parquet parquet-path #:n-rows 2)))

(displayln "parquet scan with row limit:")
(display-dataframe parquet-result)
