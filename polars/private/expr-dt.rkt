#lang racket/base

;; Expr datetime namespace wrappers.

(require ffi/unsafe
         ffi/unsafe/alloc
         polars/private/expr-core
         (only-in polars/private/foreign call/foreign-error replace-zone-failure))

(provide expr-dt-year expr-dt-month expr-dt-day
         expr-dt-hour expr-dt-minute expr-dt-second
         expr-dt-iso-year expr-dt-quarter expr-dt-week
         expr-dt-weekday expr-dt-ordinal-day expr-dt-is-leap-year
         expr-dt-date expr-dt-time
         expr-dt-millisecond expr-dt-microsecond expr-dt-nanosecond
         expr-dt-timestamp expr-dt-strftime expr-dt-truncate
         expr-dt-convert-time-zone expr-dt-replace-time-zone)

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

(define-compat expr-dt-iso-year
  (_fun _Expr-ptr -> _Expr-ptr)
  #:c-id expr_dt_iso_year
  #:wrap (allocator expr-drop))

(define-compat expr-dt-quarter
  (_fun _Expr-ptr -> _Expr-ptr)
  #:c-id expr_dt_quarter
  #:wrap (allocator expr-drop))

(define-compat expr-dt-week
  (_fun _Expr-ptr -> _Expr-ptr)
  #:c-id expr_dt_week
  #:wrap (allocator expr-drop))

(define-compat expr-dt-weekday
  (_fun _Expr-ptr -> _Expr-ptr)
  #:c-id expr_dt_weekday
  #:wrap (allocator expr-drop))

(define-compat expr-dt-ordinal-day
  (_fun _Expr-ptr -> _Expr-ptr)
  #:c-id expr_dt_ordinal_day
  #:wrap (allocator expr-drop))

(define-compat expr-dt-is-leap-year
  (_fun _Expr-ptr -> _Expr-ptr)
  #:c-id expr_dt_is_leap_year
  #:wrap (allocator expr-drop))

(define-compat expr-dt-date
  (_fun _Expr-ptr -> _Expr-ptr)
  #:c-id expr_dt_date
  #:wrap (allocator expr-drop))

(define-compat expr-dt-time
  (_fun _Expr-ptr -> _Expr-ptr)
  #:c-id expr_dt_time
  #:wrap (allocator expr-drop))

(define-compat expr-dt-millisecond
  (_fun _Expr-ptr -> _Expr-ptr)
  #:c-id expr_dt_millisecond
  #:wrap (allocator expr-drop))

(define-compat expr-dt-microsecond
  (_fun _Expr-ptr -> _Expr-ptr)
  #:c-id expr_dt_microsecond
  #:wrap (allocator expr-drop))

(define-compat expr-dt-nanosecond
  (_fun _Expr-ptr -> _Expr-ptr)
  #:c-id expr_dt_nanosecond
  #:wrap (allocator expr-drop))

(define compat-time-unit/nanoseconds 1)
(define compat-time-unit/microseconds 2)
(define compat-time-unit/milliseconds 3)

(define (time-unit-symbol->code who unit)
  (case unit
    [(nanoseconds) compat-time-unit/nanoseconds]
    [(microseconds) compat-time-unit/microseconds]
    [(milliseconds) compat-time-unit/milliseconds]
    [else (error who
                 "unknown time unit ~v (expected 'nanoseconds, 'microseconds, or 'milliseconds)"
                 unit)]))

(define-compat expr-dt-timestamp/raw
  (_fun _Expr-ptr _int32 -> _Expr-ptr)
  #:c-id expr_dt_timestamp
  #:wrap (allocator expr-drop))

(define (expr-dt-timestamp e #:unit [unit 'microseconds])
  (expr-dt-timestamp/raw e (time-unit-symbol->code 'expr-dt-timestamp unit)))

(define-compat expr-dt-strftime
  (_fun _Expr-ptr _string -> _Expr-ptr)
  #:c-id expr_dt_strftime
  #:wrap (allocator expr-drop))

(define-compat expr-dt-truncate/raw
  (_fun _Expr-ptr _Expr-ptr -> _Expr-ptr)
  #:c-id expr_dt_truncate
  #:wrap (allocator expr-drop))

(define (expr-dt-truncate e every)
  (expr-dt-truncate/raw e (->expr every)))

(define-compat expr-dt-convert-time-zone/raw
  (_fun _Expr-ptr _string/utf-8 -> _Expr-ptr/null)
  #:c-id expr_dt_convert_time_zone
  #:wrap (allocator expr-drop))

(define (expr-dt-convert-time-zone e zone #:who [who 'expr-dt-convert-time-zone])
  (call/foreign-error who
                      (lambda () (expr-dt-convert-time-zone/raw e zone))
                      "cannot convert to the time zone ~s" zone))

(define-compat expr-dt-replace-time-zone/raw
  (_fun _Expr-ptr _string/utf-8 _string/utf-8 _string/utf-8 -> _Expr-ptr/null)
  #:c-id expr_dt_replace_time_zone
  #:wrap (allocator expr-drop))

(define (expr-dt-replace-time-zone e zone
                                   #:ambiguous [ambiguous 'raise]
                                   #:non-existent [non-existent 'raise]
                                   #:who [who 'expr-dt-replace-time-zone])
  (call/foreign-error who
                      (lambda ()
                        (expr-dt-replace-time-zone/raw e zone (symbol->string ambiguous)
                                                       (symbol->string non-existent)))
                      "~a" (replace-zone-failure zone)))
