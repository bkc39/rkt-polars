#lang racket/base

;; Time-zone-aware datetimes: gregor moments in a zoned column.
;;
;; A zoned column's dtype is '(datetime unit "Zone/Name") and its values are
;; gregor moments in that zone. `series` takes the zone of the first moment, as
;; Python does from aware datetimes; a fixed offset gives UTC. A UTC offset
;; parsed with %z converts to UTC. dt-convert-time-zone keeps each instant,
;; dt-replace-time-zone keeps each wall-clock time, resolving a time the clocks
;; skip or repeat as #:ambiguous and #:non-existent say. CSV writes the local
;; time and its offset.
;;
;; Inside `nix develop`:
;;   racket examples/68-temporal-time-zones.rkt

(require gregor
         racket/file
         polars)

(define landed
  (series (list (moment 2021 3 27 9 #:tz "Europe/Brussels")
                (moment 2021 3 28 9 #:tz "Europe/Brussels")
                (moment 2021 3 27 18 #:tz "Asia/Kathmandu"))
          #:name "landed"))
(displayln landed)
(printf "~s\n~s\n" (dtype landed) (series->list landed))
(printf "a fixed offset: ~s\n" (dtype (series (list (moment 2021 3 27 9 #:tz 3600)))))

(printf "in Kathmandu: ~s\n" (series->list (dt-convert-time-zone landed "Asia/Kathmandu")))
(printf "same clocks, naive: ~s\n" (series->list (dt-replace-time-zone landed #f)))

(define clocks (series (list (datetime 2021 10 31 2 30) (datetime 2021 3 28 2 30)) #:name "clock"))
(printf "repeated and skipped: ~s\n"
        (series->list (dt-replace-time-zone clocks "Europe/Brussels"
                                            #:ambiguous 'earliest #:non-existent 'null)))
(printf "~a\n" (with-handlers ([exn:fail? exn-message])
                 (dt-replace-time-zone clocks "Europe/Brussels")))

(define stamps
  (dataframe (list (series '("2021-03-27T00:00:00+0100" "2021-03-29T00:00:00+0200")
                           #:name "at"))))
(displayln (select stamps
                   (~> (str->datetime "at" #:format "%Y-%m-%dT%H:%M:%S%z") (alias "utc"))
                   (~> (str->datetime "at" #:format "%Y-%m-%dT%H:%M:%S%z")
                       (dt-convert-time-zone "Europe/Brussels")
                       (alias "brussels"))
                   (~> (str->datetime "at" #:time-zone "Asia/Tokyo") (alias "tokyo"))))

(define flights (dataframe (list landed (series '(1 2 3) #:name "n"))))
(displayln (filter flights (> (col "landed") (moment 2021 3 27 12 #:tz "Europe/Brussels"))))
(displayln (select flights (col '(datetime microseconds "Europe/Brussels"))))
(displayln (describe landed))

(define dir (make-temporary-directory "rkt-polars-example-~a"))
(define path (build-path dir "landed.csv"))
(write-csv (select flights "landed") path)
(display (file->string path))
(displayln (read-csv path #:try-parse-dates #t))
(delete-directory/files dir)

(printf "~a\n" (with-handlers ([exn:fail? exn-message])
                 (cast landed '(datetime microseconds "Europe/Brusels"))))
