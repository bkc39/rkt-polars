#lang racket/base

;; CSV dates: #:try-parse-dates.
;;
;; By default a date column reads as strings. #:try-parse-dates #t reads ISO
;; dates as 'date, times of day as 'time and date-times as microsecond
;; datetimes, so the dt-* expressions apply straight away; a column that does
;; not parse stays a string.
;;
;; Inside `nix develop`:
;;   racket examples/44-csv-try-parse-dates.rkt

(require racket/file
         racket/runtime-path
         polars)

(define-runtime-path flights-tsv "../polars/scribblings/data/flights.tsv")

(define (dtypes df)
  (for/list ([name (column-names df)])
    (list name (dtype (ref df #:columns name)))))

(define plain (read-csv flights-tsv #:separator #\tab #:null-values "NA"))
(printf "time_hour without #:try-parse-dates: ~a\n" (dtype (ref plain #:columns "time_hour")))

(define flights
  (read-csv flights-tsv #:separator #\tab #:null-values "NA" #:try-parse-dates #t))
(printf "time_hour with #:try-parse-dates #t: ~a\n" (dtype (ref flights #:columns "time_hour")))
(displayln (~> flights
               (select "carrier" "time_hour" (alias (dt-hour "time_hour") "hour_of_day"))
               (filter (>= (col "hour_of_day") 16))))
(newline)

(define mixed (make-temporary-file "rkt-polars-dates-~a.csv"))
(display-lines-to-file '("day,at,stamp,label"
                         "2013-01-01,05:15:00,2013-01-01 05:15:00,early"
                         "2013-01-02,17:40:00,2013-01-02 17:40:00,late")
                       mixed #:exists 'replace)
(displayln "a date, a time of day, a datetime and a label:")
(displayln (dtypes (read-csv mixed #:try-parse-dates #t)))
(displayln (read-csv mixed #:try-parse-dates #t))
(delete-file mixed)
