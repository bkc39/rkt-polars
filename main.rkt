#lang racket/base

(require ffi/unsafe
         ffi/unsafe/define)

(module+ test
  (require rackunit))

(define-ffi-definer define-compat
  (ffi-lib "libcompat.so"))

(define-compat add
  (_fun _uint32 _uint32 -> _uint32))

(module+ test
  (check-equal? (add 770 7) 777))

(module+ main
  (printf "~a + ~a = ~a~n"
          1700 29 (add 1700 29)))
