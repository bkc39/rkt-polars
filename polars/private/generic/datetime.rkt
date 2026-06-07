#lang racket/base

;; Polars' `.dt` namespace: calendar/clock field extraction from a datetime Expr.
;; Each mirrors pl.col(x).dt.<method>().  The first argument is the column to
;; operate on; a bare column-name string is auto-lifted via `col`, so both
;;   (dt-year (col "ts"))  and  (dt-year "ts")
;; work.  The `dt-` prefix is the Lisp realization of Polars' `.dt` namespace:
;; uniform with the `str-` namespace and collision-safe (e.g. the upcoming
;; dt-date / dt-time would otherwise clash with gregor's date and racket/base's
;; time).

(require polars/private/foreign
         polars/private/expr)

(provide dt-year dt-month dt-day dt-hour dt-minute dt-second
         dt-iso-year dt-quarter dt-week dt-weekday dt-ordinal-day
         dt-is-leap-year dt-date dt-time
         dt-millisecond dt-microsecond dt-nanosecond
         dt-timestamp dt-strftime dt-truncate)

;; Lift a column-name string to an Expr; pass an Expr through unchanged.
(define (->dt-expr who x)
  (cond [(Expr-ptr? x) x]
        [(string? x)   (col x)]
        [else (error who "expected an Expr or column name, got ~v" x)]))

(define (dt-year x)   (expr-dt-year   (->dt-expr 'dt-year x)))
(define (dt-month x)  (expr-dt-month  (->dt-expr 'dt-month x)))
(define (dt-day x)    (expr-dt-day    (->dt-expr 'dt-day x)))
(define (dt-hour x)   (expr-dt-hour   (->dt-expr 'dt-hour x)))
(define (dt-minute x) (expr-dt-minute (->dt-expr 'dt-minute x)))
(define (dt-second x) (expr-dt-second (->dt-expr 'dt-second x)))

;; ISO / calendar fields, date+time extraction, and subsecond fields.
(define (dt-iso-year x)     (expr-dt-iso-year     (->dt-expr 'dt-iso-year x)))
(define (dt-quarter x)      (expr-dt-quarter      (->dt-expr 'dt-quarter x)))
(define (dt-week x)         (expr-dt-week         (->dt-expr 'dt-week x)))
(define (dt-weekday x)      (expr-dt-weekday      (->dt-expr 'dt-weekday x)))
(define (dt-ordinal-day x)  (expr-dt-ordinal-day  (->dt-expr 'dt-ordinal-day x)))
(define (dt-is-leap-year x) (expr-dt-is-leap-year (->dt-expr 'dt-is-leap-year x)))
(define (dt-date x)         (expr-dt-date         (->dt-expr 'dt-date x)))
(define (dt-time x)         (expr-dt-time         (->dt-expr 'dt-time x)))
(define (dt-millisecond x)  (expr-dt-millisecond  (->dt-expr 'dt-millisecond x)))
(define (dt-microsecond x)  (expr-dt-microsecond  (->dt-expr 'dt-microsecond x)))
(define (dt-nanosecond x)   (expr-dt-nanosecond   (->dt-expr 'dt-nanosecond x)))

;; epoch timestamp (#:unit 'milliseconds|'microseconds|'nanoseconds), strftime
;; formatting, and truncation to a fixed interval (e.g. "1h", "1d").
(define (dt-timestamp x #:unit [unit 'microseconds])
  (expr-dt-timestamp (->dt-expr 'dt-timestamp x) #:unit unit))
(define (dt-strftime x fmt) (expr-dt-strftime (->dt-expr 'dt-strftime x) fmt))
(define (dt-truncate x every) (expr-dt-truncate (->dt-expr 'dt-truncate x) every))

(module+ test
  (require rackunit (only-in threading ~>)
           (only-in gregor datetime date)
           polars/private/generic/core
           polars/private/generic/reductions   ; alias
           polars/private/generic/reshape)     ; with-columns / cast
  (define df
    (dataframe (list (series (list (datetime 2024 1 2 8 30 5)) #:name "ts"))))
  (define out
    (~> df
        (with-columns
          (alias (dt-year "ts") "year")
          (alias (dt-month "ts") "month")
          (alias (dt-day "ts") "day")
          (alias (dt-hour "ts") "hour")
          (alias (dt-minute "ts") "minute")
          (alias (dt-second "ts") "second"))))
  (check-equal? (ref (ref out #:columns "year") 0) 2024)
  (check-equal? (ref (ref out #:columns "month") 0) 1)
  (check-equal? (ref (ref out #:columns "day") 0) 2)
  (check-equal? (ref (ref out #:columns "hour") 0) 8)
  (check-equal? (ref (ref out #:columns "minute") 0) 30)
  (check-equal? (ref (ref out #:columns "second") 0) 5)
  ;; an Expr argument works the same as a column-name string
  (check-equal? (ref (ref (~> df (with-columns (alias (dt-year (col "ts")) "y")))
                          #:columns "y")
                     0)
                2024)
  ;; batch 2: ISO/calendar fields, date/time, subsecond, timestamp, truncate
  (define dt2
    (dataframe (list (series (list (datetime 2024 1 2 3 4 5)) #:name "ts")
                     (series '(1704164645123) #:name "t" #:dtype 'i64))))
  (define m (~> dt2 (with-columns (alias (cast "t" '(datetime milliseconds)) "ts_ms"))))
  (define o2
    (~> m (with-columns
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
            (alias (dt-timestamp "ts_ms" #:unit 'milliseconds) "epoch")
            (alias (dt-truncate "ts_ms" "1h") "bucket"))))
  (define (c0 name) (ref (ref o2 #:columns name) 0))
  (check-equal? (c0 "iso_year") 2024)
  (check-equal? (c0 "quarter") 1)
  (check-equal? (c0 "week") 1)
  (check-equal? (c0 "weekday") 2)
  (check-equal? (c0 "ordinal") 2)
  (check-equal? (c0 "leap") #t)
  (check-equal? (c0 "date") (date 2024 1 2))
  (check-equal? (c0 "fmt") "2024-01-02")
  (check-equal? (c0 "ms") 123)
  (check-equal? (c0 "us") 123000)
  (check-equal? (c0 "ns") 123000000)
  (check-equal? (c0 "epoch") 1704164645123)
  (check-not-eq? (c0 "time") polars-null)      ; gregor time-of-day value
  (check-not-eq? (c0 "bucket") polars-null))   ; truncated datetime[ms]
