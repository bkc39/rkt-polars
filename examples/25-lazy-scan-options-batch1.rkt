#lang racket/base

;; Lazy Scan Options Batch 1: high-value CSV options and Parquet row limits.
;;
;; scan-csv / scan-parquet take the same keyword options as Polars'
;; pl.scan_csv / pl.scan_parquet, and the lazy plan threads straight into
;; filter / collect.
;;
;; Inside `nix develop`:
;;   racket examples/25-lazy-scan-options-batch1.rkt

(require racket/file              ; make-temporary-file
         polars)

(define csv-path (make-temporary-file "rkt-polars-lazy-scan-options-~a.csv"))

(with-output-to-file csv-path #:exists 'replace
  (lambda ()
    (displayln "ignore;999")
    (displayln "group;value")
    (displayln "a;10")
    (displayln "a;25")
    (displayln "b;7")
    (displayln "b;30")))

(define csv-result
  (~> (scan-csv csv-path
                #:has-header #t
                #:separator #\;
                #:skip-rows 1
                #:n-rows 3)
      (filter (> (col "value") 10))
      collect))

(displayln "csv scan with options:")
(displayln csv-result)
(delete-file csv-path)
(newline)

(define parquet-source
  (dataframe (list (series '(1 2 3 4)         #:name "x" #:dtype 'i32)
                   (series '(0.5 1.5 2.5 3.5) #:name "y" #:dtype 'f64))))

(define parquet-path (make-temporary-file "rkt-polars-lazy-scan-options-~a.parquet"))

(write-parquet parquet-source parquet-path)

(define parquet-result
  (~> (scan-parquet parquet-path #:n-rows 2) collect))

(displayln "parquet scan with row limit:")
(displayln parquet-result)
(delete-file parquet-path)
