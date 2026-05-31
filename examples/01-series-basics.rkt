#lang racket/base

;; Mirror of rust/examples/01_series_basics.rs.
;;
;; Inside `nix develop`:
;;   racket examples/01-series-basics.rkt

(require gregor
         polars)

;; The generic `series` constructor infers a dtype from the values, or takes an
;; explicit #:dtype (short spellings like 'i32 or canonical 'int32 both work).
(define ints
  (series '(1 2 3 4) #:name "ints" #:dtype 'i32))

(define floats
  (series '(1.5 2.0 4.25 8.0) #:name "floats"))

(define strings
  (series '("alpha" "beta" "gamma" "delta") #:name "strings"))

(define nullable-scores
  (series (list 10 polars-null 30) #:name "nullable_scores" #:dtype 'i32))

(define timestamps
  (series
   (list (datetime 2024 1 1  9  0 0)
         (datetime 2024 1 2  9 30 0)
         (datetime 2024 1 3 10  0 0)
         (datetime 2024 1 4 10 30 0))
   #:name "timestamps"))

;; `describe` dispatches on its argument: it prints a one-line summary for a
;; series and a shape + column/dtype summary for a dataframe.
(describe ints)
(describe floats)
(describe strings)
(describe nullable-scores)
(describe timestamps)

;; `ref` is the generic element/column accessor: on a series it indexes, on a
;; dataframe it selects a column.  Being data-first, it threads cleanly.
(printf "nullable_scores[0] = ~a\n" (ref nullable-scores 0))
(printf "nullable_scores[1] = ~a\n" (ref nullable-scores 1))

;; Mutation uses a trailing `!`.  `rename!` renames in place (matching Polars);
;; the un-suffixed `rename` returns a renamed copy via `clone`.
(rename! ints "ints_renamed")
(describe ints)

;; `sum`/`mean`/`min`/`max` dispatch on the series dtype.  `mean` promotes to
;; float64, so the mean of an integer series is a flonum.  On non-series
;; arguments these fall back to the usual numeric behaviour.
(printf "int sum = ~a\n"     (sum ints))
(printf "float mean = ~a\n"  (mean floats))
(printf "float max = ~a\n"   (max floats))
