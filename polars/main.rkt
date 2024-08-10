#lang racket/base

(require ffi/unsafe
         ffi/unsafe/define
         racket/runtime-path
         (for-syntax racket/base))

(provide (all-defined-out))

(module+ test
  (require rackunit))

(define-runtime-path libcompat
  '(so "libcompat"))

(define-ffi-definer define-compat
  (ffi-lib libcompat))

;; (define-compat add
;;   (_fun _uint32 _uint32 -> _uint32))

(define-compat hello-world
  (_fun -> _void)
  #:c-id hello_world)

;; (module+ test
;;   (check-equal? (add 770 7) 777))

;; (module+ main
;;   (printf "~a + ~a = ~a~n"
;;           1700 29 (add 1700 29)))
