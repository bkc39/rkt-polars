#lang racket/base

;; Shared Expr / LazyFrame FFI plumbing and scalar leaves.

(require ffi/unsafe
         ffi/unsafe/alloc
         ffi/unsafe/define
         ffi/unsafe/define/conventions
         racket/runtime-path
         (only-in polars/private/foreign _rsstring)
         (only-in racket/contract/base contract-out [-> ->/c]))

(provide (contract-out [expr->string (->/c Expr-ptr? string?)])
         define-compat
         _Expr-ptr _Expr-ptr/null Expr-ptr?
         _LazyFrame-ptr _LazyFrame-ptr/null LazyFrame-ptr?
         expr-drop lazyframe-drop
         expr-col expr-lit-i32 expr-lit-i64 expr-lit-f64 expr-lit-bool expr-lit-str
         expr-alias
         lit col ->expr)

(define-runtime-path expr-native-libs-dir "../native-libs")

(define-ffi-definer define-compat
  (ffi-lib (build-path expr-native-libs-dir "libcompat"))
  #:make-c-id convention:hyphen->underscore)

(struct expr ([ptr #:mutable])
  #:property prop:cpointer (lambda (e) (expr-ptr e))
  #:property prop:custom-write
  (lambda (e port mode)
    (write-string (if (expr-ptr e) (expr->string e) "#<expr: dropped>") port)))

(define (wrap-expr p) (and p (expr p)))

(define-cpointer-type _Expr-ptr _pointer #f wrap-expr)
(define-cpointer-type _LazyFrame-ptr)

(define-compat expr-drop/raw
  (_fun _Expr-ptr -> _void)
  #:c-id expr_drop
  #:wrap (deallocator))

(define (expr-drop e)
  (expr-drop/raw e)
  (set-expr-ptr! e #f))

(define-compat expr-drop-count
  (_fun -> _size))

(define-compat lazyframe-drop
  (_fun _LazyFrame-ptr -> _void)
  #:wrap (deallocator))

(define-compat expr->string
  (_fun _Expr-ptr -> _rsstring)
  #:c-id expr_to_string)

(define-compat expr-col
  (_fun _string -> _Expr-ptr)
  #:wrap (allocator expr-drop))

(define-compat expr-lit-i32
  (_fun _int32 -> _Expr-ptr)
  #:wrap (allocator expr-drop))

(define-compat expr-lit-i64
  (_fun _int64 -> _Expr-ptr)
  #:wrap (allocator expr-drop))

(define-compat expr-lit-f64
  (_fun _double -> _Expr-ptr)
  #:wrap (allocator expr-drop))

(define-compat expr-lit-bool/raw
  (_fun _uint8 -> _Expr-ptr)
  #:c-id expr_lit_bool
  #:wrap (allocator expr-drop))

(define (expr-lit-bool b)
  (expr-lit-bool/raw (if b 1 0)))

(define-compat expr-lit-str
  (_fun _string -> _Expr-ptr)
  #:wrap (allocator expr-drop))

(define-compat expr-alias
  (_fun _Expr-ptr _string -> _Expr-ptr)
  #:wrap (allocator expr-drop))

(define (lit v)
  (cond
    [(boolean? v) (expr-lit-bool v)]
    [(exact-integer? v)
     (if (and (>= v -2147483648) (<= v 2147483647))
         (expr-lit-i32 v)
         (expr-lit-i64 v))]
    [(real? v) (expr-lit-f64 (exact->inexact v))]
    [(string? v) (expr-lit-str v)]
    [else (error 'lit "no Expr literal for ~v" v)]))

(define (col name) (expr-col name))

(define (->expr v)
  (if (Expr-ptr? v) v (lit v)))

(module+ test
  (require rackunit)
  (define-compat expr-add
    (_fun _Expr-ptr _Expr-ptr -> _Expr-ptr)
    #:wrap (allocator expr-drop))
  (define-compat expr-mul
    (_fun _Expr-ptr _Expr-ptr -> _Expr-ptr)
    #:wrap (allocator expr-drop))
  (define print-col (col "x"))
  (check-equal? (expr->string print-col) "col(\"x\")")
  (check-equal? (format "~a" print-col) "col(\"x\")")
  (check-equal? (format "~s" print-col) "col(\"x\")")
  (check-equal? (format "~v" print-col) "col(\"x\")")
  (check-equal? (expr->string (expr-add (col "a") (col "b")))
                "[(col(\"a\")) + (col(\"b\"))]")
  (check-equal? (expr->string (expr-alias (col "a") "b")) "col(\"a\").alias(\"b\")")
  (check-equal? (expr->string (expr-mul (col "v") (lit 10))) "[(col(\"v\")) * (dyn int: 10)]")
  (check-equal? (expr->string (lit "hi")) "String(hi)")
  (check-equal? (expr->string (lit #t)) "true")
  (check-pred Expr-ptr? print-col)
  (check-true (cpointer? print-col))
  (check-pred Expr-ptr? (expr-alias print-col "y"))
  (check-false (equal? (col "x") (col "x")))
  (define dropped (col "d"))
  (expr-drop dropped)
  (check-equal? (format "~a" dropped) "#<expr: dropped>")
  (check-exn exn:fail? (lambda () (expr-alias dropped "e")))
  (check-exn exn:fail? (lambda () (expr-drop dropped)))
  (define drop-before (expr-drop-count))
  (for ([_ (in-range 100)])
    (void (expr-alias (col "g") "h")))
  (for ([_ (in-range 10)])
    (collect-garbage)
    (sleep 0.01))
  (check-true (>= (- (expr-drop-count) drop-before) 200)))
