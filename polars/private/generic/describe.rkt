#lang racket/base

(require (only-in racket/contract/base -> contract-out or/c)
         (only-in racket/format ~r)
         racket/match
         (only-in gregor +days date date->iso8601)
         (only-in threading ~>)
         (only-in polars/private/expr
                  col expr-drop expr-sort lazyframe-drop lazyframe-select lazyframe-with-columns
                  lit)
         (only-in (submod polars/private/expr internal) collect-plan/who)
         (only-in polars/private/expr-dt expr-dt-replace-time-zone)
         (only-in polars/private/foreign
                  dataframe-column dataframe-column-names dataframe-drop dataframe-height
                  dataframe-new decimal-dtype?
                  polars-null polars-null? series-drop series-dtype series-null-count
                  series-rename zoned-datetime-dtype?)
         (only-in polars/private/generic/core
                  dataframe dataframe? ref series series? wrap-dataframe)
         (only-in polars/private/generic/dtype numeric-dtype? temporal-dtype?)
         (only-in polars/private/temporal offset-unit per-second utc-offset)
         (only-in polars/private/generic/ordering gather)
         (only-in polars/private/generic/reductions alias max mean min std)
         (only-in polars/private/generic/reshape cast)
         (only-in polars/private/resource with-release with-release-pool with-releases))

(provide (contract-out [describe (-> (or/c series? dataframe?) dataframe?)]))

