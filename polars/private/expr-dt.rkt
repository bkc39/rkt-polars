#lang racket/base

;; Expr datetime namespace wrappers.

(require ffi/unsafe
         ffi/unsafe/alloc
         polars/private/expr-core)

(provide expr-dt-year expr-dt-month expr-dt-day
         expr-dt-hour expr-dt-minute expr-dt-second)

(define-compat expr-dt-year
  (_fun _Expr-ptr -> _Expr-ptr)
  #:c-id expr_dt_year
  #:wrap (allocator expr-drop))

(define-compat expr-dt-month
  (_fun _Expr-ptr -> _Expr-ptr)
  #:c-id expr_dt_month
  #:wrap (allocator expr-drop))

(define-compat expr-dt-day
  (_fun _Expr-ptr -> _Expr-ptr)
  #:c-id expr_dt_day
  #:wrap (allocator expr-drop))

(define-compat expr-dt-hour
  (_fun _Expr-ptr -> _Expr-ptr)
  #:c-id expr_dt_hour
  #:wrap (allocator expr-drop))

(define-compat expr-dt-minute
  (_fun _Expr-ptr -> _Expr-ptr)
  #:c-id expr_dt_minute
  #:wrap (allocator expr-drop))

(define-compat expr-dt-second
  (_fun _Expr-ptr -> _Expr-ptr)
  #:c-id expr_dt_second
  #:wrap (allocator expr-drop))
