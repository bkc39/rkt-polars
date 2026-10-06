#lang racket/base

;; Polars' `.dt` namespace: calendar/clock field extraction from a datetime Expr.
;; Each mirrors pl.col(x).dt.<method>().  The first argument is the column to
;; operate on; a bare column-name string is auto-lifted via `col`, so both
;;   (dt-year (col "ts"))  and  (dt-year "ts")
;; work.  The `dt-` prefix is the Lisp realization of Polars' `.dt` namespace:
;; uniform with the `str-` namespace and collision-safe (e.g. the upcoming
;; dt-date / dt-time would otherwise clash with gregor's date and racket/base's
;; time).

(require racket/contract/base
         (only-in racket/string non-empty-string?)
         polars/private/foreign
         polars/private/expr
         (only-in polars/private/expr-dt expr-dt-convert-time-zone expr-dt-replace-time-zone)
         (only-in polars/private/generic/core series? wrap-series)
         polars/private/generic/expr-util)

(provide dt-year dt-month dt-day dt-hour dt-minute dt-second
         dt-iso-year dt-quarter dt-week dt-weekday dt-ordinal-day
         dt-is-leap-year dt-date dt-time
         dt-millisecond dt-microsecond dt-nanosecond
         dt-timestamp dt-strftime dt-truncate
         (contract-out
          [dt-convert-time-zone (-> (or/c series? col-expr/c) non-empty-string?
                                    (or/c series? Expr-ptr?))]
          [dt-replace-time-zone (->* ((or/c series? col-expr/c) (or/c #f non-empty-string?))
                                     (#:ambiguous (or/c 'raise 'earliest 'latest 'null)
                                      #:non-existent (or/c 'raise 'null))
                                     (or/c series? Expr-ptr?))]))

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

(define (dt-convert-time-zone x zone)
  (define who 'dt-convert-time-zone)
  (if (series? x)
      (wrap-series (series-dt-convert-time-zone who x zone))
      (expr-dt-convert-time-zone (->col-expr who x) zone #:who who)))

(define (dt-replace-time-zone x zone
                              #:ambiguous [ambiguous 'raise]
                              #:non-existent [non-existent 'raise])
  (define who 'dt-replace-time-zone)
  (if (series? x)
      (wrap-series (series-dt-replace-time-zone who x zone ambiguous non-existent))
      (expr-dt-replace-time-zone (->col-expr who x) zone
                                 #:ambiguous ambiguous #:non-existent non-existent #:who who)))

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
  (require (only-in racket/list make-list)
           (only-in gregor moment)
           (only-in gregor/period hours microseconds nanoseconds period weeks)
           (only-in gregor/time time)
           (only-in polars/private/bulk series->list)
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
  (check-equal? (rows (is-in "dt" (list (datetime 2013 6 1) (moment 2013 6 2 1 2 3 500 #:tz "UTC"))))
                2)
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
  (check-equal? (literal (moment 2013 6 1 5 #:tz "Europe/Paris"))
                (list '(datetime microseconds "Europe/Paris") (moment 2013 6 1 5 #:tz "Europe/Paris")))
  (check-exn #rx"^lit: value out of range for this dtype\n  dtype: 'date"
             (lambda () (lit (date 6000000 1 1))))
  (check-equal? (literal (datetime 1600 1 1 0 0 0 999))
                (list '(datetime microseconds #f) (datetime 1600 1 1)))
  (check-equal? (literal (period (weeks 20000) (nanoseconds 1)))
                (list '(duration microseconds) (microseconds (* 20000 7 86400 1000000))))
  (check-equal? (rows (p:< (col "dt") (datetime 1600 1 1 0 0 0 1))) 0)

  (for ([value (list (date 2013 6 1) (time 5 6 7 123456789) (datetime 2013 6 1 5 6 7 123456789)
                     (datetime 1969 12 31 23 59 59 999999999) (datetime 1600 1 1 0 0 0 1)
                     (nanoseconds -1500) (period (hours 1) (nanoseconds 1)) polars-null)]
        [dt (list 'date 'time '(datetime nanoseconds #f) '(datetime milliseconds #f)
                  '(datetime microseconds #f) '(duration microseconds) '(duration nanoseconds)
                  '(datetime microseconds #f))])
    (check-equal? (series->list (p:const-series dt 3 value))
                  (series->list (series (make-list 3 value) #:dtype dt)))))

(module+ test
  (require (only-in gregor
                    ->posix ->tzid ->utc-offset moment moment->iso8601/tzid posix->datetime
                    posix->moment
                    resolve-offset/pre resolve-offset/post)
           (only-in racket/contract exn:fail:contract:blame?)
           (only-in polars/private/bulk in-series)
           (only-in polars/private/generic/strings str->datetime)
           (prefix-in contracted: (submod "..")))

  (define (cells s) (for/list ([x (in-series s)]) x))
  (define (column d name) (cells (ref d name)))
  (define (one s) (ref s 0))

  ;; the guide's Time zones section, upstream's example
  (define tz-naive
    (~> (dataframe (list (series '("2021-03-27 03:00" "2021-03-28 03:00") #:name "tz_naive")))
        (select (str->datetime "tz_naive"))
        (ref "tz_naive")))
  (define tz-aware (~> tz-naive (dt-replace-time-zone "UTC") (rename "tz_aware")))
  (define tz-df (dataframe (list tz-naive tz-aware)))
  (check-equal? (column-names tz-df) '("tz_naive" "tz_aware"))
  (check-equal? (dtype (ref tz-df "tz_naive")) '(datetime microseconds #f))
  (check-equal? (dtype (ref tz-df "tz_aware")) '(datetime microseconds "UTC"))
  (check-equal? (column tz-df "tz_aware")
                (list (moment 2021 3 27 3 #:tz "UTC") (moment 2021 3 28 3 #:tz "UTC")))
  (define tz-ops
    (select tz-df
            (~> (col "tz_aware") (dt-replace-time-zone "Europe/Brussels")
                (alias "replace time zone"))
            (~> (col "tz_aware") (dt-convert-time-zone "Asia/Kathmandu")
                (alias "convert time zone"))
            (~> (col "tz_aware") (dt-replace-time-zone #f) (alias "unset time zone"))))
  (check-equal? (map (lambda (name) (dtype (ref tz-ops name))) (column-names tz-ops))
                '((datetime microseconds "Europe/Brussels") (datetime microseconds "Asia/Kathmandu")
                  (datetime microseconds #f)))
  (check-equal? (column tz-ops "replace time zone")
                (list (moment 2021 3 27 3 #:tz "Europe/Brussels")
                      (moment 2021 3 28 3 #:tz "Europe/Brussels")))
  (check-equal? (column tz-ops "convert time zone")
                (list (moment 2021 3 27 8 45 #:tz "Asia/Kathmandu")
                      (moment 2021 3 28 8 45 #:tz "Asia/Kathmandu")))
  (check-equal? (column tz-ops "unset time zone") (list (datetime 2021 3 27 3) (datetime 2021 3 28 3)))

  ;; the guide's Mixed offsets section, upstream's example
  (define offsets
    (dataframe (list (series '("2021-03-27T00:00:00+0100" "2021-03-28T00:00:00+0100"
                               "2021-03-29T00:00:00+0200" "2021-03-30T00:00:00+0200")
                             #:name "data"))))
  (define parsed (select offsets (str->datetime "data" #:format "%Y-%m-%dT%H:%M:%S%z")))
  (check-equal? (dtype (ref parsed "data")) '(datetime microseconds "UTC"))
  (check-equal? (one (ref parsed "data")) (moment 2021 3 26 23 #:tz "UTC"))
  (check-exn #rx"^lazyframe-collect: .*no format and no time zone, but a time zone is part of"
             (lambda () (select offsets (str->datetime "data"))))
  (define mixed-parsed
    (~> offsets
        (select (~> (str->datetime "data" #:format "%Y-%m-%dT%H:%M:%S%z")
                    (dt-convert-time-zone "Europe/Brussels")))
        (ref "data")))
  (check-equal? (cells mixed-parsed)
                (for/list ([day '(27 28 29 30)]) (moment 2021 3 day #:tz "Europe/Brussels")))

  ;; the guide's Zoned values from Racket and the reference's examples
  (define landings
    (series (list (moment 2021 3 27 9 #:tz "Europe/Brussels")
                  (moment 2021 3 28 9 #:tz "Europe/Brussels")
                  (moment 2021 3 27 18 #:tz "Asia/Kathmandu"))
            #:name "landed"))
  (check-equal? (format "~a" landings)
                (string-append "shape: (3,)\nSeries: 'landed' [datetime[us, Europe/Brussels]]\n[\n"
                               "\t2021-03-27 09:00:00 CET\n\t2021-03-28 09:00:00 CEST\n"
                               "\t2021-03-27 13:15:00 CET\n]"))
  (check-equal? (series->list landings)
                (list (moment 2021 3 27 9 #:tz "Europe/Brussels")
                      (moment 2021 3 28 9 #:tz "Europe/Brussels")
                      (moment 2021 3 27 13 15 #:tz "Europe/Brussels")))
  (check-equal? (dtype (series (list (moment 2021 3 27 9 #:tz 3600))))
                '(datetime microseconds "UTC"))
  (check-equal? (series->list (series (list (moment 2021 3 27 #:tz 3600)) #:name "offset"))
                (list (moment 2021 3 26 23 #:tz "UTC")))
  (check-equal? (cells (series (list (moment 2021 3 27 #:tz "Europe/Brussels")
                                     (moment 2021 3 28 5 #:tz "Europe/Brussels")
                                     (moment 2021 3 27 #:tz "Asia/Kathmandu"))
                               #:name "zoned"))
                (list (moment 2021 3 27 #:tz "Europe/Brussels")
                      (moment 2021 3 28 5 #:tz "Europe/Brussels")
                      (moment 2021 3 26 19 15 #:tz "Europe/Brussels")))
  (check-equal? (cells (series (list (datetime 2021 3 27 12))
                               #:dtype '(datetime milliseconds "Europe/Brussels")))
                (list (moment 2021 3 27 13 #:tz "Europe/Brussels")))
  (check-equal? (ref (ref (select (dataframe (list (series '(1) #:name "id")))
                                  (alias (lit (moment 2013 6 1 12 30 #:tz "Europe/Paris")) "noon"))
                          "noon")
                     0)
                (moment 2013 6 1 12 30 #:tz "Europe/Paris"))

  ;; a moment read back carries polars' offset, whatever the system zoneinfo says
  (define (read-back seconds zone)
    (one (cast (series (list (* seconds 1000000))) (list 'datetime 'microseconds zone))))
  (for ([seconds (list 2540282400 (- -2208988800 20476) 1616842800 1616842800)]
        [zone '("Europe/Brussels" "Asia/Kathmandu" "US/Pacific" "Etc/GMT-1")]
        [iso '("2050-07-01T12:00:00+02:00" "1900-01-01T00:00:00+05:41" "2021-03-27T04:00:00-07:00"
               "2021-03-27T12:00:00+01:00")]
        [offset '(7200 20476 -25200 3600)])
    (define m (read-back seconds zone))
    (check-equal? (moment->iso8601/tzid m) (format "~a[~a]" iso zone))
    (check-equal? (->utc-offset m) offset)
    (check-equal? (->posix m) seconds))

  ;; the reference's dt-convert-time-zone / dt-replace-time-zone and cast examples
  (define clocks
    (dataframe (list (series (list (datetime 2021 3 27 3) (datetime 2021 10 31 2 30))
                             #:name "clock"))))
  (define moved
    (select clocks
            (~> "clock" (dt-replace-time-zone "UTC") (alias "utc"))
            (~> "clock" (dt-replace-time-zone "UTC") (dt-convert-time-zone "Asia/Kathmandu")
                (alias "kathmandu"))
            (~> "clock" (dt-replace-time-zone "Europe/Brussels" #:ambiguous 'earliest)
                (alias "brussels"))))
  (check-equal? (column moved "utc")
                (list (moment 2021 3 27 3 #:tz "UTC") (moment 2021 10 31 2 30 #:tz "UTC")))
  (check-equal? (column moved "kathmandu")
                (list (moment 2021 3 27 8 45 #:tz "Asia/Kathmandu")
                      (moment 2021 10 31 8 15 #:tz "Asia/Kathmandu")))
  (check-equal? (column moved "brussels")
                (list (moment 2021 3 27 3 #:tz "Europe/Brussels")
                      (moment 2021 10 31 2 30 #:tz "Europe/Brussels"
                              #:resolve-offset resolve-offset/pre)))
  (check-equal? (cells (dt-replace-time-zone (ref clocks "clock") "Europe/Brussels"
                                             #:ambiguous 'latest))
                (list (moment 2021 3 27 3 #:tz "Europe/Brussels")
                      (moment 2021 10 31 2 30 #:tz "Europe/Brussels"
                              #:resolve-offset resolve-offset/post)))
  (check-exn #rx"^dt-replace-time-zone: .*'2021-10-31 02:30:00' is ambiguous"
             (lambda () (dt-replace-time-zone (ref clocks "clock") "Europe/Brussels")))
  (define skipped (series (list (datetime 2021 3 28 1 30) (datetime 2021 3 28 2 30))
                          #:name "clock"))
  (check-equal? (cells (dt-replace-time-zone skipped "Europe/Brussels" #:non-existent 'null))
                (list (moment 2021 3 28 1 30 #:tz "Europe/Brussels") polars-null))
  (check-exn #rx"^dt-replace-time-zone: .*'2021-03-28 02:30:00' is non-existent .*#:non-existent 'null"
             (lambda () (dt-replace-time-zone skipped "Europe/Brussels")))
  (check-exn #rx"^dt-convert-time-zone: .*'Asia/Kathmando'.*did you mean 'Asia/Kathmandu'"
             (lambda () (dt-convert-time-zone "clock" "Asia/Kathmando")))
  (check-exn #rx"^cast: cannot convert to .*'Europe/Brusels'.*did you mean 'Europe/Brussels'"
             (lambda () (cast (series (list (datetime 2021 3 27 12)))
                              '(datetime microseconds "Europe/Brusels"))))

  ;; a series from moments takes the first value's zone, as Python's does
  (define brussels (moment 2021 3 27 #:tz "Europe/Brussels"))
  (define kathmandu (moment 2021 3 27 #:tz "Asia/Kathmandu"))
  (define plus-one (moment 2021 3 27 #:tz 3600))
  (for ([vals (list (list brussels kathmandu) (list polars-null brussels plus-one)
                    (list brussels (datetime 2021 3 27)) (list kathmandu brussels)
                    (list plus-one brussels) (list (datetime 2021 3 27) brussels)
                    (list (moment 2021 3 27 #:tz "Etc/UTC")))]
        [expected-dtype (list '(datetime microseconds "Europe/Brussels")
                              '(datetime microseconds "Europe/Brussels")
                              '(datetime microseconds "Europe/Brussels")
                              '(datetime microseconds "Asia/Kathmandu")
                              '(datetime microseconds "UTC")
                              '(datetime microseconds #f)
                              '(datetime microseconds "Etc/UTC"))])
    (define s (series vals))
    (check-equal? (dtype s) expected-dtype)
    (define zone (caddr expected-dtype))
    (check-equal? (cells s)
                  (for/list ([v (in-list vals)])
                    (cond [(polars-null? v) v]
                          [zone (posix->moment (->posix v) zone)]
                          [else (posix->datetime (->posix v))]))))
  (check-equal? (cells (series (list brussels (datetime 2021 3 27))))
                (list brussels (moment 2021 3 27 1 #:tz "Europe/Brussels")))
  (check-equal? (cells (series (list (datetime 2021 3 27) brussels)))
                (list (datetime 2021 3 27) (datetime 2021 3 26 23)))

  ;; moment -> series -> moment, across DST transitions, at nanosecond precision
  (define transitions
    (for*/list ([zone '("Europe/Brussels" "America/New_York" "Australia/Lord_Howe")]
                [utc (list (datetime 2021 3 28 0 59 59 999999999) (datetime 2021 3 28 1)
                           (datetime 2021 10 31 0 30 0 1) (datetime 2021 10 31 1 30 0 1)
                           (datetime 2021 3 14 6 59 59 999999999) (datetime 2021 11 7 5 30)
                           (datetime 2021 11 7 6 30 0 123456789) (datetime 2021 4 3 14 45))])
      (posix->moment (->posix utc) zone)))
  (for ([zone '("Europe/Brussels" "America/New_York" "Australia/Lord_Howe")])
    (define ms (filter (lambda (m) (equal? (->tzid m) zone)) transitions))
    (define s (series ms))
    (check-equal? (dtype s) (list 'datetime 'nanoseconds zone))
    (check-equal? (series->list s) ms)
    (check-equal? (for/list ([i (in-range (len s))]) (ref s i)) ms)
    (check-equal? (cells (dt-convert-time-zone s "UTC"))
                  (for/list ([m (in-list ms)]) (posix->moment (->posix m) "UTC"))))
  (check-equal? (dtype (series (list (moment 2021 3 27 0 0 0 1 #:tz "UTC")
                                     (moment 1600 #:tz "UTC"))))
                '(datetime microseconds "UTC"))

  ;; #:dtype: a zoned dtype reads a datetime as UTC, a naive one reads a moment's UTC clock
  (check-equal? (cells (series (list (datetime 2021 3 27 12) kathmandu)
                               #:dtype '(datetime milliseconds "Europe/Brussels")))
                (list (moment 2021 3 27 13 #:tz "Europe/Brussels")
                      (moment 2021 3 26 19 15 #:tz "Europe/Brussels")))
  (check-equal? (cells (series (list brussels) #:dtype '(datetime microseconds #f)))
                (list (datetime 2021 3 26 23)))
  (check-equal? (cells (series (list (moment 2021 3 27 0 0 0 1999 #:tz "UTC"))
                               #:dtype '(datetime microseconds "UTC")))
                (list (moment 2021 3 27 0 0 0 1000 #:tz "UTC")))
  (check-exn (regexp (string-append "^series: cannot convert to '\\(datetime microseconds"
                                    " \"Mars/Base\"\\): unable to parse time zone: 'Mars/Base'"))
             (lambda ()
               (series (list (datetime 2021 3 27)) #:dtype '(datetime microseconds "Mars/Base"))))
  (check-equal? (dtype (series (list (datetime 2021 3 27))
                               #:dtype '(datetime microseconds "+01:00")))
                '(datetime microseconds "Etc/GMT-1"))

  ;; literals and comparisons
  (define zoned-frame
    (dataframe (list (series (list brussels (moment 2021 7 1 #:tz "Europe/Brussels"))
                             #:name "t"))))
  (define may-day (moment 2021 5 1 #:tz "Europe/Brussels"))
  (check-equal? (height (filter zoned-frame (p:> (col "t") may-day))) 1)
  (check-equal? (height (filter zoned-frame (is-between "t" brussels
                                                        (moment 2021 4 1 #:tz "Europe/Brussels"))))
                1)
  (check-equal? (height (filter zoned-frame (is-in "t" (list brussels)))) 1)
  (check-equal? (cells (p:< (ref zoned-frame "t") may-day)) '(#t #f))
  (check-equal? (cells (p:p- (ref zoned-frame "t") may-day))
                (for/list ([m (list brussels (moment 2021 7 1 #:tz "Europe/Brussels"))])
                  (microseconds (* 1000000 (- (->posix m) (->posix may-day))))))
  (for ([op (list p:> p:= p:p-)]
        [who '(> = -)]
        [other (list (moment 2021 5 1 #:tz "Asia/Tokyo") (datetime 2021 5 1)
                     (series (list (moment 2021 5 1 #:tz "UTC") brussels)))])
    (check-exn (regexp (string-append "^" (regexp-quote (symbol->string who))
                                      ": datetimes in different time zones\n"
                                      "  series dtype: '\\(datetime microseconds"
                                      " \"Europe/Brussels\"\\)"))
               (lambda () (op (ref zoned-frame "t") other))))
  (check-exn (regexp (string-append "^<: datetimes in different time zones\n"
                                    "  series dtype: '\\(datetime microseconds #f\\)"))
             (lambda () (p:< (series (list (datetime 2021 5 1))) brussels)))
  (check-exn #rx"^lazyframe-collect: .*comparison"
             (lambda () (filter zoned-frame (p:> (col "t") (moment 2021 5 1 #:tz "Asia/Tokyo")))))
  (check-equal? (literal (moment 2021 3 27 #:tz 3600)) (list '(datetime microseconds "UTC")
                                                             (moment 2021 3 26 23 #:tz "UTC")))
  (check-equal? (literal (moment 2021 3 27 0 0 0 1 #:tz "Europe/Brussels"))
                (list '(datetime nanoseconds "Europe/Brussels")
                      (moment 2021 3 27 0 0 0 1 #:tz "Europe/Brussels")))
  (check-equal? (cells (ref (select (dataframe (list (series (list polars-null brussels) #:name "t")))
                                    (fill-null (col "t") (moment 2000 #:tz "Europe/Brussels")))
                            "t"))
                (list (moment 2000 #:tz "Europe/Brussels") brussels))

  ;; casts and dtype selection
  (check-equal? (dtype (cast (ref zoned-frame "t") '(datetime milliseconds "Asia/Tokyo")))
                '(datetime milliseconds "Asia/Tokyo"))
  (check-equal? (one (cast (ref zoned-frame "t") '(datetime microseconds #f)))
                (datetime 2021 3 26 23))
  (check-equal? (one (cast (series (list (datetime 2021 3 27 12)))
                           '(datetime microseconds "Europe/Brussels")))
                (moment 2021 3 27 13 #:tz "Europe/Brussels"))
  (check-equal? (column (select zoned-frame (cast "t" '(datetime microseconds "UTC"))) "t")
                (list (moment 2021 3 26 23 #:tz "UTC") (moment 2021 6 30 22 #:tz "UTC")))
  (check-exn #rx"^cast: cannot convert to '\\(datetime microseconds \"Mars/Base\"\\): .*'Mars/Base'"
             (lambda () (cast (ref zoned-frame "t") '(datetime microseconds "Mars/Base"))))
  (check-exn #rx"^cast: cannot convert to '\\(datetime microseconds \"Mars/Base\"\\): .*'Mars/Base'"
             (lambda () (cast "t" '(datetime microseconds "Mars/Base"))))
  (define three-kinds
    (with-columns zoned-frame
      (~> (col "t") (dt-convert-time-zone "UTC") (alias "utc"))
      (~> (col "t") (dt-replace-time-zone #f) (alias "naive"))))
  (check-equal? (column-names (select three-kinds (col '(datetime microseconds "UTC"))))
                '("utc"))
  (check-equal? (column-names (select three-kinds (col '(datetime microseconds "Europe/Brussels"))))
                '("t"))
  (check-equal? (column-names (select three-kinds (col '(datetime microseconds #f)))) '("naive"))

  ;; convert and replace on a series, an expression or a column name
  (define wall (series (list (datetime 2021 10 31 2 30) (datetime 2021 10 31 3 30) polars-null
                             (datetime 2021 3 28 2 30))
                       #:name "wall"))
  (check-exn (regexp (string-append "^dt-replace-time-zone: cannot replace the time zone with"
                                    " \"Europe/Brussels\": datetime '2021-10-31 02:30:00' is"
                                    " ambiguous in time zone 'Europe/Brussels'\\. Please use"
                                    " #:ambiguous to tell how it should be localized\\.$"))
             (lambda () (dt-replace-time-zone wall "Europe/Brussels")))
  (define (replaced ambiguous non-existent)
    (cells (dt-replace-time-zone wall "Europe/Brussels"
                                 #:ambiguous ambiguous #:non-existent non-existent)))
  (check-exn (regexp (string-append "^dt-replace-time-zone: .*is non-existent in time zone"
                                    " 'Europe/Brussels'\\. You may be able to use"
                                    " #:non-existent 'null to return `null` in this case\\.$"))
             (lambda () (replaced 'earliest 'raise)))
  (check-equal? (replaced 'earliest 'null)
                (list (moment 2021 10 31 2 30 #:tz "Europe/Brussels"
                              #:resolve-offset resolve-offset/pre)
                      (moment 2021 10 31 3 30 #:tz "Europe/Brussels") polars-null polars-null))
  (check-equal? (replaced 'latest 'null)
                (list (moment 2021 10 31 2 30 #:tz "Europe/Brussels"
                              #:resolve-offset resolve-offset/post)
                      (moment 2021 10 31 3 30 #:tz "Europe/Brussels") polars-null polars-null))
  (check-equal? (replaced 'null 'null)
                (list polars-null (moment 2021 10 31 3 30 #:tz "Europe/Brussels") polars-null
                      polars-null))
  (check-equal? (series-name (dt-convert-time-zone wall "Asia/Tokyo")) "wall")
  (check-equal? (one (dt-convert-time-zone (dt-replace-time-zone wall "UTC") "Asia/Tokyo"))
                (moment 2021 10 31 11 30 #:tz "Asia/Tokyo"))
  (check-equal? (one (dt-convert-time-zone wall "Asia/Tokyo"))
                (moment 2021 10 31 11 30 #:tz "Asia/Tokyo"))
  (check-equal? (cells (dt-replace-time-zone (dt-replace-time-zone wall "UTC") #f))
                (cells wall))
  (check-exn #rx"^lazyframe-collect: .*is ambiguous in time zone 'Europe/Brussels'\\. Please use #:amb"
             (lambda ()
               (select (dataframe (list wall)) (dt-replace-time-zone "wall" "Europe/Brussels"))))
  (check-equal? (column (select (dataframe (list wall))
                                (dt-replace-time-zone "wall" "Europe/Brussels"
                                                      #:ambiguous 'null #:non-existent 'null))
                        "wall")
                (replaced 'null 'null))
  (check-exn (regexp (string-append "^dt-convert-time-zone: cannot convert to the time zone"
                                    " \"Mars/Base\": unable to parse time zone: 'Mars/Base'\\."
                                    ".*Hint: did you mean"))
             (lambda () (dt-convert-time-zone "t" "Mars/Base")))
  (check-exn #rx"^dt-convert-time-zone: cannot convert to the time zone \"Mars/Base\""
             (lambda () (dt-convert-time-zone wall "Mars/Base")))
  (check-exn #rx"^dt-replace-time-zone: cannot replace the time zone with \"Mars/Base\""
             (lambda () (dt-replace-time-zone (col "t") "Mars/Base")))
  (check-exn #rx"^dt-convert-time-zone: cannot convert to .* \"UTC\": expected Datetime, got date$"
             (lambda () (dt-convert-time-zone (series (list (date 2021 3 27))) "UTC")))
  (check-exn #rx"^dt-replace-time-zone: cannot unset the time zone: expected Datetime, got str$"
             (lambda () (dt-replace-time-zone (series '("x")) #f)))
  (for ([bad (list (lambda () (contracted:dt-convert-time-zone 5 "UTC"))
                   (lambda () (contracted:dt-convert-time-zone "t" ""))
                   (lambda () (contracted:dt-convert-time-zone "t" #f))
                   (lambda () (contracted:dt-replace-time-zone "t" 'utc))
                   (lambda () (contracted:dt-replace-time-zone "t" "UTC" #:ambiguous "raise"))
                   (lambda () (contracted:dt-replace-time-zone "t" "UTC" #:ambiguous 'first))
                   (lambda () (contracted:dt-replace-time-zone "t" "UTC" #:non-existent 'earliest)))])
    (check-exn exn:fail:contract:blame? bad))

  ;; a zoned series prints its zone and each value's abbreviation, as Python does
  (check-equal? (format "~a" (ref tz-ops "convert time zone"))
                (string-append "shape: (2,)\nSeries: 'convert time zone'"
                               " [datetime[us, Asia/Kathmandu]]\n[\n"
                               "\t2021-03-27 08:45:00 +0545\n\t2021-03-28 08:45:00 +0545\n]")))
