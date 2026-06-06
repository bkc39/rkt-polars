#lang racket/base

;; Mirror of rust/examples/04_csv_roundtrip.rs.
;;
;; Build a frame with the smart `series`/`dataframe` constructors (example 02),
;; write it to CSV, read it back, and inspect the round-tripped frame with the
;; prefix-free UX vocabulary (`write-csv`, `read-csv`, `shape/values`,
;; `column-names`) — the same style as example 03.
;;
;; Inside `nix develop`:
;;   racket examples/04-csv-roundtrip.rkt

(require racket/file              ; make-temporary-file
         polars)

(define original
  (dataframe
   (list (series '("Boston" "New York" "Chicago") #:name "city")
         (series '(0.65 8.8 2.7)                  #:name "population_millions")
         (series '(1630 1624 1837)                #:name "founded" #:dtype 'i32))))

(define csv-path (make-temporary-file "rkt-polars-example-~a.csv"))

(write-csv original csv-path)
(define roundtrip (read-csv csv-path))

(printf "wrote csv to ~a\n" csv-path)

(define-values (rows cols) (shape/values roundtrip))
(printf "roundtrip shape=(~a, ~a)\n" rows cols)
(printf "roundtrip columns=~a\n" (column-names roundtrip))

(displayln "roundtrip:")
(displayln roundtrip)
(delete-file csv-path)
