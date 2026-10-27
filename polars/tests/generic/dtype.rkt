#lang racket/base

(module+ test
  (require rackunit
           syntax/macro-testing
           (only-in polars/private/foreign enum-dtype?)
           (only-in polars/private/generic/dtype define-enum))

  (define-enum log-levels debug info warning error)
  (check-equal? log-levels '(enum debug info warning error))
  (check-true (enum-dtype? log-levels))

  (define-enum sizes small "Very High")
  (check-equal? sizes '(enum small |Very High|))

  (check-exn #rx"duplicate enum category"
             (lambda () (convert-compile-time-error (let () (define-enum twice a b a) twice))))
  (check-exn #rx"duplicate enum category"
             (lambda () (convert-compile-time-error (let () (define-enum twice a "a") twice))))
  (check-exn #rx"expected more terms"
             (lambda () (convert-compile-time-error (let () (define-enum none) none))))
  (check-exn #rx"an enum category cannot contain a NUL character"
             (lambda () (convert-compile-time-error (let () (define-enum held a "b\u0000c") held)))))
