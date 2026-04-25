#lang racket/base

;; Mirror of rust/examples/01_series_basics.rs.
;;
;; Inside `nix develop`:
;;   racket examples/01-series-basics.rkt

(require gregor
         polars/private/foreign
         polars/private/series)

(define (describe-series s)
  (printf "name=~s len=~a dtype=~a nulls=~a\n"
          (series-name s)
          (series-len s)
          (series-dtype s)
          (series-null-count s)))

(define ints
  (series-new-i32 "ints" '(1 2 3 4)))

(define floats
  (series-new-f64 "floats" '(1.5 2.0 4.25 8.0)))

(define strings
  (series-new-str "strings" '("alpha" "beta" "gamma" "delta")))

(define timestamps
  (series-new-datetime
   "timestamps"
   (list (datetime 2024 1 1  9  0 0)
         (datetime 2024 1 2  9 30 0)
         (datetime 2024 1 3 10  0 0)
         (datetime 2024 1 4 10 30 0))))

(describe-series ints)
(describe-series floats)
(describe-series strings)
(describe-series timestamps)

;; Rename: rkt-polars' rename mutates in place, matching Polars' API.
;; The Rust example uses .clone() to keep the original; we don't have
;; series-clone yet, so just rename the original here.
(series-rename ints "ints_renamed")
(describe-series ints)

(printf "int sum = ~a\n"     (series-sum-i32 ints))
(printf "float mean = ~a\n"  (series-mean-f64 floats))
(printf "float max = ~a\n"   (series-max-f64 floats))
