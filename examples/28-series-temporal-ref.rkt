#lang racket/base

;; Temporal series-ref values for Date, Duration, and Time.
;;
;; cast changes a series' dtype; ref then returns gregor values (a date, a
;; time-period for Duration, a time-of-day for Time).
;;
;; Inside `nix develop`:
;;   racket examples/28-series-temporal-ref.rkt

(require gregor
         gregor/period
         polars)

(define dates
  (cast (series (list 19724 polars-null -1) #:name "d" #:dtype 'i32) 'date))
(define durations
  (cast (series (list 1500 polars-null -250) #:name "dur" #:dtype 'i64)
        '(duration milliseconds)))
(define times
  (cast (series (list 11045123456789 polars-null 0) #:name "tod" #:dtype 'i64)
        'time))

(printf "dates dtype=~a row0=~a row1=~a row2=~a\n"
        (dtype dates) (ref dates 0) (ref dates 1) (ref dates 2))
(printf "durations dtype=~a row0=~a row1=~a row2=~a\n"
        (dtype durations) (ref durations 0) (ref durations 1) (ref durations 2))
(printf "times dtype=~a row0=~a row1=~a row2=~a\n"
        (dtype times) (ref times 0) (ref times 1) (ref times 2))

(printf "duration row0 milliseconds=~a\n"
        (period-ref (ref durations 0) 'milliseconds))
(printf "time row0 nanoseconds=~a\n"
        (->nanoseconds (ref times 0)))
