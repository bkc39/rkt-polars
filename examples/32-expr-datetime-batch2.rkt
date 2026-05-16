#lang racket/base

;; Expr datetime batch 2: ISO fields, date/time extraction, subsecond
;; fields, timestamps, formatting, and truncation.
;;
;; Inside `nix develop`:
;;   racket examples/32-expr-datetime-batch2.rkt

(require gregor
         polars)

(define df
  (dataframe-new
   (list (series-new-datetime
          "ts"
          (list (datetime 2024 1 2 3 4 5)
                (datetime 2025 12 31 23 59 58)
                (datetime 2026 5 9 12 30 45)))
         (series-new-i64 "t" '(1704164645123 1704164645999 1704164646000)))))

(define with-ms
  (dataframe-with-columns
   df
   (list (expr-alias (expr-cast (col "t") '(datetime milliseconds)) "ts_ms"))))

(define out
  (dataframe-with-columns
   with-ms
   (list (expr-alias (expr-dt-iso-year (col "ts")) "iso_year")
         (expr-alias (expr-cast (expr-dt-quarter (col "ts")) 'int32) "quarter")
         (expr-alias (expr-cast (expr-dt-week (col "ts")) 'int32) "week")
         (expr-alias (expr-cast (expr-dt-weekday (col "ts")) 'int32) "weekday")
         (expr-alias (expr-cast (expr-dt-ordinal-day (col "ts")) 'int32) "ordinal")
         (expr-alias (expr-dt-is-leap-year (col "ts")) "leap")
         (expr-alias (expr-dt-date (col "ts")) "date")
         (expr-alias (expr-dt-time (col "ts")) "time")
         (expr-alias (expr-dt-strftime (col "ts") "%Y-%m-%d") "fmt")
         (expr-alias (expr-dt-millisecond (col "ts_ms")) "ms")
         (expr-alias (expr-dt-microsecond (col "ts_ms")) "us")
         (expr-alias (expr-dt-nanosecond (col "ts_ms")) "ns")
         (expr-alias (expr-dt-timestamp (col "ts_ms") #:unit 'milliseconds)
                     "epoch_ms")
         (expr-alias (expr-dt-truncate (col "ts_ms") "1h") "hour_bucket"))))

(display-dataframe out)
