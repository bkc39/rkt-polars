#lang racket/base

;; rkt-polars user guide — IO: Multiple files
;; Mirrors https://docs.pola.rs/user-guide/io/multiple/ and multiple.py.
;;
;; Inside `nix develop`:
;;   racket user-guide/io/multiple.rkt

(require racket/file
         file/glob
         polars)

(define dir (make-temporary-directory "polars-guide-~a"))

;; --- create ------------------------------------------------------------------
(define df
  (dataframe (list (series '(1 2 3) #:name "foo")
                   (series (list polars-null "ham" "spam") #:name "bar"))))
(for ([i (in-range 5)])
  (write-csv df (build-path dir (format "my_many_files_~a.csv" i))))

;; --- read into a single dataframe ------------------------------------------
(displayln (read-csv (build-path dir "my_many_files_*.csv")))

(for ([i (in-range 2)])
  (write-parquet df (build-path dir (format "my_many_files_~a.parquet" i))))
(displayln (height (read-parquet (build-path dir "my_many_files_*.parquet"))))

;; API gap: no show_graph, so the query plan cannot be drawn.

;; --- read and process in parallel -------------------------------------------
;; API gaps: no collect_all (the plans run one after another) and no pl.len()
;; (a column's count stands in).
(for ([file (sort (glob (build-path dir "my_many_files_*.csv")) path<?)])
  (displayln (~> (scan-csv file)
                 (group-by "bar")
                 (agg (alias (count "foo") "len") (sum "foo"))
                 (sort "bar")
                 collect)))

(delete-directory/files dir)
