#lang racket/base

(require (only-in racket/contract/base and/c flat-named-contract integer-in not/c))

(provide column-name/c positive-size/c size/c)

(define size-max (sub1 (expt 2 64)))

(define size/c (flat-named-contract 'size/c (integer-in 0 size-max)))

(define positive-size/c (flat-named-contract 'positive-size/c (integer-in 1 size-max)))

(define column-name/c (flat-named-contract 'column-name/c (and/c string? (not/c #rx"\0"))))

(module+ test
  (require rackunit
           (only-in racket/contract/base contract-name))

  (check-true (size/c 0))
  (check-true (size/c (sub1 (expt 2 64))))
  (check-false (size/c (expt 2 64)))
  (check-false (size/c -1))
  (check-false (positive-size/c 0))
  (check-true (positive-size/c (sub1 (expt 2 64))))
  (check-false (positive-size/c (expt 2 64)))
  (check-true (column-name/c ""))
  (check-true (column-name/c "a b"))
  (check-false (column-name/c "a\u0000b"))
  (check-false (column-name/c 'a))
  (check-equal? (map contract-name (list size/c positive-size/c column-name/c))
                '(size/c positive-size/c column-name/c)))
