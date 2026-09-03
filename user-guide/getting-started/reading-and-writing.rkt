#lang racket/base

;; rkt-polars user guide — Getting started: Reading & writing
;; Mirrors https://docs.pola.rs/user-guide/getting-started/#reading-writing
;; and reading_and_writing.py.
;;
;; Inside `nix develop`:
;;   racket user-guide/getting-started/reading-and-writing.rkt

(require gregor
         polars)

;; API gap: `series` cannot build a Date column from gregor dates, so build
;; datetimes and cast.
(define df
  (~> (dataframe
       (list (series '("Alice Archer" "Ben Brown" "Chloe Cooper" "Daniel Donovan")
                     #:name "name")
             (series (list (datetime 1997 1 10) (datetime 1985 2 15)
                           (datetime 1983 3 22) (datetime 1981 4 30))
                     #:name "birthdate")
             (series '(57.9 72.5 53.6 83.1) #:name "weight")
             (series '(1.56 1.77 1.65 1.75) #:name "height")))
      (with-columns (cast "birthdate" 'date))))

(displayln df)

(define csv-path (build-path (find-system-path 'temp-dir) "output.csv"))
(write-csv df csv-path)

;; API gap: read-csv has no try_parse_dates; parse the column afterwards.
(define df-csv
  (~> (read-csv csv-path)
      (with-columns (str-to-date "birthdate"))))

(displayln df-csv)
