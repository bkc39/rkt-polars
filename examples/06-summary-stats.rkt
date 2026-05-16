#lang racket/base

;; Per-column summary statistics — exercises Phase 4 reductions.
;;
;; Inside `nix develop`:
;;   racket examples/06-summary-stats.rkt

(require racket/file
         polars)

(define df
  (dataframe-new
   (list (series-new-str "city" '("Boston" "New York" "Chicago" "Houston"))
         (series-new-f64 "population_millions" '(0.65 8.8 2.7 2.3))
         (series-new-i32 "founded" '(1630 1624 1837 1837)))))

(displayln "input:")
(display-dataframe df)
(newline)

(define (summarize-i32 col)
  (define s (dataframe-column df col))
  (printf "~a (i32): min=~a max=~a mean=~a sum=~a n_unique=~a\n"
          col
          (series-min-i32 s)
          (series-max-i32 s)
          (series-mean-i32 s)
          (series-sum-i32 s)
          (series-n-unique s)))

(define (summarize-f64 col)
  (define s (dataframe-column df col))
  (printf "~a (f64): min=~a max=~a mean=~a sum=~a n_unique=~a\n"
          col
          (series-min-f64 s)
          (series-max-f64 s)
          (series-mean-f64 s)
          (series-sum-f64 s)
          (series-n-unique s)))

(define (summarize-str col)
  (define s (dataframe-column df col))
  (printf "~a (str): n_unique=~a len=~a\n"
          col
          (series-n-unique s)
          (series-len s)))

(summarize-str "city")
(summarize-f64 "population_millions")
(summarize-i32 "founded")
