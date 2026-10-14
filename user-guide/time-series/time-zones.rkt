#lang racket/base

;; rkt-polars user guide — Time series: Time zones
;; Mirrors https://docs.pola.rs/user-guide/transformations/time-series/timezones/
;; and time_zones.py.
;;
;; Inside `nix develop`:
;;   racket user-guide/time-series/time-zones.rkt

(require gregor
         polars)

;; --- converting and replacing time zones ---------------------------------
(define ts '("2021-03-27 03:00" "2021-03-28 03:00"))
(define tz-naive
  (~> (dataframe (list (series ts #:name "tz_naive")))
      (select (str->datetime "tz_naive"))
      (ref "tz_naive")))
(define tz-aware (~> tz-naive (dt-replace-time-zone "UTC") (rename "tz_aware")))
(define time-zones-df (dataframe (list tz-naive tz-aware)))
(displayln time-zones-df)

(displayln
 (select time-zones-df
         (~> (col "tz_aware") (dt-replace-time-zone "Europe/Brussels")
             (alias "replace time zone"))
         (~> (col "tz_aware") (dt-convert-time-zone "Asia/Kathmandu")
             (alias "convert time zone"))
         (~> (col "tz_aware") (dt-replace-time-zone #f) (alias "unset time zone"))))

;; --- zoned values from Racket (no upstream counterpart) -------------------
;; Python's aware datetimes play the part of gregor's moments.
(define landings
  (series (list (moment 2021 3 27 9 #:tz "Europe/Brussels")
                (moment 2021 3 28 9 #:tz "Europe/Brussels")
                (moment 2021 3 27 18 #:tz "Asia/Kathmandu"))
          #:name "landed"))
(displayln landings)
(writeln (series->list landings))
(writeln (dtype (series (list (moment 2021 3 27 9 #:tz 3600)))))
