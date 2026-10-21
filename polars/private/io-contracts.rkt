#lang racket/base

(require (only-in racket/contract/base
                  and/c flat-named-contract integer-in not/c unsupplied-arg?)
         (only-in racket/list check-duplicates))

(provide c-string/c column-index/c column-name/c distinct-names? distinct? given int64/c
         nonnegative-int64/c positive-size/c row-index/c size-max size/c)

(define size-max (sub1 (expt 2 64)))

(define size/c (flat-named-contract 'size/c (integer-in 0 size-max)))

(define positive-size/c (flat-named-contract 'positive-size/c (integer-in 1 size-max)))

(define row-index/c (flat-named-contract 'row-index/c (integer-in 0 (sub1 (expt 2 32)))))

(define int64-min (- (expt 2 63)))

(define int64-max (sub1 (expt 2 63)))

(define int64/c (flat-named-contract 'int64/c (integer-in int64-min int64-max)))

(define nonnegative-int64/c (flat-named-contract 'nonnegative-int64/c (integer-in 0 int64-max)))

(define column-index/c (flat-named-contract 'column-index/c (integer-in int64-min int64-max)))

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

  (check-true (size/c 0))
  (check-true (size/c size-max))
  (check-false (size/c (add1 size-max)))
  (check-false (size/c -1))
  (check-false (positive-size/c 0))
  (check-true (positive-size/c size-max))
  (check-false (positive-size/c (add1 size-max)))
  (check-true (row-index/c 0))
  (check-true (row-index/c (sub1 (expt 2 32))))
  (check-true (int64/c (- (expt 2 63))))
  (check-false (int64/c (expt 2 63)))
  (check-true (nonnegative-int64/c 0))
  (check-true (nonnegative-int64/c (sub1 (expt 2 63))))
  (check-false (nonnegative-int64/c -1))
  (check-false (nonnegative-int64/c (expt 2 63)))
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
                           c-string/c int64/c nonnegative-int64/c))
                '(size/c positive-size/c row-index/c column-index/c column-name/c c-string/c
                         int64/c nonnegative-int64/c)))
