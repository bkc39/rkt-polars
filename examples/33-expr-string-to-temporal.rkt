#lang racket/base

;; Expr string-to-temporal parsing: Date, Datetime, and Time.
;;
;; Inside `nix develop`:
;;   racket examples/33-expr-string-to-temporal.rkt

(require polars)

(define df
  (dataframe-new
   (list (series-new-str "date_s" '("2024-01-02" "not-a-date" "2024-05-09 extra"))
         (series-new-str "dt_s" '("2024-01-02 03:04:05"
                                  "bad"
                                  "2024-05-09 12:30:45"))
         (series-new-str "time_s" '("03:04:05.123456789"
                                    "bad"
                                    "12:30:45")))))

(define out
  (dataframe-with-columns
   df
   (list (expr-alias (expr-str-to-date (col "date_s") #:strict #f)
                     "date_infer")
         (expr-alias (expr-str-to-date (col "date_s")
                                       #:format "%Y-%m-%d"
                                       #:strict #f
                                       #:exact #f)
                     "date_embedded")
         (expr-alias (expr-str-to-datetime (col "dt_s")
                                           #:format "%Y-%m-%d %H:%M:%S"
                                           #:unit 'milliseconds
                                           #:strict #f)
                     "parsed_dt")
         (expr-alias (expr-str-to-time (col "time_s")
                                       #:format "%H:%M:%S%.f"
                                       #:strict #f)
                     "parsed_time"))))

(display-dataframe out)
