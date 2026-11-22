#lang racket/base

(module+ test
  (require rackunit
           (only-in racket/contract/base flat-contract-predicate)
           (only-in polars/private/compat-dtype dtype-short-names)
           (only-in polars/private/dtype-spelling
                    cast-target/c dtype-aliases dtype-spec? normalize-dtype))

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
                      (datetime microseconds "a\u0000b") (enum a a) "int32"))])
    (check-false (dtype-spec? v)))
  (check-exn #rx"^normalize-dtype: unsupported dtype 'f65$" (lambda () (normalize-dtype 'f65)))
  (check-exn #rx"^series: unsupported dtype 'f65$" (lambda () (normalize-dtype 'f65 'series)))
  (define cast-target? (flat-contract-predicate cast-target/c))
  (for ([dtype (in-list '(f64 float64 i32 str bool binary null duration date time categorical
                          datetime (datetime milliseconds) (datetime microseconds #f)
                          (duration nanoseconds) (enum a b) (datetime microseconds "Nope/Zone")))])
    (check-true (cast-target? dtype) (format "~s" dtype)))
  (for ([dtype (in-list '(f65 float decimal (decimal 10 2) (list int32) (enum a a) "f64"
                          (datetime microseconds todo-timezone) nope (duration milliseconds "UTC")
                          (duration ms x y z) (datetime microseconds "a\u0000b")))])
    (check-false (cast-target? dtype) (format "~s" dtype))))
