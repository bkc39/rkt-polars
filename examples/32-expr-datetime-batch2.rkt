#lang racket/base

;; Expr datetime batch 2: ISO fields, date/time extraction, subsecond
;; fields, timestamps, formatting, and truncation.
;;
;; Inside `nix develop`:
;;   racket examples/32-expr-datetime-batch2.rkt

(require gregor
         polars)

(define df
  (dataframe
   (list (series (list (datetime 2024 1 2 3 4 5)
                       (datetime 2025 12 31 23 59 58)
                       (datetime 2026 5 9 12 30 45))
                 #:name "ts")
         (series '(1704164645123 1704164645999 1704164646000)
                 #:name "t" #:dtype 'i64))))

(define with-ms
  (~> df (with-columns (alias (cast "t" '(datetime milliseconds)) "ts_ms"))))

(define out
  (~> with-ms
      (with-columns
       (alias (dt-iso-year "ts") "iso_year")
       (alias (cast (dt-quarter "ts") 'int32) "quarter")
       (alias (cast (dt-week "ts") 'int32) "week")
       (alias (cast (dt-weekday "ts") 'int32) "weekday")
       (alias (cast (dt-ordinal-day "ts") 'int32) "ordinal")
       (alias (dt-is-leap-year "ts") "leap")
       (alias (dt-date "ts") "date")
       (alias (dt-time "ts") "time")
       (alias (dt-strftime "ts" "%Y-%m-%d") "fmt")
       (alias (dt-millisecond "ts_ms") "ms")
       (alias (dt-microsecond "ts_ms") "us")
       (alias (dt-nanosecond "ts_ms") "ns")
       (alias (dt-timestamp "ts_ms" #:unit 'milliseconds) "epoch_ms")
       (alias (dt-truncate "ts_ms" "1h") "hour_bucket"))))

(displayln out)
