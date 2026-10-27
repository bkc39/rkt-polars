#lang racket/base

(module+ test
  (require rackunit
           (only-in gregor date datetime)
           (only-in gregor/period milliseconds nanoseconds)
           (only-in gregor/time time)
           (only-in racket/list make-list)
           (only-in polars/private/bulk series->list)
           (only-in polars/private/foreign
                    dataframe-column dataframe-column-name dataframe-height dataframe-new
                    dataframe-width polars-null series-dtype series-name series-new-f64
                    series-new-i32 series-new-str series-null-count series-ref)
           (only-in polars/private/series series-new-temporal series-repeat-temporal))

  (for ([elements (list (list (date 2024 1 2) polars-null (date -1300 5 23))
                        (list (time 5 6 7 8) polars-null (time 0))
                        (list (datetime 2024 1 2 9 30 0 123000000) polars-null
                              (datetime 2024 1 1 9))
                        (list (datetime 1969 12 31 23 59 59 999999999) polars-null
                              (datetime 2262 4 11))
                        (list (nanoseconds -1) polars-null (milliseconds 1500)))]
        [dtype (list 'date 'time '(datetime milliseconds #f) '(datetime nanoseconds #f)
                     '(duration nanoseconds))]
        [expected (list #f #f #f #f (list (nanoseconds -1) polars-null (nanoseconds 1500000000)))])
    (for ([shaped (list elements (list->vector elements))])
      (define t (series-new-temporal 'test "t" shaped dtype))
      (check-equal? (series-dtype t) dtype)
      (check-equal? (series-name t) "t")
      (check-equal? (series-null-count t) 1)
      (check-equal? (series->list t) (or expected elements))
      (check-equal? (for/list ([i (in-range 3)]) (series-ref t i))
                    (series->list t)))
    (for ([value (list (car elements) polars-null)])
      (define repeated (series-repeat-temporal 'test "r" value 4 dtype))
      (check-equal? (series-dtype repeated) dtype)
      (check-equal? (series-name repeated) "r")
      (check-equal? (series->list repeated)
                    (series->list (series-new-temporal 'test "r" (make-list 4 value) dtype)))))
  (check-equal? (series->list (series-repeat-temporal 'test "r" (nanoseconds 1999999) 2
                                                      '(duration milliseconds)))
                (list (milliseconds 1) (milliseconds 1)))
  (check-equal? (series->list (series-new-temporal 'test "d" (list (date -1300 5 23)) 'date))
                (list (date -1300 5 23)))
  (check-exn #rx"^test: expected a gregor date for this dtype"
             (lambda () (series-new-temporal 'test "d" (vector (datetime 2024)) 'date)))
  (check-exn #rx"^test: expected a gregor date for this dtype"
             (lambda () (series-repeat-temporal 'test "d" (datetime 2024) 3 'date)))

  ;; Mirror of rust/examples/02_dataframe_from_series.rs
  (define users   (series-new-str "user" '("alice" "bob" "carol" "dora")))
  (define scores  (series-new-i32 "score" '(10 25 18 41)))
  (define costs   (series-new-f64 "cost" '(1.2 3.5 2.0 8.4)))
  (define created (series-new-temporal
                   'test
                   "created_at"
                   (list (datetime 2024 1 1 8 0 0)
                         (datetime 2024 1 2 8 0 0)
                         (datetime 2024 1 3 8 0 0)
                         (datetime 2024 1 4 8 0 0))
                   '(datetime milliseconds #f)))
  (define df (dataframe-new (list users scores costs created)))
  (check-equal? (dataframe-height df) 4)
  (check-equal? (dataframe-width df) 4)
  (check-equal? (dataframe-column-name df 3) "created_at")
  (check-equal? (series-dtype (dataframe-column df "created_at"))
                '(datetime milliseconds #f)))
