#lang racket/base

;; Lazy IO Batch 1: scan CSV and Parquet directly into lazy pipelines.
;;
;; scan-csv / scan-parquet start a lazy plan straight from a file (no eager
;; read); the threaded ops just build the plan and `collect` runs it.
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
  (~> (scan-csv csv-path)
      (filter (> (col "value") 10))
      (group-by "group")
      (agg (alias (sum (cast (col "value") 'int32)) "total"))
      (sort "group")
      collect))

(displayln "csv scan pipeline:")
(displayln csv-result)
(delete-file csv-path)
(newline)

(define parquet-source
  (dataframe (list (series '(1 2 3 4)         #:name "x" #:dtype 'i32)
                   (series '(0.5 1.5 2.5 3.5) #:name "y" #:dtype 'f64))))

(define parquet-path (make-temporary-file "rkt-polars-lazy-io-~a.parquet"))

(write-parquet parquet-source parquet-path)

(define parquet-result
  (~> (scan-parquet parquet-path)
      (filter (>= (col "x") 2))
      (select (col "x") (alias (* (col "x") 10) "ten_x"))
      collect))

(displayln "parquet scan pipeline:")
(displayln parquet-result)
(delete-file parquet-path)
