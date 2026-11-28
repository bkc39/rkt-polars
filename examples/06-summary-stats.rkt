#lang racket/base

;; Per-column summary statistics via `describe` — the Racket spelling of Polars'
;; df.describe().  It returns a summary dataframe (count, null_count, mean, std,
;; min, quartiles, max), which prints as a table.
;;
;; Inside `nix develop`:
;;   racket examples/06-summary-stats.rkt

(require polars)

(define df
  (dataframe [city '("Boston" "New York" "Chicago" "Houston")]
             [population_millions '(0.65 8.8 2.7 2.3)]
             [founded '(1630 1624 1837 1837) #:dtype 'i32]))

(displayln "input:")
(displayln df)
(newline)

(define summary (describe df))
(displayln "summary:")
(displayln summary)
