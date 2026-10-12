#lang racket/base

;; rkt-polars user guide — Time series: Filtering
;; Mirrors https://docs.pola.rs/user-guide/transformations/time-series/filter/
;; and filtering.py.
;;
;; Inside `nix develop`:
;;   racket user-guide/time-series/filtering.rkt

(require gregor
         racket/runtime-path
         polars)

(define-runtime-path data-dir "../../polars/scribblings/data")

(define stock (read-csv (build-path data-dir "apple_stock.csv") #:try-parse-dates #t))
(displayln stock)

;; --- filtering by single dates -------------------------------------------
(displayln (filter stock (= (col "Date") (datetime 1995 10 16))))

;; --- filtering by a date range -------------------------------------------
(displayln (filter stock (is-between "Date" (datetime 1995 7 1) (datetime 1995 11 1))))

;; --- filtering with negative dates ---------------------------------------
(define negative-dates
  (~> (dataframe (list (series '("-1300-05-23" "-1400-03-02") #:name "ts")
                       (series '(3 4) #:name "values")))
      (with-columns (str->date "ts"))))
(displayln (filter negative-dates (< (dt-year "ts") -1300)))
;; gregor holds years before 1, where Python's datetime cannot.
(displayln (filter negative-dates (= (col "ts") (date -1300 5 23))))
