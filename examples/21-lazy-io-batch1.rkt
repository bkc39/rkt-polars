#lang racket/base

;; Lazy IO Batch 1: scan CSV and Parquet directly into lazy pipelines.
;;
;; Inside `nix develop`:
;;   racket examples/21-lazy-io-batch1.rkt

(require racket/file              ; make-temporary-file
         polars)

(define csv-path (make-temporary-file "rkt-polars-lazy-io-~a.csv"))

(with-output-to-file csv-path #:exists 'replace
  (lambda ()
    (displayln "group,value")
    (displayln "a,10")
    (displayln "a,25")
    (displayln "b,7")
    (displayln "b,30")))

(define csv-result
  (lazyframe-collect
   (lazyframe-sort
    (lazyframe-group-by-agg
     (lazyframe-filter (lazyframe-scan-csv csv-path)
                       (expr-gt (col "value") 10))
     '("group")
     (list (expr-alias (expr-sum (expr-cast (col "value") 'int32))
                       "total")))
    '("group"))))

(displayln "csv scan pipeline:")
(display-dataframe csv-result)
(delete-file csv-path)
(newline)

(define parquet-source
  (dataframe-new
   (list (series-new-i32 "x" '(1 2 3 4))
         (series-new-f64 "y" '(0.5 1.5 2.5 3.5)))))

(define parquet-path (make-temporary-file "rkt-polars-lazy-io-~a.parquet"))

(dataframe-write-parquet parquet-source parquet-path)

(define parquet-result
  (lazyframe-collect
   (lazyframe-select
    (lazyframe-filter (lazyframe-scan-parquet parquet-path)
                      (expr-ge (col "x") 2))
    (list (col "x")
          (expr-alias (expr-mul (col "x") 10) "ten_x")))))

(displayln "parquet scan pipeline:")
(display-dataframe parquet-result)
(delete-file parquet-path)
