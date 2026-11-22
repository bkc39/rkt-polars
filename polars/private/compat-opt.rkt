#lang racket/base

(require ffi/unsafe
         (only-in gregor date)
         syntax/parse/define
         (for-syntax racket/base racket/syntax))

(provide (except-out (all-defined-out) define-compat-opt))

(struct polars-null-sentinel ()
  #:property prop:custom-write
  (lambda (_ out mode)
    (write-string "polars-null" out)))

(define polars-null (polars-null-sentinel))

(define (polars-null? v)
  (eq? v polars-null))

(define-syntax-parse-rule (define-compat-opt suffix:id value-type:expr
                            (~optional (~seq #:datum ->datum:expr)))
  #:with struct-type (format-id #'suffix "_CompatOpt~a" #'suffix)
  #:with valid-of (format-id #'suffix "CompatOpt~a-valid" #'suffix)
  #:with value-of (format-id #'suffix "CompatOpt~a-value" #'suffix)
  #:with converter
  (format-id #'suffix "compat-opt-~a->datum" (string-downcase (symbol->string (syntax-e #'suffix))))
  (begin
    (define-cstruct struct-type
      ([valid _int32]
       [value value-type]))
    (define (converter o)
      (and (not (zero? (valid-of o)))
           (~? (->datum (value-of o)) (value-of o))))))

(define-cstruct _YMD
  ([ymd-year _int32]
   [ymd-month _uint32]
   [ymd-day _uint32]))

(define (ymd->date value)
  (date (YMD-ymd-year value)
        (YMD-ymd-month value)
        (YMD-ymd-day value)))

(define-compat-opt I32 _int32)
(define-compat-opt I8 _int8)
(define-compat-opt I16 _int16)
(define-compat-opt F64 _double)
(define-compat-opt F32 _float)
(define-compat-opt I64 _int64)
(define-compat-opt U8 _uint8)
(define-compat-opt U16 _uint16)
(define-compat-opt U32 _uint32)
(define-compat-opt U64 _uint64)
(define-compat-opt Bool _int32 #:datum (lambda (v) (not (zero? v))))
(define-compat-opt YMD _YMD #:datum ymd->date)
