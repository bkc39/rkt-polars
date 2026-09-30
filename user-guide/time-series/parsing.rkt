#lang racket/base

;; rkt-polars user guide — Time series: Parsing
;; Mirrors https://docs.pola.rs/user-guide/transformations/time-series/parsing/
;; and parsing.py.
;;
;; Inside `nix develop`:
;;   racket user-guide/time-series/parsing.rkt

(require gregor
         racket/runtime-path
         polars)

(define-runtime-path data-dir "../../polars/scribblings/data")
(define apple-stock (build-path data-dir "apple_stock.csv"))

;; --- parsing dates from a file -------------------------------------------
(displayln (read-csv apple-stock #:try-parse-dates #t))

;; --- casting strings to dates --------------------------------------------
(define df
  (~> (read-csv apple-stock)
      (with-columns (str->date "Date" #:format "%Y-%m-%d"))))
(displayln df)

;; --- extracting date features --------------------------------------------
(displayln (with-columns df (~> (col "Date") dt-year (alias "year"))))

;; --- dates from Racket values (no upstream counterpart) ------------------
(define closes (series (list (date 1995 10 16) (date 1995 11 1)) #:name "Date"))
(displayln closes)
(writeln (series->list closes))

;; API gap: no time zones, so no mixed-offsets example: str->datetime drops an
;; offset parsed with %z where Python converts to UTC; no dt.convert_time_zone.
