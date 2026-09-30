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
         polars/private/expr
         polars/private/generic/expr-util)

(provide dt-year dt-month dt-day dt-hour dt-minute dt-second
         dt-iso-year dt-quarter dt-week dt-weekday dt-ordinal-day
         dt-is-leap-year dt-date dt-time
         dt-millisecond dt-microsecond dt-nanosecond
         dt-timestamp dt-strftime dt-truncate)

(define-expr-unop dt-year   'dt-year   expr-dt-year)
(define-expr-unop dt-month  'dt-month  expr-dt-month)
(define-expr-unop dt-day    'dt-day    expr-dt-day)
(define-expr-unop dt-hour   'dt-hour   expr-dt-hour)
(define-expr-unop dt-minute 'dt-minute expr-dt-minute)
(define-expr-unop dt-second 'dt-second expr-dt-second)

;; ISO / calendar fields, date+time extraction, and subsecond fields.
(define-expr-unop dt-iso-year     'dt-iso-year     expr-dt-iso-year)
(define-expr-unop dt-quarter      'dt-quarter      expr-dt-quarter)
(define-expr-unop dt-week         'dt-week         expr-dt-week)
(define-expr-unop dt-weekday      'dt-weekday      expr-dt-weekday)
(define-expr-unop dt-ordinal-day  'dt-ordinal-day  expr-dt-ordinal-day)
(define-expr-unop dt-is-leap-year 'dt-is-leap-year expr-dt-is-leap-year)
(define-expr-unop dt-date         'dt-date         expr-dt-date)
(define-expr-unop dt-time         'dt-time         expr-dt-time)
(define-expr-unop dt-millisecond  'dt-millisecond  expr-dt-millisecond)
(define-expr-unop dt-microsecond  'dt-microsecond  expr-dt-microsecond)
(define-expr-unop dt-nanosecond   'dt-nanosecond   expr-dt-nanosecond)

;; epoch timestamp (#:unit 'milliseconds|'microseconds|'nanoseconds), strftime
;; formatting, and truncation to a fixed interval (e.g. "1h", "1d").
(define (dt-timestamp x #:unit [unit 'microseconds])
  (expr-dt-timestamp (->col-expr 'dt-timestamp x) #:unit unit))
(define (dt-strftime x fmt) (expr-dt-strftime (->col-expr 'dt-strftime x) fmt))
(define (dt-truncate x every) (expr-dt-truncate (->col-expr 'dt-truncate x) every))

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

(module+ test
  (require (only-in gregor moment)
           (only-in gregor/period hours microseconds nanoseconds)
           (only-in gregor/time time)
           (prefix-in p: polars/private/generic/operators)
           (only-in polars/private/generic/nullable fill-null)
           (only-in polars/private/generic/predicates is-between is-in))
  (define calendar
    (dataframe
     (list (series (list (date 2013 5 31) (date 2013 6 1) (date 2013 6 2)) #:name "d")
           (series (list (datetime 2013 5 31 5) (datetime 2013 6 1) (datetime 2013 6 2 1 2 3 500))
                   #:name "dt")
           (series (list (time 1) (time 5 6 7 123456000) (time 23)) #:name "t")
           (series (list (hours 1) (hours 2) (nanoseconds 1)) #:name "dur"))))
  (check-equal? (c0 "time") (time 3 4 5))
  (check-equal? (c0 "bucket") (datetime 2024 1 2 3))
  (check-equal? (ref (ref m "ts_ms") 0) (datetime 2024 1 2 3 4 5 123000000))

  (define (rows predicate) (height (filter calendar predicate)))
  (check-equal? (dtype (ref calendar "dt")) '(datetime nanoseconds #f))
  (check-equal? (rows (p:> (col "d") (date 2013 6 1))) 1)
  (check-equal? (rows (p:> (col "d") (datetime 2013 6 1 12))) 1)
  (check-equal? (rows (p:> (col "dt") (date 2013 6 1))) 1)
  (check-equal? (rows (p:>= (col "dt") (date 2013 6 1))) 2)
  (check-equal? (rows (p:= (col "dt") (datetime 2013 6 2 1 2 3 500))) 1)
  (check-equal? (rows (p:= (col "dt") (datetime 2013 6 2 1 2 3 400))) 0)
  (check-equal? (rows (p:= (col "dt") (datetime 2013 6 2 1 2 3))) 1)
  (check-equal? (rows (p:> (col "t") (time 5))) 2)
  (check-equal? (rows (p:> (col "dur") (hours 1))) 1)
  (check-equal? (rows (is-between "d" (date 2013 5 31) (date 2013 6 1))) 2)
  (check-equal? (rows (is-in "d" (list (date 2013 5 31) (date 2013 6 2)))) 2)
  (check-equal? (rows (is-in "t" (list (time 23) (time 2)))) 1)
  (check-equal? (for/list ([x (p:> (ref calendar "d") (date 2013 6 1))]) x) '(#f #f #t))
  (check-equal? (for/list ([x (p:!= (date 2013 6 1) (ref calendar "d"))]) x) '(#t #f #t))
  (check-equal? (for/list ([x (p:> (ref calendar "d") (datetime 2013 6 1 12))]) x) '(#f #f #t))
  (check-equal? (for/list ([x (p:< (ref calendar "dur") (nanoseconds 7200000000001))]) x)
                '(#t #t #t))
  (check-exn #rx"^expr-is-in: a moment carries a time zone"
             (lambda () (is-in "dt" (list (datetime 2013 6 1) (moment 2013 6 1 #:tz "UTC")))))
  (check-equal? (for/list ([x (series (list (nanoseconds -1500) (nanoseconds 1500))
                                      #:dtype '(duration microseconds))])
                  x)
                (list (microseconds -1) (microseconds 1)))
  (check-exn #rx"^series: value out of range for this dtype"
             (lambda () (series (list (date 300000 1 1)))))
  (check-exn #rx"^lit: value out of range for this dtype"
             (lambda () (lit (datetime 270000 1 1))))

  (define (literal v)
    (define s (ref (select calendar (alias (lit v) "v")) "v"))
    (list (dtype s) (ref s 0)))
  (check-equal? (literal (date 2013 6 1)) (list 'date (date 2013 6 1)))
  (check-equal? (literal (date -1300 5 23)) (list 'date (date -1300 5 23)))
  (check-equal? (literal (datetime 2013 6 1 5 6 7 123456000))
                (list '(datetime microseconds #f) (datetime 2013 6 1 5 6 7 123456000)))
  (check-equal? (literal (datetime 1969 12 31 23 59 59 999999999))
                (list '(datetime nanoseconds #f) (datetime 1969 12 31 23 59 59 999999999)))
  (check-equal? (literal (time 5 6 7 123456789)) (list 'time (time 5 6 7 123456789)))
  (check-equal? (literal (hours 1)) (list '(duration microseconds) (microseconds 3600000000)))
  (check-equal? (literal (nanoseconds -1)) (list '(duration nanoseconds) (nanoseconds -1)))
  (check-equal? (for/list ([x (~> (dataframe (list (series (list (date 2013 1 1) polars-null)
                                                           #:name "d")))
                                 (select (fill-null (col "d") (date 2000 1 1)))
                                 (ref "d"))])
                  x)
                (list (date 2013 1 1) (date 2000 1 1)))
  (check-exn #rx"^lit: a moment carries a time zone.*\n  value: #<moment"
             (lambda () (lit (moment 2013 6 1 #:tz "UTC"))))
  (check-exn #rx"^lit: a moment carries a time zone"
             (lambda () (p:> (col "dt") (moment 2013 6 1 #:tz "UTC"))))
  (check-exn #rx"^lit: value out of range for this dtype\n  dtype: 'date"
             (lambda () (lit (date 6000000 1 1)))))
