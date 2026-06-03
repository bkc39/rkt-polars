#lang racket/base

;; Per-column summary statistics via `describe` — the Racket spelling of Polars'
;; df.describe().  It returns a summary dataframe (count, null_count, mean, std,
;; min, quartiles, max), which prints as a table.
;;
;; Inside `nix develop`:
;;   racket examples/06-summary-stats.rkt

(require polars)

(define df
  (dataframe
   (list (series '("Boston" "New York" "Chicago" "Houston") #:name "city")
         (series '(0.65 8.8 2.7 2.3)                         #:name "population_millions")
         (series '(1630 1624 1837 1837)                      #:name "founded" #:dtype 'i32))))

(displayln "input:")
(displayln df)
(newline)

(define summary (describe df))
(displayln "summary:")
(displayln summary)
