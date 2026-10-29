#lang racket/base

(require (only-in ffi/unsafe _size ctype-sizeof)
         (only-in racket/contract/base integer-in))

(provide int16/c int32/c int64/c int64-max int64-min int8/c nonnegative-int64/c positive-size/c
         size-max size/c
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
(define int8/c (integer-in (- (arithmetic-shift 1 7)) (unsigned-max 7)))
(define int16/c (integer-in (- (arithmetic-shift 1 15)) (unsigned-max 15)))
(define int32/c (integer-in (- (arithmetic-shift 1 31)) (unsigned-max 31)))
(define int64/c (integer-in int64-min int64-max))
(define nonnegative-int64/c (integer-in 0 int64-max))
(define size/c (integer-in 0 size-max))
(define positive-size/c (integer-in 1 size-max))
