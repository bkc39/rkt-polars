#lang racket/base

;; rkt-polars user guide — Getting started: Reading & writing
;; Mirrors https://docs.pola.rs/user-guide/getting-started/#reading-writing
;; and reading_and_writing.py.
;;
;; Inside `nix develop`:
;;   racket user-guide/getting-started/reading-and-writing.rkt

(require gregor
         polars)

(define df
  (dataframe [name '("Alice Archer" "Ben Brown" "Chloe Cooper" "Daniel Donovan")]
             [birthdate (list (date 1997 1 10) (date 1985 2 15) (date 1983 3 22) (date 1981 4 30))]
             [weight '(57.9 72.5 53.6 83.1)]
             ["height" '(1.56 1.77 1.65 1.75)]))

(displayln df)

(define csv-path (build-path (find-system-path 'temp-dir) "output.csv"))
(write-csv df csv-path)

(define df-csv (read-csv csv-path #:try-parse-dates #t))
(delete-file csv-path)

(displayln df-csv)
