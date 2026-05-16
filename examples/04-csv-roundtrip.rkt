#lang racket/base

;; Mirror of rust/examples/04_csv_roundtrip.rs.
;;
;; Inside `nix develop`:
;;   racket examples/04-csv-roundtrip.rkt

(require racket/file
         polars)

(define original
  (dataframe-new
   (list (series-new-str "city" '("Boston" "New York" "Chicago"))
         (series-new-f64 "population_millions" '(0.65 8.8 2.7))
         (series-new-i32 "founded" '(1630 1624 1837)))))

(define csv-path
  (build-path (find-system-path 'temp-dir) "rkt-polars-example.csv"))

(dataframe-write-csv original csv-path)

(define roundtrip (dataframe-read-csv csv-path))

(printf "wrote csv to ~a\n" csv-path)
(printf "roundtrip shape=~a\n"
        (call-with-values (lambda () (dataframe-shape roundtrip)) cons))
(printf "roundtrip columns=~a\n"
        (for/list ([i (in-range (dataframe-width roundtrip))])
          (dataframe-column-name roundtrip i)))
(displayln "roundtrip:")
(display-dataframe roundtrip)
