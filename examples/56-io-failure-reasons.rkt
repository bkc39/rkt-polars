#lang racket/base

;; Failure reasons from reading, writing, scanning and collecting.
;;
;; A failed read or write names the operation and the path, then the cause:
;; the operating system's for a file that cannot be opened or created,
;; Polars' own for input it cannot parse.  A scan only builds a plan, so a
;; missing file or a bad query is reported by collect.
;;
;; Inside `nix develop`:
;;   racket examples/56-io-failure-reasons.rkt

(require racket/file              ; make-temporary-file
         polars)

(define (report label thunk)
  (printf "~a:\n  ~a\n\n" label
          (with-handlers ([exn:fail? exn-message])
            (thunk)
            "no error")))

(define df
  (dataframe (list (series '("a" "b" "c") #:name "k")
                   (series '(1 2 3) #:name "v"))))

(report "read-csv of a missing file"
        (lambda () (read-csv "/no/such/file.csv")))

(report "write-parquet into a missing directory"
        (lambda () (write-parquet df "/no/such/dir/out.parquet")))

(define csv-path (make-temporary-file "rkt-polars-not-parquet-~a.csv"))
(dynamic-wind
 void
 (lambda ()
   (write-csv df csv-path)
   (report "read-parquet of a file that is not parquet"
           (lambda () (read-parquet csv-path)))
   (report "read-ndjson of the same file"
           (lambda () (read-ndjson csv-path))))
 (lambda () (delete-file csv-path)))

(define plan (scan-csv "/no/such/file.csv"))
(printf "scan-csv of a missing file builds a plan: ~a\n\n" (lazyframe? plan))
(report "collect runs it and reports the file"
        (lambda () (collect plan)))

(report "collect of a plan that reads a missing column"
        (lambda () (~> df lazy (filter (> (col "nope") 1)) collect)))

(report "an eager select of a missing column, which runs the same way"
        (lambda () (select df (col "nope"))))
