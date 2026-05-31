#lang racket/base

;; rkt-polars user guide — Reading & writing
;; Mirrors https://docs.pola.rs/user-guide/getting-started/ (the "Reading &
;; writing" section) and reading_and_writing.py in this directory.
;;
;; Inside `nix develop`:
;;   racket user-guide/getting-started/reading-and-writing.rkt

(require gregor
         racket/file
         polars)

(define df
  (dataframe-new
   (list (series '(1 2 3) #:name "integer" #:dtype 'i64)
         (series (list (datetime 2025 1 1) (datetime 2025 1 2)
                       (datetime 2025 1 3))
                 #:name "date")
         (series '(4.0 5.0 6.0) #:name "float")
         (series '("a" "b" "c") #:name "string"))))

(displayln "original:")
(display-dataframe df)
(newline)

(define tmp (find-system-path 'temp-dir))

;; --- CSV ----------------------------------------------------------------
(define csv-path (build-path tmp "rkt-polars-guide.csv"))
(dataframe-write-csv df csv-path)
(printf "wrote ~a\n" csv-path)
(displayln "read back from CSV:")
(display-dataframe (dataframe-read-csv csv-path))
(newline)

;; --- Parquet ------------------------------------------------------------
(define parquet-path (build-path tmp "rkt-polars-guide.parquet"))
(dataframe-write-parquet df parquet-path)
(printf "wrote ~a\n" parquet-path)
(displayln "read back from Parquet:")
(display-dataframe (dataframe-read-parquet parquet-path))
(newline)

;; --- JSON (newline-delimited) ------------------------------------------
(define jsonl-path (build-path tmp "rkt-polars-guide.jsonl"))
(dataframe-write-json-lines df jsonl-path)
(printf "wrote ~a\n" jsonl-path)
(displayln "read back from JSON lines:")
(display-dataframe (dataframe-read-json-lines jsonl-path))
