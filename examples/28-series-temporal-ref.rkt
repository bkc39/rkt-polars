#lang racket/base

;; Temporal series-ref values for Date, Duration, and Time.
;;
;; Inside `nix develop`:
;;   racket examples/28-series-temporal-ref.rkt

(require gregor
         gregor/period
         polars)

(define dates
  (series-cast (series-new-i32 "d" (list 19724 polars-null -1))
               'date))
(define durations
  (series-cast (series-new-i64 "dur" (list 1500 polars-null -250))
               '(duration milliseconds)))
(define times
  (series-cast (series-new-i64 "tod" (list 11045123456789 polars-null 0))
               'time))

(printf "dates dtype=~a row0=~a row1=~a row2=~a\n"
        (series-dtype dates)
        (series-ref dates 0)
        (series-ref dates 1)
        (series-ref dates 2))
(printf "durations dtype=~a row0=~a row1=~a row2=~a\n"
        (series-dtype durations)
        (series-ref durations 0)
        (series-ref durations 1)
        (series-ref durations 2))
(printf "times dtype=~a row0=~a row1=~a row2=~a\n"
        (series-dtype times)
        (series-ref times 0)
        (series-ref times 1)
        (series-ref times 2))

(printf "duration row0 milliseconds=~a\n"
        (period-ref (series-ref durations 0) 'milliseconds))
(printf "time row0 nanoseconds=~a\n"
        (->nanoseconds (series-ref times 0)))
