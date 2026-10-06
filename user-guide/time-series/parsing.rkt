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

;; --- parsing dates from a file: in io/csv.rkt -----------------------------

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
(displayln (series (list (datetime 1995 10 16 9 30 0 123456789) (datetime 1995 11 1))
                   #:name "precise"))
(displayln (series (list (datetime 1995 10 16 9 30 0 123456789) (datetime 1600 1 1))
                   #:name "wide"))

;; --- mixed offsets -------------------------------------------------------
(define mixed
  (dataframe (list (series '("2021-03-27T00:00:00+0100" "2021-03-28T00:00:00+0100"
                             "2021-03-29T00:00:00+0200" "2021-03-30T00:00:00+0200")
                           #:name "data"))))
(define mixed-parsed
  (~> mixed
      (select (~> (str->datetime "data" #:format "%Y-%m-%dT%H:%M:%S%z")
                  (dt-convert-time-zone "Europe/Brussels")))
      (ref "data")))
(displayln mixed-parsed)
