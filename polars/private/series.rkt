#lang racket/base

(require gregor
         polars/private/foreign)

(module+ test
  (require rackunit))

(provide series-new-datetime
         series-new-datetime/vec)

(define (datetime->ymdhms dt)
  (make-YMDHMS (->year dt)
               (->month dt)
               (->day dt)
               (->hours dt)
               (->minutes dt)
               (->seconds dt)))

(define (series-new-datetime name datetimes)
  (series-new-ymdhms name
                     (map (lambda (dt)
                            (if (polars-null? dt)
                                polars-null
                                (datetime->ymdhms dt)))
                          datetimes)))

(define (series-new-datetime/vec name datetimes)
  (series-new-ymdhms/vec name
                         (for/vector #:length (vector-length datetimes)
                                     ([dt (in-vector datetimes)])
                           (if (polars-null? dt)
                               polars-null
                               (datetime->ymdhms dt)))))

(module+ test
  (define ts0 (datetime 2024 1 1 9 0 0))
  (define ts1 (datetime 2024 1 2 9 30 0))
  (define s (series-new-datetime "ts" (list ts0 ts1)))
  (check-pred Series-ptr? s)
  (check-equal? (series-len s) 2)
  (check-equal? (series-name s) "ts")
  (check-equal? (series-dtype s) '(datetime milliseconds #f))

  (define sv (series-new-datetime/vec "tsv" (vector ts0 ts1)))
  (check-pred Series-ptr? sv)
  (check-equal? (series-len sv) 2)
  (define sn (series-new-datetime "tsn" (list ts0 polars-null ts1)))
  (check-equal? (series-null-count sn) 1)
  (check-equal? (series-ref sn 0) ts0)
  (check-equal? (series-ref sn 1) polars-null)

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
