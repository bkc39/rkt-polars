#lang racket/base

(require ffi/unsafe
         ffi/unsafe/define
         ffi/unsafe/define/conventions)

(module+ test
  (require rackunit))

(define libcompat
  (ffi-lib "libcompat"))

(define-ffi-definer define-compat
  libcompat)

(define-compat add
  (_fun _uint32 _uint32 -> _uint32))

(define _DataFrame-ptr (_cpointer 'DataFrame))

;; (define-compat make-data_frame
;;   (_fun -> _DataFrame-ptr)
;;   #:c-id make_data_frame)

(define-compat dataframe-to-string
  (_fun _DataFrame-ptr -> _string)
  #:c-id dataframe_to_string)

(module+ test
  (check-equal? (add 770 7) 777))

(module+ main
  (printf "~a + ~a = ~a~n"
          1700 29 (add 1700 29)))
