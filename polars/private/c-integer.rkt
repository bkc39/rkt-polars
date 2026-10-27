#lang racket/base

(require (only-in ffi/unsafe _size ctype-sizeof)
         (only-in racket/contract/base integer-in))

(provide int32/c int64/c int64-max int64-min nonnegative-int64/c positive-size/c size-max size/c
         uint16-max uint16/c uint32-max uint32/c uint64-max uint64/c uint8/c)

(define (unsigned-max bits)
  (sub1 (arithmetic-shift 1 bits)))

(define int64-min (- (arithmetic-shift 1 63)))
(define int64-max (unsigned-max 63))
(define uint16-max (unsigned-max 16))
(define uint32-max (unsigned-max 32))
(define uint64-max (unsigned-max 64))
(define size-max (unsigned-max (* 8 (ctype-sizeof _size))))

(define uint8/c (integer-in 0 (unsigned-max 8)))
(define uint16/c (integer-in 0 uint16-max))
(define uint32/c (integer-in 0 uint32-max))
(define uint64/c (integer-in 0 uint64-max))
(define int32/c (integer-in (- (arithmetic-shift 1 31)) (unsigned-max 31)))
(define int64/c (integer-in int64-min int64-max))
(define nonnegative-int64/c (integer-in 0 int64-max))
(define size/c (integer-in 0 size-max))
(define positive-size/c (integer-in 1 size-max))

(module+ test
  (require rackunit
           (only-in racket/contract/base contract-name)
           (only-in racket/match match-define))

  (for ([row (in-list `((uint8/c ,uint8/c 0 255)
                        (uint16/c ,uint16/c 0 65535)
                        (uint32/c ,uint32/c 0 ,(sub1 (expt 2 32)))
                        (uint64/c ,uint64/c 0 ,(sub1 (expt 2 64)))
                        (int32/c ,int32/c ,(- (expt 2 31)) ,(sub1 (expt 2 31)))
                        (int64/c ,int64/c ,(- (expt 2 63)) ,(sub1 (expt 2 63)))
                        (nonnegative-int64/c ,nonnegative-int64/c 0 ,(sub1 (expt 2 63)))
                        (size/c ,size/c 0 ,(sub1 (expt 2 64)))
                        (positive-size/c ,positive-size/c 1 ,(sub1 (expt 2 64)))))])
    (match-define (list name c lo hi) row)
    (check-equal? (contract-name c) `(integer-in ,lo ,hi) (format "~a names its range" name))
    (check-true (c lo) (format "~a admits ~a" name lo))
    (check-true (c hi) (format "~a admits ~a" name hi))
    (check-false (c (sub1 lo)) (format "~a refuses ~a" name (sub1 lo)))
    (check-false (c (add1 hi)) (format "~a refuses ~a" name (add1 hi)))
    (check-false (c 1.0) (format "~a refuses 1.0" name)))
  (check-equal? (list int64-min int64-max uint16-max uint32-max uint64-max size-max)
                (list (- (expt 2 63)) (sub1 (expt 2 63)) 65535 (sub1 (expt 2 32))
                      (sub1 (expt 2 64)) (sub1 (expt 2 64)))))
