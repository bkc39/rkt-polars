#lang racket/base

;; Duration columns from gregor periods.
;;
;; A period without years or months has a fixed length (a day is 24 hours, as
;; in Polars), so a list of them is a duration column, microseconds as
;; Python's timedelta gives, or nanoseconds when a value carries them and a
;; nanosecond column (about 292 years either way) holds every value. A
;; duration reads back as a period in the column's unit. Years and months have
;; no fixed length and are refused.
;;
;; Inside `nix develop`:
;;   racket examples/65-temporal-durations.rkt

(require gregor/period
         polars)

(define waits (series (list (hours 1) (minutes 90) (period (days 1) (hours 2)) polars-null)
                      #:name "wait"))
(printf "~s ~s\n" (dtype waits) (series->list waits))

(define precise (series (list (nanoseconds 1500) (milliseconds 2)) #:name "lag"))
(printf "~s ~s\n" (dtype precise) (series->list precise))

(define long (series (list (nanoseconds 1500) (weeks 20000)) #:name "lag"))
(printf "~s ~s\n" (dtype long) (series->list long))

(define in-ms (series (list (seconds 90)) #:name "wait" #:dtype '(duration milliseconds)))
(printf "~s ~s\n" (dtype in-ms) (series->list in-ms))

(displayln (filter (dataframe (list waits)) (> (col "wait") (minutes 60))))

(printf "a month: ~a\n"
        (with-handlers ([exn:fail? exn-message])
          (series (list (months 1)) #:dtype '(duration microseconds))))
