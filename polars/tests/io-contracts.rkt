#lang racket/base

(module+ test
  (require rackunit
           (only-in racket/contract/base contract-name)
           polars/private/io-contracts)

  (check-true (row-index/c 0))
  (check-true (row-index/c (sub1 (expt 2 32))))
  (check-false (row-index/c (expt 2 32)))
  (check-false (row-index/c -1))
  (check-true (column-index/c (- (expt 2 63))))
  (check-true (column-index/c (sub1 (expt 2 63))))
  (check-false (column-index/c (expt 2 63)))
  (check-false (column-index/c (sub1 (- (expt 2 63)))))
  (for ([string/c (list column-name/c c-string/c)])
    (check-true (string/c ""))
    (check-true (string/c "a b"))
    (check-false (string/c "a\u0000b"))
    (check-false (string/c 'a)))
  (check-true (distinct? '(1 2 3)))
  (check-false (distinct? '("a" "b" "a")))
  (check-true (distinct-names? '(("a" . 1) ("b" . 1))))
  (check-false (distinct-names? '(("a" . 1) ("a" . 2))))
  (check-equal? (given 3 0) 3)
  (check-equal? (given #f 0) #f)
  (check-equal? (map contract-name
                     (list size/c positive-size/c row-index/c column-index/c column-name/c
                           c-string/c))
                `((integer-in 0 ,size-max) (integer-in 1 ,size-max) (integer-in 0 ,(sub1 (expt 2 32)))
                  (integer-in ,(- (expt 2 63)) ,(sub1 (expt 2 63))) column-name/c c-string/c)))
