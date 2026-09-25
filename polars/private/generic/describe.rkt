#lang racket/base

(require (only-in racket/contract/base -> contract-out or/c)
         (only-in racket/format ~r)
         racket/match
         (only-in gregor +days date date->iso8601)
         (only-in threading ~>)
         (only-in polars/private/expr
                  col dataframe-lazy expr-alias expr-cast expr-gather expr-max expr-mean
                  expr-min expr-sort expr-std lazyframe-collect lazyframe-select
                  lazyframe-with-columns lit)
         (only-in polars/private/foreign
                  dataframe-column dataframe-column-names dataframe-height dataframe-new
                  polars-null polars-null? series-dtype series-null-count series-ref
                  series-rename)
         (only-in polars/private/generic/core dataframe dataframe? series series?)
         (only-in polars/private/generic/dtype numeric-dtype?))

(provide (contract-out [describe (-> (or/c series? dataframe?) dataframe?)]))

(define statistics '("count" "null_count" "mean" "std" "min" "25%" "50%" "75%" "max"))
(define counts '("count" "null_count"))
(define quantiles (hash "25%" 1/4 "50%" 1/2 "75%" 3/4))

(struct column-plan (index dtype count nulls queried))

(define (temporal-dtype? dt)
  (match dt
    [(or 'date 'time (list 'datetime _ _) (list 'duration _)) #t]
    [_ #f]))

(define (float-valued? dt)
  (or (numeric-dtype? dt) (eq? dt 'boolean) (eq? dt 'null)))

(define (dtype-statistics dt)
  (cond
    [(numeric-dtype? dt) statistics]
    [(eq? dt 'boolean) '("count" "null_count" "mean" "min" "max")]
    [(temporal-dtype? dt) (remove "std" statistics)]
    [(eq? dt 'string) '("count" "null_count" "min" "max")]
    [else counts]))

(define (plan-column s i height)
  (define dt (series-dtype s))
  (define nulls (series-null-count s))
  (define count (- height nulls))
  (column-plan i dt count nulls
               (if (zero? count) '() (remove* counts (dtype-statistics dt)))))

(define (statistic-dtype dt stat)
  (if (and (eq? dt 'date) (equal? stat "mean")) '(datetime microseconds #f) dt))

;; The row Polars' nearest interpolation picks once the column is sorted nulls
;; first; Rust's f64 round goes half away from zero, Racket's round does not.
(define (nearest-row q count nulls)
  (+ nulls (floor (+ (* (sub1 count) q) 1/2))))

(define (statistic-expr plan stat)
  (match-define (column-plan i dt count nulls _) plan)
  (define c (col (number->string i)))
  (define e
    (match stat
      ["mean" (expr-mean c)]
      ["std" (expr-std c)]
      ["min" (expr-min c)]
      ["max" (expr-max c)]
      [_ (expr-gather c (lit (nearest-row (hash-ref quantiles stat) count nulls)))]))
  (define out (statistic-dtype dt stat))
  (expr-alias (cond
                [(not (temporal-dtype? dt)) e]
                [(equal? out dt) (expr-cast e 'int64)]
                [else (expr-cast (expr-cast e out) 'int64)])
              (cell-name i stat)))

(define (cell-name i stat) (format "~a:~a" i stat))

(define (needs-sort? plan)
  (for/or ([stat (in-list (column-plan-queried plan))])
    (hash-has-key? quantiles stat)))

(define (statistics-row frame plans)
  (~> (dataframe-lazy frame)
      (lazyframe-with-columns
       (for/list ([plan (in-list plans)] #:when (needs-sort? plan))
         (expr-sort (col (number->string (column-plan-index plan))))))
      (lazyframe-select
       (for*/list ([plan (in-list plans)]
                   [stat (in-list (column-plan-queried plan))])
         (statistic-expr plan stat)))
      lazyframe-collect))

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

(define (temporal->string dt v)
  (match dt
    ['date (date->iso8601 (+days epoch v))]
    ['time (clock->string (floor (/ v 1000)))]
    [(list 'datetime unit _)
     (define-values (days clock) (day-and-clock (->microseconds unit v floor)))
     (string-append (date->iso8601 (+days epoch days)) " " (clock->string clock))]
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

(define (column-statistics d)
  (define height (dataframe-height d))
  (define columns
    (for/list ([name (in-list (dataframe-column-names d))]
               [i (in-naturals)])
      (define s (dataframe-column d name))
      (series-rename s (number->string i))
      s))
  (define plans
    (for/list ([s (in-list columns)]
               [i (in-naturals)])
      (plan-column s i height)))
  (define row
    (and (ormap (lambda (plan) (pair? (column-plan-queried plan))) plans)
         (statistics-row (dataframe-new columns) plans)))
  (for/list ([plan (in-list plans)])
    (match-define (column-plan i dt count nulls queried) plan)
    (for/list ([stat (in-list statistics)])
      (cell-value dt stat
                  (cond
                    [(equal? stat "count") count]
                    [(equal? stat "null_count") nulls]
                    [(member stat queried)
                     (series-ref (dataframe-column row (cell-name i stat)) 0)]
                    [else polars-null])))))

(define (describe-series s)
  (define rows (dtype-statistics (series-dtype s)))
  (match-define (list values) (column-statistics (dataframe-new (list s))))
  (dataframe
   (list (series rows #:name "statistic")
         (series (for/list ([stat (in-list statistics)]
                            [v (in-list values)]
                            #:when (member stat rows))
                   v)
                 #:name "value"))))

(define (describe-dataframe d)
  (dataframe
   (cons (series statistics #:name "statistic")
         (for/list ([name (in-list (dataframe-column-names d))]
                    [values (in-list (column-statistics d))])
           (series values #:name name)))))

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
  (check-equal? (ref (ref fr-desc #:columns "score") 4) 10.0))    ; numeric min

(module+ test
  (require (only-in racket/math nan?)
           (only-in polars/private/expr expr-abs)
           (only-in polars/private/foreign dataframe-head series-quantile series-std)
           (only-in polars/private/generic/core len null-count ref wrap-dataframe)
           (only-in polars/private/generic/reductions alias max mean min)
           (only-in polars/private/generic/reshape cast select)
           (prefix-in contracted: (submod "..")))

  (define (check-column d name expected)
    (check-equal? (length (column d name)) (length expected))
    (for ([got (in-list (column d name))]
          [want (in-list expected)])
      (if (and (flonum? want) (not (nan? want)))
          (check-= got want 1e-12)
          (check-equal? got want))))

  (define nums
    (dataframe (list (series (list 5 polars-null 3 9 1 2 polars-null 8) #:name "i")
                     (series (list 1.5 2.25 polars-null -3.0 0.5 7.75 4.0 polars-null) #:name "f")
                     (series '(7 8 9 10 11 12 13 14) #:name "u" #:dtype 'u8))))
  (for ([name (in-list '("i" "f" "u"))])
    (define s (ref nums name))
    (check-column (describe nums) name
                  (map exact->inexact
                       (list (- (len s) (null-count s)) (null-count s) (mean s) (series-std s)
                             (min s) (series-quantile s 0.25) (series-quantile s 0.5)
                             (series-quantile s 0.75) (max s)))))
  (check-column (describe (series '(1 2))) "value" '(2.0 0.0 1.5 0.7071067811865476 1.0 1.0 2.0 2.0 2.0))

  ;; expected values are Python polars 1.42.1's describe() of the same frames
  (define mixed
    (dataframe
     (list (series (list 1.5 2.5 +nan.0 polars-null -3.25 0.0) #:name "f")
           (series (list #t #f polars-null #t #t #f) #:name "b")
           (series (list "pear" polars-null "apple" "fig" "" "Zed") #:name "s")
           (series (list polars-null polars-null polars-null polars-null polars-null polars-null)
                   #:name "none" #:dtype 'f64)
           (series '("a" "b" "c" "d" "e" "f") #:name "*")
           (series '(1 2 3 4 5 6) #:name "^i$"))))
  (define mixed-desc (describe mixed))
  (check-equal? (column-names mixed-desc) '("statistic" "f" "b" "s" "none" "*" "^i$"))
  (check-column mixed-desc "f" '(5.0 1.0 +nan.0 +nan.0 -3.25 0.0 1.5 2.5 2.5))
  (check-column mixed-desc "b" (list 5.0 1.0 0.6 polars-null 0.0 polars-null polars-null
                                     polars-null 1.0))
  (check-column mixed-desc "s" (list "5" "1" polars-null polars-null "" polars-null polars-null
                                     polars-null "pear"))
  (check-column mixed-desc "none" (list 0.0 6.0 polars-null polars-null polars-null polars-null
                                        polars-null polars-null polars-null))
  (check-column mixed-desc "*" (list "6" "0" polars-null polars-null "a" polars-null polars-null
                                     polars-null "f"))
  (check-column mixed-desc "^i$" '(6.0 0.0 3.5 1.8708286933869707 1.0 2.0 4.0 5.0 6.0))

  (define ms (series (list 1500 -250 86400001 polars-null -172800000 7) #:name "ms"))
  (define ns (series (list 3723000000001 -1 999 polars-null 86399999999999 5) #:name "ns"))
  (define temporal
    (select (dataframe (list ms ns))
            (alias (cast "ms" '(datetime milliseconds)) "dtm")
            (alias (cast "ms" '(duration milliseconds)) "durm")
            (alias (cast "ns" '(datetime nanoseconds)) "dtn")
            (alias (cast "ns" '(duration nanoseconds)) "durn")
            (alias (cast (expr-abs (col "ns")) 'time) "t")
            (alias (cast (cast "ms" '(datetime milliseconds)) 'date) "d")))
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

  (check-equal? (column (describe (ref temporal "d")) "statistic")
                '("count" "null_count" "mean" "min" "25%" "50%" "75%" "max"))
  (check-equal? (column (describe (ref mixed "b")) "statistic")
                '("count" "null_count" "mean" "min" "max"))
  (check-equal? (column (describe (ref mixed "none")) "statistic")
                '("count" "null_count" "mean" "std" "min" "25%" "50%" "75%" "max"))

  (define empty-desc (describe (wrap-dataframe (dataframe-head frame 0))))
  (check-column empty-desc "user" (list "0" "0" polars-null polars-null polars-null polars-null
                                        polars-null polars-null polars-null))
  (check-column empty-desc "score" (list 0.0 0.0 polars-null polars-null polars-null polars-null
                                         polars-null polars-null polars-null))
  (define no-columns (describe (dataframe '())))
  (check-equal? (column-names no-columns) '("statistic"))
  (check-equal? (height no-columns) 9)

  (check-exn #rx"^describe: contract violation" (lambda () (contracted:describe 5)))
  (check-exn #rx"^describe: contract violation" (lambda () (contracted:describe (col "a")))))
