#lang racket/base

(require (only-in racket/contract/base -> contract-out or/c)
         (only-in racket/format ~r)
         racket/match
         (only-in gregor +days date date->iso8601)
         (only-in threading ~>)
         (only-in polars/private/expr
                  col expr-drop expr-sort lazyframe-drop lazyframe-select lazyframe-with-columns
                  lit/who)
         (only-in (submod polars/private/expr internal) collect-plan/who)
         (only-in (submod polars/private/foreign internal) dataframe-column/who)
         (only-in polars/private/expr-dt expr-dt-replace-time-zone)
         (only-in polars/private/foreign
                  dataframe-column-names dataframe-drop dataframe-height
                  dataframe-new decimal-dtype?
                  polars-null polars-null? series-drop series-dtype series-null-count
                  series-rename/who zoned-datetime-dtype?)
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
  (define s (dataframe-column/who 'describe d column))
  (series-rename/who 'describe s name)
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
     (own (gather c (own (lit/who 'describe row))))]))

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

(module+ internal
  (provide call-with-column-plans column-plan-series describe offset->string))
