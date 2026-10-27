#lang racket/base

(module+ test
  (require rackunit
           (only-in gregor moment)
           (only-in racket/list make-list)
           (only-in racket/match match-define)
           (only-in racket/math nan?)
           (only-in threading ~>)
           (only-in polars/private/expr-core expr-drop-count lazyframe-drop-count)
           (only-in polars/private/foreign
                    dataframe-drop dataframe-drop-count series-drop series-drop-count
                    series-quantile)
           (only-in polars/private/generic/core
                    column-names dataframe dataframe? height len null-count ref series)
           (prefix-in contracted: polars/private/generic/describe)
           (only-in (submod polars/private/generic/describe internal)
                    call-with-column-plans column-plan-series describe offset->string)
           (only-in polars/private/generic/math p-abs)
           (only-in polars/private/generic/parquet read-parquet)
           (only-in polars/private/generic/reductions alias max mean min std)
           (only-in polars/private/generic/reshape
                    agg cast collect group-by head lazy select with-columns)
           (only-in polars/tests/generic/test-fixtures
                    col column drops-during frame polars-null polars-null? produce-parquet
                    settle!))
  ;; describe returns a Polars-style stats dataframe (matching .describe())
  (define sc (series '(10 25 18) #:name "score" #:dtype 'i32))
  (define sc-desc (describe sc))
  (check-pred dataframe? sc-desc)
  (check-equal? (column-names sc-desc) '("statistic" "value"))
  (check-equal? (height sc-desc) 9)
  (check-equal? (ref (ref sc-desc #:columns "statistic") 0) "count")
  (check-equal? (ref (ref sc-desc #:columns "value") 0) 3.0)   ; count
  (check-equal? (ref (ref sc-desc #:columns "value") 4) 10.0)  ; min
  (check-equal? (ref (ref sc-desc #:columns "value") 8) 25.0)  ; max
  (define fr-desc (describe frame))
  (check-pred dataframe? fr-desc)
  (check-equal? (height fr-desc) 9)
  (check-equal? (column-names fr-desc) '("statistic" "user" "score" "cost"))
  (check-equal? (ref (ref fr-desc #:columns "user") 0) "3")       ; string count
  (check-equal? (ref (ref fr-desc #:columns "user") 4) "alice")   ; string min
  (check-equal? (ref (ref fr-desc #:columns "user") 8) "carol")   ; string max
  (check-pred polars-null? (ref (ref fr-desc #:columns "user") 2)) ; mean -> null
  (check-equal? (ref (ref fr-desc #:columns "score") 4) 10.0)     ; numeric min

  (define (check-column d name expected)
    (check-equal? (length (column d name)) (length expected))
    (for ([got (in-list (column d name))]
          [want (in-list expected)])
      (if (and (flonum? want) (not (nan? want)))
          (check-= got want 1e-12)
          (check-equal? got want))))

  (define (nulls n) (make-list n polars-null))

  (define nums
    (dataframe (list (series (list 5 polars-null 3 9 1 2 polars-null 8) #:name "i")
                     (series (list 1.5 2.25 polars-null -3.0 0.5 7.75 4.0 polars-null) #:name "f")
                     (series '(7 8 9 10 11 12 13 14) #:name "u" #:dtype 'u8))))
  (for ([name (in-list '("i" "f" "u"))])
    (define s (ref nums name))
    (check-column (describe nums) name
                  (map exact->inexact
                       (list (- (len s) (null-count s)) (null-count s) (mean s) (std s)
                             (min s) (series-quantile s 0.25) (series-quantile s 0.5)
                             (series-quantile s 0.75) (max s)))))

  ;; expected values are Python polars 1.42.1's describe() of the same frames
  (check-column (describe (series '(1 2))) "value" '(2.0 0.0 1.5 0.7071067811865476 1.0 1.0 2.0 2.0 2.0))

  (define mixed
    (dataframe
     (list (series (list 1.5 2.5 +nan.0 polars-null -3.25 0.0) #:name "f")
           (series (list #t #f polars-null #t #t #f) #:name "b")
           (series (list "pear" polars-null "apple" "fig" "" "Zed") #:name "s")
           (series (nulls 6) #:name "none" #:dtype 'f64)
           (series '("a" "b" "c" "d" "e" "f") #:name "*")
           (series '(1 2 3 4 5 6) #:name "^i$"))))
  (define mixed-desc (describe mixed))
  (check-equal? (column-names mixed-desc) '("statistic" "f" "b" "s" "none" "*" "^i$"))
  (check-column mixed-desc "f" '(5.0 1.0 +nan.0 +nan.0 -3.25 0.0 1.5 2.5 2.5))
  (check-column mixed-desc "b" (list 5.0 1.0 0.6 polars-null 0.0 polars-null polars-null
                                     polars-null 1.0))
  (check-column mixed-desc "s" (list "5" "1" polars-null polars-null "" polars-null polars-null
                                     polars-null "pear"))
  (check-column mixed-desc "none" (list* 0.0 6.0 (nulls 7)))
  (check-column mixed-desc "*" (list "6" "0" polars-null polars-null "a" polars-null polars-null
                                     polars-null "f"))
  (check-column mixed-desc "^i$" '(6.0 0.0 3.5 1.8708286933869707 1.0 2.0 4.0 5.0 6.0))

  (define ms (series (list 1500 -250 86400001 polars-null -172800000 7) #:name "ms"))
  (define ns (series (list 3723000000001 -1 999 polars-null 86399999999999 5) #:name "ns"))
  (define temporal
    (select (dataframe (list ms ns))
            (~> "ms" (cast '(datetime milliseconds)) (alias "dtm"))
            (~> "ms" (cast '(duration milliseconds)) (alias "durm"))
            (~> "ns" (cast '(datetime nanoseconds)) (alias "dtn"))
            (~> "ns" (cast '(duration nanoseconds)) (alias "durn"))
            (~> "ns" p-abs (cast 'time) (alias "t"))
            (~> "ms" (cast '(datetime milliseconds)) (cast 'date) (alias "d"))))
  (define temporal-desc (describe temporal))
  (check-column temporal-desc "dtm"
                (list "5" "1" "1969-12-31 19:12:00.252000" polars-null "1969-12-30 00:00:00"
                      "1969-12-31 23:59:59.750000" "1970-01-01 00:00:00.007000"
                      "1970-01-01 00:00:01.500000" "1970-01-02 00:00:00.001000"))
  (check-column temporal-desc "durm"
                (list "5" "1" "-1 day, 19:12:00.252000" polars-null "-2 days, 0:00:00"
                      "-1 day, 23:59:59.750000" "0:00:00.007000" "0:00:01.500000"
                      "1 day, 0:00:00.001000"))
  (check-column temporal-desc "dtn"
                (list "5" "1" "1970-01-01 05:00:24.600000" polars-null "1969-12-31 23:59:59.999999"
                      "1970-01-01 00:00:00" "1970-01-01 00:00:00" "1970-01-01 01:02:03"
                      "1970-01-01 23:59:59.999999"))
  (check-column temporal-desc "durn"
                (list "5" "1" "5:00:24.600000" polars-null "0:00:00" "0:00:00" "0:00:00" "1:02:03"
                      "23:59:59.999999"))
  (check-column temporal-desc "t"
                (list "5" "1" "05:00:24.600000" polars-null "00:00:00" "00:00:00" "00:00:00"
                      "01:02:03" "23:59:59.999999"))
  (check-column temporal-desc "d"
                (list "5" "1" "1969-12-31 14:24:00" polars-null "1969-12-30" "1969-12-31"
                      "1970-01-01" "1970-01-01" "1970-01-02"))
  (define days (select (dataframe (list (series '(0 1 2 3 4 5 7) #:name "d" #:dtype 'i32)))
                       (cast "d" 'date)))
  (check-column (describe days) "d"
                (list "7" "0" "1970-01-04 03:25:42.857142" polars-null "1970-01-01" "1970-01-03"
                      "1970-01-04" "1970-01-06" "1970-01-08"))

  (define zoned
    (dataframe
     (list (series (list (moment 2021 3 27 12 0 0 500000000 #:tz "Europe/Brussels") polars-null
                         (moment 2021 7 1 #:tz "Europe/Brussels"))
                   #:name "t")
           (cast (series (list (* 1616825700 1000000) (* (- -2208988800 20476) 1000000)
                               polars-null)
                         #:name "k")
                 '(datetime microseconds "Asia/Kathmandu"))
           (series (list (moment 2020 1 1 12 #:tz "America/New_York") polars-null polars-null)
                   #:name "ny"))))
  (define zoned-desc (describe zoned))
  (check-column zoned-desc "t"
                (list "2" "1" "2021-05-14 06:30:00.250000+02:00" polars-null
                      "2021-03-27 12:00:00.500000+01:00" "2021-03-27 12:00:00.500000+01:00"
                      "2021-07-01 00:00:00+02:00" "2021-07-01 00:00:00+02:00"
                      "2021-07-01 00:00:00+02:00"))
  (check-column zoned-desc "k"
                (list "2" "1" "1960-08-14 05:46:52+05:30" polars-null
                      "1900-01-01 00:00:00+05:41:16" "1900-01-01 00:00:00+05:41:16"
                      "2021-03-27 12:00:00+05:45" "2021-03-27 12:00:00+05:45"
                      "2021-03-27 12:00:00+05:45"))
  (check-column zoned-desc "ny" (list* "1" "2" "2020-01-01 12:00:00-05:00" polars-null
                                       (make-list 5 "2020-01-01 12:00:00-05:00")))
  (check-column (describe (ref zoned "t")) "value"
                (list "2" "1" "2021-05-14 06:30:00.250000+02:00"
                      "2021-03-27 12:00:00.500000+01:00" "2021-03-27 12:00:00.500000+01:00"
                      "2021-07-01 00:00:00+02:00" "2021-07-01 00:00:00+02:00"
                      "2021-07-01 00:00:00+02:00"))
  (define zoned-temporal
    (select (dataframe (list ms ns))
            (~> "ms" (cast '(datetime milliseconds "Asia/Kathmandu")) (alias "ms"))
            (~> "ns" (cast '(datetime nanoseconds "America/New_York")) (alias "ns"))))
  (check-column (describe zoned-temporal) "ms"
                (list "5" "1" "1970-01-01 00:42:00.252000+05:30" polars-null
                      "1969-12-30 05:30:00+05:30" "1970-01-01 05:29:59.750000+05:30"
                      "1970-01-01 05:30:00.007000+05:30" "1970-01-01 05:30:01.500000+05:30"
                      "1970-01-02 05:30:00.001000+05:30"))
  (check-column (describe zoned-temporal) "ns"
                (list "5" "1" "1970-01-01 00:00:24.600000-05:00" polars-null
                      "1969-12-31 18:59:59.999999-05:00" "1969-12-31 19:00:00-05:00"
                      "1969-12-31 19:00:00-05:00" "1969-12-31 20:02:03-05:00"
                      "1970-01-01 18:59:59.999999-05:00"))
  (check-column (describe (series (list (moment 2021 3 27 12 #:tz "Europe/Brussels")
                                        (moment 2021 7 1 #:tz "Europe/Brussels"))
                                  #:name "local"))
                "value"
                (list "2" "0" "2021-05-14 06:30:00+02:00" "2021-03-27 12:00:00+01:00"
                      "2021-03-27 12:00:00+01:00" "2021-07-01 00:00:00+02:00"
                      "2021-07-01 00:00:00+02:00" "2021-07-01 00:00:00+02:00"))
  (define ns-edges
    (dataframe
     (list (cast (series (list 9223369200000000001 polars-null) #:name "east")
                 '(datetime nanoseconds "Asia/Tokyo"))
           (cast (series (list (+ (- (sub1 (expt 2 63))) 3600000000000) polars-null) #:name "west")
                 '(datetime nanoseconds "America/New_York")))))
  (for ([name '("east" "west")]
        [shown '("2262-04-12 08:00:00+09:00" "1677-09-20 20:16:41.145224-04:56:02")])
    (check-column (describe ns-edges) name (list* "1" "1" shown polars-null (make-list 5 shown))))
  (check-equal? (map offset->string '(0 3600 -18000 20700 1050 -1050))
                '("+00:00" "+01:00" "-05:00" "+05:45" "+00:17:30" "-00:17:30"))

  (define grouped
    (~> (dataframe (list (series '("x" "y" "x") #:name "k") (series '(1 2 3) #:name "v")))
        (group-by "k")
        (agg (col "v"))))
  (check-column (describe grouped) "v" (list* 2.0 0.0 (nulls 7)))
  (check-column (describe grouped) "k" (list "2" "0" polars-null polars-null "x" polars-null
                                             polars-null polars-null "y"))

  (check-equal? (~> temporal (ref "d") describe (column "statistic"))
                '("count" "null_count" "mean" "min" "25%" "50%" "75%" "max"))
  (check-equal? (~> mixed (ref "b") describe (column "statistic"))
                '("count" "null_count" "mean" "min" "max"))
  (check-equal? (~> mixed (ref "none") describe (column "statistic"))
                '("count" "null_count" "mean" "std" "min" "25%" "50%" "75%" "max"))

  (define produce-desc (describe (read-parquet produce-parquet)))
  (check-column produce-desc "item" (list* "4" "0" (nulls 7)))
  (check-column produce-desc "grade" (list* "3" "1" (nulls 7)))
  (check-column produce-desc "price"
                '(3.0 1.0 4.683333333333334 6.3404127100160705 0.8 1.25 1.25 12.0 12.0))

  (define empty-desc (describe (head frame 0)))
  (check-column empty-desc "user" (list* "0" "0" (nulls 7)))
  (check-column empty-desc "score" (list* 0.0 0.0 (nulls 7)))
  (define no-columns (describe (dataframe '())))
  (check-equal? (column-names no-columns) '("statistic"))
  (check-equal? (height no-columns) 9)

  (check-exn #rx"^describe: contract violation" (lambda () (contracted:describe 5)))
  (check-exn #rx"^describe: contract violation" (lambda () (contracted:describe (col "a"))))

  (define planned (box '()))
  (define (note-copies plans)
    (set-box! planned (map column-plan-series plans)))
  (check-equal? (drops-during series-drop-count
                              (lambda () (call-with-column-plans nums note-copies)))
                (length (column-names nums)))
  (check-equal? (length (unbox planned)) (length (column-names nums)))
  (for ([copy (in-list (unbox planned))])
    (check-exn #rx"^series-drop: series has been dropped" (lambda () (series-drop copy))))
  (check-equal? (drops-during series-drop-count
                              (lambda ()
                                (check-exn #rx"^boom"
                                           (lambda ()
                                             (call-with-column-plans
                                              nums (lambda (plans) (error 'boom "")))))))
                (length (column-names nums)))

  (define numeric
    (dataframe (list (series '(5 3 9 1) #:name "i") (series '(1.5 -3.0 0.5 7.75) #:name "f"))))
  (define all-null
    (dataframe (for/list ([i (in-range 4)])
                 (series (nulls 3) #:name (format "n~a" i) #:dtype 'i64))))
  (define zoned-column
    (dataframe (list (cast (series (list 1 2 polars-null) #:name "k")
                           '(datetime microseconds "Asia/Kathmandu")))))
  (define counters
    (list (cons 'series series-drop-count)
          (cons 'dataframe dataframe-drop-count)
          (cons 'lazyframe lazyframe-drop-count)
          (cons 'expression expr-drop-count)))
  (for ([row (in-list (list (list "numeric frame" numeric '(19 3 3 52))
                            (list "series" (series '(1 2)) '(10 4 3 26))
                            (list "all-null frame" all-null '(9 1 0 0))
                            (list "zoned frame" zoned-column '(15 3 3 53))))])
    (match-define (list label x expected) row)
    (define (describe-and-drop) (dataframe-drop (describe x)))
    (for ([counter (in-list counters)]
          [want (in-list expected)])
      (match-define (cons kind count) counter)
      (define info (format "~a, ~a releases" label kind))
      (check-equal? (drops-during count describe-and-drop) want info)
      (check-equal? (drops-during count (lambda () (describe-and-drop) (settle!))) want info))))
