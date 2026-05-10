#lang racket/base

;; Expr datetime batch 1: extract calendar and clock fields from datetimes.
;;
;; Inside `nix develop`:
;;   racket examples/23-expr-datetime-batch1.rkt

(require gregor
         polars)

(define df
  (dataframe-new
   (list (series-new-str "event" '("open" "lunch" "close"))
         (series-new-datetime
          "ts"
          (list (datetime 2024 1 2 8 30 5)
                (datetime 2024 1 2 12 15 0)
                (datetime 2024 1 2 17 45 30))))))

(define out
  (dataframe-with-columns
   df
   (list (expr-alias (expr-dt-year (col "ts")) "year")
         (expr-alias (expr-cast (expr-dt-month (col "ts")) 'int32) "month")
         (expr-alias (expr-cast (expr-dt-day (col "ts")) 'int32) "day")
         (expr-alias (expr-cast (expr-dt-hour (col "ts")) 'int32) "hour")
         (expr-alias (expr-cast (expr-dt-minute (col "ts")) 'int32) "minute")
         (expr-alias (expr-cast (expr-dt-second (col "ts")) 'int32) "second"))))

(display-dataframe out)
