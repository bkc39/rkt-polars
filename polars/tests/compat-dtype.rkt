#lang racket/base

(module+ test
  (require rackunit
           (only-in polars/private/compat-dtype
                    ->compat-dtype dtype-aliases dtype-short-names dtype-spec? enum-dtype?
                    normalize-dtype zoned-datetime-dtype?))

  (check-true (enum-dtype? '(enum)))
  (check-false (enum-dtype? '(enum a . b)))
  (check-exn #rx"^->compat-dtype: unsupported cast target '\\(datetime microseconds \"UTC\"\\)"
             (lambda () (->compat-dtype '(datetime microseconds "UTC"))))
  (check-true (zoned-datetime-dtype? '(datetime nanoseconds "UTC")))
  (for ([v (list '(datetime nanoseconds "") '(datetime #f "UTC") '(datetime nanoseconds #f)
                 '(datetime nanoseconds UTC) '(datetime nanoseconds "UTC" x))])
    (check-false (zoned-datetime-dtype? v)))

  (for ([(short canonical) (in-hash dtype-short-names)])
    (check-equal? (hash-ref dtype-aliases short) canonical)
    (check-equal? (hash-ref dtype-aliases canonical) canonical)
    (check-equal? (normalize-dtype short) canonical)
    (check-equal? (normalize-dtype canonical) canonical))
  (for ([canonical (in-list '(date time datetime categorical null))])
    (check-equal? (normalize-dtype canonical) canonical))
  (for ([spec (in-list '((datetime nanoseconds) (datetime microseconds #f) (duration milliseconds)
                         (datetime milliseconds "Europe/Brussels") (enum a b) (enum)))])
    (check-true (dtype-spec? spec))
    (check-equal? (normalize-dtype spec) spec))
  (for ([v (in-list '(f65 binary (list int32) (duration days) (datetime microseconds "")
                      (enum a a) "int32"))])
    (check-false (dtype-spec? v)))
  (check-exn #rx"^series: unsupported dtype 'f65$" (lambda () (normalize-dtype 'f65))))
