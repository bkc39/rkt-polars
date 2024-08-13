#lang racket/base

(require ffi/unsafe
         ffi/unsafe/alloc
         ffi/unsafe/define
         ffi/unsafe/define/conventions
         racket/runtime-path
         syntax/parse/define
         (for-syntax racket/base racket/syntax))

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

;; heap allocated rust string
(define _rsstring
  (make-ctype
   _pointer
   (lambda (str)
     (error '_rsstring
            "_rsstring should only be used as a result type: ~a"
            str))
   (lambda (ptr)
     (define str
       (cast ptr _pointer _string))
     (register-finalizer ptr string-drop)
     str)))

(define-cpointer-type _Series-ptr)

(define-compat series-drop
  (_fun _Series-ptr -> _void)
  #:wrap (deallocator))

(define-compat series-empty
  (_fun -> _Series-ptr)
  #:wrap (allocator series-drop))

(module+ test
  (define empty-series-ptr
    (series-empty))
  (check-pred Series-ptr? empty-series-ptr)
  (check-pred void? (series-drop empty-series-ptr)))

(define-compat series-name
  (_fun _Series-ptr -> _rsstring))

(define-compat series-rename
  (_fun _Series-ptr _string -> _void))

(module+ test
  (check-equal? (series-name (series-empty)) "")
  (check-equal?
   (let ([s (series-empty)])
     (series-rename s "hello")
     (series-name s))
   "hello"))

(define-compat series-len
  (_fun _Series-ptr -> _size))

(module+ test
  (check-equal? (series-len (series-empty)) 0))

(define-syntax-parse-rule (define-series-constructor rs-type:id ctype:id)
  #:with constructor-name (format-id #'rs-type "series-new-~a" #'rs-type)
  (define-compat constructor-name
    (_fun _string
          (v : (_list i ctype))
          (_size = (length v))
          -> _Series-ptr)))

(define-series-constructor i32 _int32)

(module+ test
  (check-pred Series-ptr? (series-new-i32 "" '(1 2 3)))
  (check-equal?
   (series-len (series-new-i32 "series" '(0 1)))
   2)
  (check-exn
   #rx"argument is not non-null"
   (lambda ()
     (series-new-i32 "example" '()))))

(define-compat series-new-f64
  (_fun _string
        (v : (_list i _double))
        (_size = (length v))
        -> _Series-ptr))

(module+ test
  (check-pred Series-ptr? (series-new-f64 "" '(1.1 2.17)))
  (check-equal?
   (series-len (series-new-f64 "series" '(0.0 1.2)))
   2)
  (check-exn
   #rx"argument is not non-null"
   (lambda ()
     (series-new-f64 "example" '())))
  (check-exn
   #rx"given value does not fit primitive C type"
   (λ ()
     (series-new-f64 "no-name" '(0)))))

(define-compat series-new-str
  (_fun _string
        (v : (_list i _string))
        (_size = (length v))
        -> _Series-ptr))

(module+ test
  (check-pred Series-ptr? (series-new-str "" '("foo" "bar" "baz" "")))
  (check-equal?
   (series-len (series-new-str "str" '("" "")))
   2)
  (check-exn
   #rx"argument is not non-null"
   (lambda ()
     (series-new-str "example" '())))
  (check-exn
   #rx"contract violation"
   (λ ()
     (series-new-str "" '(symbol)))))

;; Year, Month, Day, Hour, Minute, Second
(define-cstruct _YMDHMS
  ([year _int]
   [month _uint32]
   [day _uint32]
   [hour _uint32]
   [minute _uint32]
   [sescond _uint32]))

(module+ test
  (check-pred YMDHMS?
              (make-YMDHMS 2014 7 11 12 0 0)))

(define-compat series-new-ymdhms
  (_fun _string
        (v : (_list i _YMDHMS))
        (_size = (length v))
        -> _Series-ptr))

(module+ test
  (check-pred Series-ptr?
              (series-new-ymdhms "" (list (make-YMDHMS 2010 1 1 0 0 0))))
  (check-equal?
   (series-len (series-new-ymdhms "name" (list (make-YMDHMS 2010 1 1 0 0 0)
                                               (make-YMDHMS 2011 1 1 0 0 0)
                                               (make-YMDHMS 2012 1 1 0 0 0))))
   3))

(define-cpointer-type _DataFrame-ptr)

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
  (check-pred DataFrame-ptr? (dataframe-make))
  (check-pred void? (dataframe-drop (dataframe-make)))

  (define-values (r c)
    (dataframe-shape (dataframe-make)))
  (check-equal? r 0)
  (check-equal? c 0))
