#lang racket/base

(require (only-in ffi/unsafe _size ctype-sizeof)
         (only-in racket/contract/base integer-in))

(provide c-int32/c c-int64/c c-size/c c-uint8/c c-uint32/c c-uint64/c)

(define (unsigned/c bits)
  (integer-in 0 (sub1 (arithmetic-shift 1 bits))))

(define (signed/c bits)
  (integer-in (- (arithmetic-shift 1 (sub1 bits))) (sub1 (arithmetic-shift 1 (sub1 bits)))))

(define c-uint8/c (unsigned/c 8))
(define c-uint32/c (unsigned/c 32))
(define c-uint64/c (unsigned/c 64))
(define c-int32/c (signed/c 32))
(define c-int64/c (signed/c 64))
(define c-size/c (unsigned/c (* 8 (ctype-sizeof _size))))

(module+ test
  (require rackunit)

  (for ([c (list c-uint8/c c-uint32/c c-uint64/c c-int32/c c-int64/c c-size/c)]
        [lo (list 0 0 0 (- (expt 2 31)) (- (expt 2 63)) 0)]
        [hi (list 255 (sub1 (expt 2 32)) (sub1 (expt 2 64)) (sub1 (expt 2 31)) (sub1 (expt 2 63))
                  (sub1 (expt 2 64)))])
    (check-true (c lo))
    (check-true (c hi))
    (check-false (c (sub1 lo)))
    (check-false (c (add1 hi)))
    (check-false (c 1.0))))
