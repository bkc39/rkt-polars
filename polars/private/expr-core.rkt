#lang racket/base

;; Shared Expr / LazyFrame FFI plumbing and scalar leaves.

(require ffi/unsafe
         ffi/unsafe/alloc
         ffi/unsafe/define
         ffi/unsafe/define/conventions
         racket/runtime-path)

(provide define-compat
         _Expr-ptr Expr-ptr?
         _LazyFrame-ptr LazyFrame-ptr?
         expr-drop lazyframe-drop
         expr-col expr-lit-i32 expr-lit-i64 expr-lit-f64 expr-lit-bool expr-lit-str
         expr-alias
         lit col ->expr)

(define-runtime-path expr-native-libs-dir "../native-libs")

(define-ffi-definer define-compat
  (ffi-lib (build-path expr-native-libs-dir "libcompat"))
  #:make-c-id convention:hyphen->underscore)

(define-cpointer-type _Expr-ptr)
(define-cpointer-type _LazyFrame-ptr)

(define-compat expr-drop
  (_fun _Expr-ptr -> _void)
  #:wrap (deallocator))

(define-compat lazyframe-drop
  (_fun _LazyFrame-ptr -> _void)
  #:wrap (deallocator))

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