(define statistics '("count" "null_count" "mean" "std" "min" "25%" "50%" "75%" "max"))
(define counts '("count" "null_count"))
(define quantiles (hash "25%" 1/4 "50%" 1/2 "75%" 3/4))

(struct column-plan (name series dtype count nulls queried))

(define (quantile-statistic? stat) (hash-has-key? quantiles stat))

(define (float-valued? dt)
  (match dt
    [(or 'boolean 'null (list* 'todo 'nested-dtype-support _)) #t]
    [_ (or (numeric-dtype? dt) (decimal-dtype? dt))]))

(define (dtype-statistics dt)
  (cond
    [(or (numeric-dtype? dt) (decimal-dtype? dt)) statistics]
    [(eq? dt 'boolean) '("count" "null_count" "mean" "min" "max")]
    [(temporal-dtype? dt) (remove "std" statistics)]
    [(eq? dt 'string) '("count" "null_count" "min" "max")]
    [else counts]))

(define (plan-column d column i height)
  (define name (number->string i))
  (define s (dataframe-column d column))
  (series-rename s name)
  (define dt (series-dtype s))
  (define nulls (series-null-count s))
  (define count (- height nulls))
  (column-plan name s dt count nulls
               (if (zero? count) '() (remove* counts (dtype-statistics dt)))))

(define (needs-sort? plan)
  (ormap quantile-statistic? (column-plan-queried plan)))

(define (cell-name plan stat) (format "~a:~a" (column-plan-name plan) stat))

(define (date-mean? dt stat)
  (and (eq? dt 'date) (equal? stat "mean")))

(define (statistic-dtype dt stat)
  (if (date-mean? dt stat) '(datetime microseconds #f) dt))

;; The row Polars' nearest interpolation picks once the column is sorted nulls
;; first; Rust's f64 round goes half away from zero, Racket's round does not.
(define (nearest-row q count nulls)
  (+ nulls (floor (+ (* (sub1 count) q) 1/2))))

(define (reduce c own plan stat)
  (match stat
    ["mean" (own (mean c))]
    ["std" (own (std c))]
    ["min" (own (min c))]
    ["max" (own (max c))]
    [(? quantile-statistic?)
     (define row
       (nearest-row (hash-ref quantiles stat) (column-plan-count plan) (column-plan-nulls plan)))
     (own (gather c (own (lit row))))]))

(define (cast-when e own cast? dtype)
  (if cast? (own (cast e dtype)) e))

(define (local-cell-name plan stat) (format "~a:local" (cell-name plan stat)))

(define (statistic-exprs own plan stat)
  (define dt (column-plan-dtype plan))
  (define value
    (~> (col (column-plan-name plan)) own
        (cast-when own (date-mean? dt stat) '(datetime microseconds))
        (reduce own plan stat)))
  (cons (~> value (cast-when own (temporal-dtype? dt) 'int64) (alias (cell-name plan stat)) own)
        (match dt
          [(list 'datetime unit (? string? zone))
           (list (~> value (cast (list 'datetime (offset-unit unit) zone)) own
                     (expr-dt-replace-time-zone #f) own (cast 'int64) own
                     (alias (local-cell-name plan stat)) own))]
          [_ '()])))

(define (statistics-plan source plans)
  (with-release-pool ([own expr-drop])
    (define sorts
      (for/list ([plan (in-list plans)]
                 #:when (needs-sort? plan))
        (~> (col (column-plan-name plan)) own expr-sort own)))
    (define cells
      (for*/list ([plan (in-list plans)]
                  [stat (in-list (column-plan-queried plan))]
                  [e (in-list (statistic-exprs own plan stat))])
        e))
    (with-release ([sorted (lazyframe-with-columns source sorts) lazyframe-drop])
      (lazyframe-select sorted cells))))

(define (call-with-statistics-row plans proc)
  (with-release ([frame (dataframe-new (map column-plan-series plans)) dataframe-drop]
                 [row (collect-plan/who 'describe frame (lambda (source)
                                                          (statistics-plan source plans)))
                      dataframe-drop])
    (proc (wrap-dataframe row))))

(define epoch (date 1970 1 1))
(define microseconds/day 86400000000)

(define (->microseconds unit v rounding)
  (case unit
    [(nanoseconds) (rounding (/ v 1000))]
    [(milliseconds) (* v 1000)]
    [else v]))

(define (pad n width) (~r n #:min-width width #:pad-string "0"))

(define (clock->string us #:hour-width [hour-width 2])
  (define-values (seconds fraction) (quotient/remainder us 1000000))
  (define-values (minutes second) (quotient/remainder seconds 60))
  (define-values (hour minute) (quotient/remainder minutes 60))
  (string-append (pad hour hour-width) ":" (pad minute 2) ":" (pad second 2)
                 (if (zero? fraction) "" (string-append "." (pad fraction 6)))))

(define (day-and-clock us)
  (define days (floor (/ us microseconds/day)))
  (values days (- us (* days microseconds/day))))

(define (day->string days) (date->iso8601 (+days epoch days)))

(define (offset->string seconds)
  (define-values (hours rest) (quotient/remainder (abs seconds) 3600))
  (define-values (minutes second) (quotient/remainder rest 60))
  (string-append (if (negative? seconds) "-" "+") (pad hours 2) ":" (pad minutes 2)
                 (if (zero? second) "" (string-append ":" (pad second 2)))))

(define (temporal->string dt v)
  (match dt
    ['date (day->string v)]
    ['time (~> v (/ 1000) floor clock->string)]
    [(list 'datetime unit (? string?))
     (match-define (cons instant clock) v)
     (define offset (utc-offset unit instant clock))
     (string-append (temporal->string (list 'datetime unit #f)
                                      (+ instant (* offset (per-second unit))))
                    (offset->string offset))]
    [(list 'datetime unit _)
     (define-values (days clock) (day-and-clock (->microseconds unit v floor)))
     (string-append (day->string days) " " (clock->string clock))]
    [(list 'duration unit)
     (define-values (days clock) (day-and-clock (->microseconds unit v truncate)))
     (define hms (clock->string clock #:hour-width 1))
     (if (zero? days)
         hms
         (format "~a day~a, ~a" days (if (= (abs days) 1) "" "s") hms))]))

(define (cell-value dt stat v)
  (cond
    [(polars-null? v) v]
    [(float-valued? dt) (if (boolean? v) (if v 1.0 0.0) (exact->inexact v))]
    [(member stat counts) (number->string v)]
    [(temporal-dtype? dt) (temporal->string (statistic-dtype dt stat) v)]
    [else v]))

(define (statistic-value row plan stat)
  (define (cell name)
    (with-release ([c (ref row name) series-drop])
      (ref c 0)))
  (define v (cell (cell-name plan stat)))
  (if (and (zoned-datetime-dtype? (column-plan-dtype plan)) (not (polars-null? v)))
      (cons v (cell (local-cell-name plan stat)))
      v))

(define (call-with-column-plans d proc)
  (define height (dataframe-height d))
  (with-releases ([plans ([column (in-list (dataframe-column-names d))]
                          [i (in-naturals)])
                         (plan-column d column i height)
                         (lambda (plan) (series-drop (column-plan-series plan)))])
    (proc plans)))

(define (plan-cells plans row)
  (for/list ([plan (in-list plans)])
    (match-define (column-plan _ _ dt count nulls queried) plan)
    (for/list ([stat (in-list statistics)])
      (cell-value dt stat
                  (match stat
                    ["count" count]
                    ["null_count" nulls]
                    [_ #:when (member stat queried) (statistic-value row plan stat)]
                    [_ polars-null])))))

(define (plan-statistics plans)
  (if (ormap (lambda (plan) (pair? (column-plan-queried plan))) plans)
      (call-with-statistics-row plans (lambda (row) (plan-cells plans row)))
      (plan-cells plans #f)))

(define (dataframe-of-columns names columns)
  (with-releases ([built ([name (in-list names)] [values (in-list columns)])
                         (series values #:name name)
                         series-drop])
    (dataframe built)))

(define (describe-series s)
  (define rows (dtype-statistics (series-dtype s)))
  (match-define (list values)
    (with-release ([d (dataframe-new (list s)) dataframe-drop])
      (call-with-column-plans d plan-statistics)))
  (dataframe-of-columns '("statistic" "value")
                        (list rows
                              (for/list ([stat (in-list statistics)]
                                         [v (in-list values)]
                                         #:when (member stat rows))
                                v))))

(define (describe-dataframe d)
  (define names (dataframe-column-names d))
  (dataframe-of-columns (cons "statistic" names)
                        (cons statistics (call-with-column-plans d plan-statistics))))

(define (describe x)
  (if (series? x)
      (describe-series x)
      (describe-dataframe x)))

(module+ test
  (require rackunit
           polars/private/generic/core
           polars/private/generic/test-fixtures)
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

  (require (only-in gregor moment)
           (only-in racket/list make-list)
           (only-in racket/math nan?)
           (only-in polars/private/generic/parquet read-parquet)
           (only-in polars/private/expr-core expr-drop-count lazyframe-drop-count)
           (only-in polars/private/foreign dataframe-drop-count series-drop-count series-quantile)
           (only-in polars/private/generic/math p-abs)
           (only-in polars/private/generic/reshape agg collect group-by head lazy select
                    with-columns)
           (prefix-in contracted: (submod "..")))

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
