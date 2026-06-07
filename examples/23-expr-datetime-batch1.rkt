#lang racket/base

;; Expr datetime batch 1: extract calendar and clock fields from datetimes.
;;
;; The .dt field extractors are prefix-free and data-first, with bare
;; column-name strings auto-lifted to (col ...), so they thread straight
;; through with-columns.
;;
;; Inside `nix develop`:
;;   racket examples/23-expr-datetime-batch1.rkt

(require gregor
         polars)

(define df
  (dataframe
   (list (series '("open" "lunch" "close") #:name "event")
         (series (list (datetime 2024 1 2 8 30 5)
                       (datetime 2024 1 2 12 15 0)
                       (datetime 2024 1 2 17 45 30))
                 #:name "ts"))))

(define out
  (~> df
      (with-columns
        (alias (year "ts") "year")
        (alias (cast (month "ts") 'int32) "month")
        (alias (cast (day "ts") 'int32) "day")
        (alias (cast (hour "ts") 'int32) "hour")
        (alias (cast (minute "ts") 'int32) "minute")
        (alias (cast (second "ts") 'int32) "second"))))

(displayln out)
