#lang racket/base

;; Temporal series from gregor values.
;;
;; `series` infers the dtype from gregor values as Python does from date, time
;; and datetime: a date column, a time column, and a microsecond datetime
;; column, or a nanosecond one when a value carries nanoseconds and a
;; nanosecond column (1677 to 2262) holds every value; otherwise the
;; nanoseconds are floored. #:dtype picks another unit, flooring what the unit
;; cannot hold. A moment makes a zoned column (example 68).
;;
;; Inside `nix develop`:
;;   racket examples/62-temporal-series-from-gregor.rkt

(require gregor
         (only-in gregor/time time)
         polars)

(define birthdays (series (list (date 1997 1 10) polars-null (date 1981 4 30)) #:name "d"))
(define alarms (series (list (time 6 30) (time 7 15 0 500000000)) #:name "t"))
(define stamps (series (list (datetime 2013 1 1 5 6 7 123456000)) #:name "dt"))
(define fine (series (list (datetime 2013 1 1 5 6 7 123456789)) #:name "dt"))
(define wide (series (list (datetime 2013 1 1 5 6 7 123456789) (datetime 1600 1 1)) #:name "wide"))

(for ([s (list birthdays alarms stamps fine wide)])
  (printf "~a: ~s ~s\n" (series-name s) (dtype s) (series->list s)))

(define coarse
  (series (list (datetime 2013 1 1 5 6 7 123456789)) #:name "dt" #:dtype '(datetime milliseconds)))
(printf "as milliseconds: ~s ~s\n" (dtype coarse) (series->list coarse))

(displayln (dataframe (list birthdays (series '(1 2 3) #:name "n"))))
