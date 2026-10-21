#lang racket/base

(require (only-in racket/contract/base and/c flat-named-contract not/c unsupplied-arg?)
         (only-in racket/list check-duplicates)
         (only-in polars/private/c-integer
                  int64/c positive-size/c size-max size/c uint32/c))

(provide c-string/c column-index/c column-name/c distinct-names? distinct? given positive-size/c
         row-index/c size-max size/c)

(define row-index/c (flat-named-contract 'row-index/c uint32/c))

(define column-index/c (flat-named-contract 'column-index/c int64/c))

(define nul-free? (and/c string? (not/c #rx"\0")))

(define c-string/c (flat-named-contract 'c-string/c nul-free?))

(define column-name/c (flat-named-contract 'column-name/c nul-free?))

(define (distinct? vs)
  (not (check-duplicates vs)))

(define (distinct-names? pairs)
  (distinct? (map car pairs)))

(define (given v default)
  (if (unsupplied-arg? v) default v))

(module+ test
  (require rackunit
           (only-in racket/contract/base contract-name))

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
                '(size/c positive-size/c row-index/c column-index/c column-name/c c-string/c)))
