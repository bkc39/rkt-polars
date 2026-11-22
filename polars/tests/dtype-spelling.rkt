#lang racket/base

(module+ test
  (require rackunit
           (only-in polars/private/compat-dtype dtype-short-names)
           (only-in polars/private/dtype-spelling dtype-aliases dtype-spec? normalize-dtype))

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
  (check-exn #rx"^normalize-dtype: unsupported dtype 'f65$" (lambda () (normalize-dtype 'f65)))
  (check-exn #rx"^series: unsupported dtype 'f65$" (lambda () (normalize-dtype 'f65 'series))))
