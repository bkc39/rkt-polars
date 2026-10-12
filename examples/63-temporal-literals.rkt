#lang racket/base

;; Temporal literals: gregor values in expressions.
;;
;; `lit`, and so every comparison, `is-between` and `is-in`, takes a gregor
;; date, time, datetime or period, as Python's expressions take date, time,
;; datetime and timedelta. A date column compares with a datetime as midnight
;; of its day.
;;
;; Inside `nix develop`:
;;   racket examples/63-temporal-literals.rkt

(require gregor
         (only-in gregor/period hours minutes)
         (only-in gregor/time time)
         polars)

(define flights
  (dataframe
   (list (series (list (date 2013 5 31) (date 2013 6 1) (date 2013 6 2) (date 2013 6 3))
                 #:name "day")
         (series (list (time 5 40) (time 17 5) (time 23 59) (time 6 0)) #:name "departs")
         (series (list (hours 2) (minutes 45) (hours 5) (minutes 90)) #:name "flight_time"))))

(displayln (filter flights (> (col "day") (date 2013 6 1))))
(displayln (filter flights (is-between "day" (date 2013 6 1) (datetime 2013 6 2 12))))
(displayln (filter flights (is-in "day" (list (date 2013 5 31) (date 2013 6 3)))))
(displayln (filter flights (< (col "departs") (time 12))))
(displayln (filter flights (>= (col "flight_time") (hours 1))))

(printf "a series against a date: ~s\n" (series->list (= (ref flights "day") (date 2013 6 2))))
(displayln (select flights (alias (lit (date 2013 6 1)) "since")
                           (alias (lit (datetime 2013 6 1 12 30)) "noon")))
(printf "lit of a date prints as ~a\n" (lit (date 2013 6 1)))
