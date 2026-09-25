#lang racket/base

;; Reading several files at once: glob patterns on read-csv and read-parquet.
;;
;; A path with *, ? or [...] is a pattern: every matching file is read and the
;; results are stacked in sorted filename order, eagerly with read-csv and
;; read-parquet as lazily with scan-csv and scan-parquet. Row options apply to
;; the whole read. #:glob #f takes a CSV path literally, a pattern that
;; matches nothing is an error, and an eager read of a directory is too.
;;
;; Inside `nix develop`:
;;   racket examples/45-eager-glob.rkt

(require racket/file
         polars)

(define (report thunk)
  (with-handlers ([exn:fail? (lambda (e) (displayln (exn-message e)))])
    (thunk)))

(define dir (make-temporary-directory "rkt-polars-glob-~a"))
(define (in-dir name) (build-path dir name))

(for ([month '("2013-03" "2013-01" "2013-02")]
      [delays '(("EWR,12" "JFK,-3") ("EWR,2" "LGA,4") ("JFK,30" "LGA,-1"))])
  (display-lines-to-file (cons "origin,dep_delay" delays)
                         (in-dir (format "flights-~a.csv" month)) #:exists 'replace)
  (write-parquet (read-csv (in-dir (format "flights-~a.csv" month)))
                 (in-dir (format "flights-~a.parquet" month))))

(displayln "read-csv \"flights-*.csv\", sorted by file name:")
(displayln (read-csv (in-dir "flights-*.csv")))
(displayln "#:n-rows 3 counts across the files:")
(displayln (read-csv (in-dir "flights-*.csv") #:n-rows 3))
(displayln "read-parquet \"flights-2013-0[12].parquet\":")
(displayln (read-parquet (in-dir "flights-2013-0[12].parquet")))
(displayln "scan-csv over the same pattern, then a query:")
(displayln (~> (scan-csv (in-dir "flights-*.csv"))
               (group-by "origin")
               (agg (mean "dep_delay"))
               (sort "origin")
               collect))
(newline)

(display-lines-to-file '("origin,dep_delay" "EWR,99") (in-dir "draft[1].csv") #:exists 'replace)
(displayln "a literal [ in a name: #:glob #f")
(displayln (read-csv (in-dir "draft[1].csv") #:glob #f))
(displayln "a pattern that matches nothing:")
(report (lambda () (read-csv (in-dir "*.tsv"))))
(displayln "a directory:")
(report (lambda () (read-csv dir)))

(delete-directory/files dir)
