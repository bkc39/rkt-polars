#lang racket/base

(require ffi/unsafe
         ffi/unsafe/alloc
         ffi/unsafe/define
         ffi/unsafe/define/conventions
         racket/runtime-path
         (for-syntax racket/base))

(module+ test
  (require rackunit))

(provide (all-defined-out))

(define-runtime-path libcompat
  '(so "libcompat"))

(define-ffi-definer define-compat
  (ffi-lib libcompat)
  #:make-c-id convention:hyphen->underscore)

(define _Series-ptr
  (_cpointer 'Series))

(define-compat free-series
  (_fun _Series-ptr -> _void)
  #:wrap (deallocator))

(define-compat empty-series
  (_fun -> _Series-ptr)
  #:wrap (allocator free-series))

(module+ test
  (define empty-series-ptr
    (empty-series))
  (check-pred cpointer? empty-series-ptr)
  (check-pred void? (free-series empty-series-ptr)))

(define-compat series-name
  (_fun _Series-ptr -> _string))

(define-compat series-rename
  (_fun _Series-ptr _string -> _void))

(module+ test
  (check-equal? (series-name (empty-series)) "")
  (check-equal?
   (let ([s (empty-series)])
     (series-rename s "hello")
     (series-name s))
   "hello"))

(define _DataFrame-ptr
  (_cpointer 'DataFrame))

(define-compat free-dataframe
  (_fun _DataFrame-ptr -> _void)
  #:wrap (deallocator))

(define-compat make-dataframe
  (_fun -> _DataFrame-ptr)
  #:wrap (allocator free-dataframe))

(define-cstruct _Shape
  ([rows _size]
   [cols _size]))

(define-compat get-shape
  (_fun _DataFrame-ptr
        -> (s : _Shape)
        -> (values (Shape-rows s) (Shape-cols s))))

(module+ test
  (check-pred void? (free-dataframe (make-dataframe)))

  (define-values (r c)
    (get-shape (make-dataframe)))
  (check-equal? r 0)
  (check-equal? c 0))
