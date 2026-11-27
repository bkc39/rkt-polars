#lang racket/base

(module+ test
  (require rackunit
           (only-in polars/private/compat-dtype ->compat-dtype enum-dtype? zoned-datetime-dtype?))

  (check-true (enum-dtype? '(enum)))
  (check-false (enum-dtype? '(enum a . b)))
  (check-exn #rx"^->compat-dtype: unsupported cast target '\\(datetime microseconds \"UTC\"\\)"
             (lambda () (->compat-dtype '(datetime microseconds "UTC"))))
  (check-true (zoned-datetime-dtype? '(datetime nanoseconds "UTC")))
  (for ([v (list '(datetime nanoseconds "") '(datetime #f "UTC") '(datetime nanoseconds #f)
                 '(datetime nanoseconds UTC) '(datetime nanoseconds "UTC" x))])
    (check-false (zoned-datetime-dtype? v))))
