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

(define-compat string-drop
  (_fun _pointer -> _void)
  #:wrap (deallocator))

(define _rsstring
  (make-ctype
   _pointer
   (lambda (str)
     (cast str _string _pointer))
   (lambda (ptr)
     (define str
       (cast ptr _pointer _string))
     (register-finalizer ptr string-drop)
     str)))

(define _Series-ptr
  (_cpointer 'Series))

(define-compat series-drop
  (_fun _Series-ptr -> _void)
  #:wrap (deallocator))

(define-compat series-empty
  (_fun -> _Series-ptr)
  #:wrap (allocator series-drop))

(module+ test
  (define empty-series-ptr
    (series-empty))
  (check-pred cpointer? empty-series-ptr)
  (check-pred void? (series-drop empty-series-ptr)))

(define-compat series-name
  (_fun _Series-ptr -> _rsstring))

(define-compat series-rename
  (_fun _Series-ptr _rsstring -> _void))

(module+ test
  (check-equal? (series-name (series-empty)) "")
  ;; (check-pred void? (string-drop (series-name (series-empty))))
  (check-equal?
   (let ([s (series-empty)])
     (series-rename s "hello")
     (series-name s))
   "hello"))

(define _DataFrame-ptr
  (_cpointer 'DataFrame))

(define-compat dataframe-drop
  (_fun _DataFrame-ptr -> _void)
  #:wrap (deallocator))

(define-compat dataframe-make
  (_fun -> _DataFrame-ptr)
  #:wrap (allocator dataframe-drop))

(define-cstruct _Shape
  ([rows _size]
   [cols _size]))

(define-compat dataframe-shape
  (_fun _DataFrame-ptr
        -> (s : _Shape)
        -> (values (Shape-rows s) (Shape-cols s))))

(module+ test
  (check-pred void? (dataframe-drop (dataframe-make)))

  (define-values (r c)
    (dataframe-shape (dataframe-make)))
  (check-equal? r 0)
  (check-equal? c 0))
