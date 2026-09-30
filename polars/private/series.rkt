#lang racket/base

(require polars/private/foreign
         (only-in polars/private/resource with-release)
         (only-in polars/private/temporal temporal-encoder))

(provide series-new-datetime
         series-new-datetime/vec
         series-new-temporal)

(define (series-new-temporal who name elements dtype)
  (define encode (temporal-encoder who dtype))
  (define (physical v) (if (polars-null? v) v (encode v)))
  (define-values (physicals construct)
    (if (vector? elements)
        (values (for/vector #:length (vector-length elements) ([v (in-vector elements)])
                  (physical v))
                (if (eq? dtype 'date) series-new-i32/vec series-new-i64/vec))
        (values (map physical elements)
                (if (eq? dtype 'date) series-new-i32 series-new-i64))))
  (with-release ([s (construct name physicals) series-drop])
    (series-cast s dtype)))

(define (series-new-datetime name datetimes)
  (series-new-temporal 'series-new-datetime name datetimes '(datetime milliseconds #f)))

(define (series-new-datetime/vec name datetimes)
  (series-new-temporal 'series-new-datetime/vec name datetimes '(datetime milliseconds #f)))

(module+ test
  (require rackunit
           (only-in gregor date datetime)
           (only-in gregor/period milliseconds nanoseconds)
           (only-in gregor/time time)
           (only-in polars/private/bulk series->list))

  (define ts0 (datetime 2024 1 1 9 0 0))
  (define ts1 (datetime 2024 1 2 9 30 0 123000000))
  (define s (series-new-datetime "ts" (list ts0 ts1)))
  (check-pred Series-ptr? s)
  (check-equal? (series-len s) 2)
  (check-equal? (series-name s) "ts")
  (check-equal? (series-dtype s) '(datetime milliseconds #f))
  (check-equal? (series-ref s 1) ts1)

  (define sv (series-new-datetime/vec "tsv" (vector ts0 ts1)))
  (check-pred Series-ptr? sv)
  (check-equal? (series-len sv) 2)
  (define sn (series-new-datetime "tsn" (list ts0 polars-null ts1)))
  (check-equal? (series-null-count sn) 1)
  (check-equal? (series-ref sn 0) ts0)
  (check-equal? (series-ref sn 1) polars-null)

  (for ([elements (list (list (date 2024 1 2) polars-null (date -1300 5 23))
                        (list (time 5 6 7 8) polars-null (time 0))
                        (list (datetime 1969 12 31 23 59 59 999999999) polars-null
                              (datetime 2262 4 11))
                        (list (nanoseconds -1) polars-null (milliseconds 1500)))]
        [dtype (list 'date 'time '(datetime nanoseconds #f) '(duration nanoseconds))]
        [expected (list 'date 'time '(datetime nanoseconds #f) '(duration nanoseconds))])
    (for ([shaped (list elements (list->vector elements))])
      (define t (series-new-temporal 'test "t" shaped dtype))
      (check-equal? (series-dtype t) expected)
      (check-equal? (series-name t) "t")
      (check-equal? (for/list ([i (in-range 3)]) (series-ref t i))
                    (series->list t))))
  (check-equal? (series->list (series-new-temporal 'test "d" (list (date -1300 5 23)) 'date))
                (list (date -1300 5 23)))
  (check-exn #rx"^test: expected a gregor date for this dtype"
             (lambda () (series-new-temporal 'test "d" (vector (datetime 2024)) 'date)))

  ;; Mirror of rust/examples/02_dataframe_from_series.rs
  (define users   (series-new-str "user" '("alice" "bob" "carol" "dora")))
  (define scores  (series-new-i32 "score" '(10 25 18 41)))
  (define costs   (series-new-f64 "cost" '(1.2 3.5 2.0 8.4)))
  (define created (series-new-datetime
                   "created_at"
                   (list (datetime 2024 1 1 8 0 0)
                         (datetime 2024 1 2 8 0 0)
                         (datetime 2024 1 3 8 0 0)
                         (datetime 2024 1 4 8 0 0))))
  (define df (dataframe-new (list users scores costs created)))
  (check-equal? (dataframe-height df) 4)
  (check-equal? (dataframe-width df) 4)
  (check-equal? (dataframe-column-name df 3) "created_at")
  (check-equal? (series-dtype (dataframe-column df "created_at"))
                '(datetime milliseconds #f)))
