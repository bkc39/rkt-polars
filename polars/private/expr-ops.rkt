#lang racket/base

(require ffi/unsafe
         ffi/unsafe/alloc
         (only-in racket/contract/base [-> ->/c] ->* any/c contract-out or/c)
         (only-in racket/match match-define)
         syntax/parse/define
         (only-in polars/private/c-integer int64/c uint32/c)
         (only-in polars/private/expr-core ->expr/who Expr-ptr? _Expr-ptr _Expr-ptr/null
                  define-compat expr-drop)
         (only-in polars/private/foreign
                  ->compat-dtype _CompatDType _c-string _rsstr _rsstr-list call/foreign-error
                  datetime-zone/c enum-dtype? time-unit-symbol->code zoned-datetime-dtype?)
         (only-in polars/private/resource _str-list)
         (for-syntax racket/base racket/syntax))

(provide expr-meta-output-name expr-meta-output-name/raw expr-meta-output-name/who
         expr-meta-root-names expr-meta-eq?
         expr-add expr-sub expr-mul expr-div expr-mod
         expr-gt expr-lt expr-ge expr-le expr-eq expr-ne
         expr-and expr-or expr-xor
         expr-not expr-neg expr-name-keep expr-is-null expr-is-not-null
         expr-drop-nulls expr-drop-nans
         expr-is-nan expr-is-not-nan expr-is-finite expr-is-infinite
         expr-fill-null expr-fill-nan
         expr-abs expr-sign expr-floor expr-ceil expr-sqrt expr-exp expr-log1p
         expr-log expr-pow expr-clip
         expr-cum-sum expr-cum-prod expr-cum-min expr-cum-max expr-cum-count
         null-behavior/c
         expr-cast-to
         (contract-out
          [expr-forward-fill (->* (Expr-ptr?) (#:limit (or/c #f uint32/c)) Expr-ptr?)]
          [expr-backward-fill (->* (Expr-ptr?) (#:limit (or/c #f uint32/c)) Expr-ptr?)]
          [expr-round (->* (Expr-ptr?) (#:decimals uint32/c) Expr-ptr?)]
          [expr-shift (->* (Expr-ptr?) (#:n int64/c #:fill-value any/c) Expr-ptr?)]
          [expr-diff (->* (Expr-ptr?) (#:n int64/c #:null-behavior null-behavior/c) Expr-ptr?)]
          [expr-cast (->/c Expr-ptr? datetime-zone/c Expr-ptr?)]))

(define-compat expr-meta-output-name/raw
  (_fun _Expr-ptr -> _rsstr)
  #:c-id expr_meta_output_name_v2)

(define (expr-meta-output-name/who who e)
  (call/foreign-error who (lambda () (expr-meta-output-name/raw e))
                      "cannot determine the output name of ~a" e))

(define (expr-meta-output-name e)
  (expr-meta-output-name/who 'expr-meta-output-name e))

(define-compat expr-meta-root-names
  (_fun _Expr-ptr -> _rsstr-list)
  #:c-id expr_meta_root_names)

(define-compat expr-meta-eq/raw
  (_fun _Expr-ptr _Expr-ptr -> _uint8)
  #:c-id expr_meta_eq)

(define (expr-meta-eq? a b) (= 1 (expr-meta-eq/raw a b)))

(define-syntax-parse-rule (define-expr-binop name:id c-id:id)
  #:with raw (format-id #'name "~a/raw" #'name)
  (begin
    (define-compat raw
      (_fun _Expr-ptr _Expr-ptr -> _Expr-ptr)
      #:c-id c-id
      #:wrap (allocator expr-drop))
    (define (name a b) (raw (->expr/who 'name a) (->expr/who 'name b)))))

(define-expr-binop expr-add expr_add)
(define-expr-binop expr-sub expr_sub)
(define-expr-binop expr-mul expr_mul)
(define-expr-binop expr-div expr_div)
(define-expr-binop expr-mod expr_mod)
(define-expr-binop expr-gt expr_gt)
(define-expr-binop expr-lt expr_lt)
(define-expr-binop expr-ge expr_ge)
(define-expr-binop expr-le expr_le)
(define-expr-binop expr-eq expr_eq)
(define-expr-binop expr-ne expr_ne)
(define-expr-binop expr-and expr_and)
(define-expr-binop expr-or expr_or)
(define-expr-binop expr-xor expr_xor)

(define-compat expr-not
  (_fun _Expr-ptr -> _Expr-ptr)
  #:wrap (allocator expr-drop))

(define-compat expr-neg
  (_fun _Expr-ptr -> _Expr-ptr)
  #:wrap (allocator expr-drop))

(define-compat expr-name-keep
  (_fun _Expr-ptr -> _Expr-ptr)
  #:c-id expr_name_keep
  #:wrap (allocator expr-drop))

(define-compat expr-is-null
  (_fun _Expr-ptr -> _Expr-ptr)
  #:wrap (allocator expr-drop))

(define-compat expr-is-not-null
  (_fun _Expr-ptr -> _Expr-ptr)
  #:wrap (allocator expr-drop))

(define-compat expr-drop-nulls
  (_fun _Expr-ptr -> _Expr-ptr)
  #:wrap (allocator expr-drop))

(define-compat expr-drop-nans
  (_fun _Expr-ptr -> _Expr-ptr)
  #:wrap (allocator expr-drop))

(define-compat expr-is-nan
  (_fun _Expr-ptr -> _Expr-ptr)
  #:wrap (allocator expr-drop))

(define-compat expr-is-not-nan
  (_fun _Expr-ptr -> _Expr-ptr)
  #:wrap (allocator expr-drop))

(define-compat expr-is-finite
  (_fun _Expr-ptr -> _Expr-ptr)
  #:wrap (allocator expr-drop))

(define-compat expr-is-infinite
  (_fun _Expr-ptr -> _Expr-ptr)
  #:wrap (allocator expr-drop))

(define-compat expr-fill-null/raw
  (_fun _Expr-ptr _Expr-ptr -> _Expr-ptr)
  #:c-id expr_fill_null
  #:wrap (allocator expr-drop))

(define (expr-fill-null e value) (expr-fill-null/raw e (->expr/who 'expr-fill-null value)))

(define-compat expr-fill-nan/raw
  (_fun _Expr-ptr _Expr-ptr -> _Expr-ptr)
  #:c-id expr_fill_nan
  #:wrap (allocator expr-drop))

(define (expr-fill-nan e value) (expr-fill-nan/raw e (->expr/who 'expr-fill-nan value)))

(define-compat expr-forward-fill/raw
  (_fun _Expr-ptr _uint8 _uint32 -> _Expr-ptr)
  #:c-id expr_forward_fill
  #:wrap (allocator expr-drop))

(define-compat expr-backward-fill/raw
  (_fun _Expr-ptr _uint8 _uint32 -> _Expr-ptr)
  #:c-id expr_backward_fill
  #:wrap (allocator expr-drop))

(define (expr-forward-fill e #:limit [limit #f])
  (expr-forward-fill/raw e (if limit 1 0) (or limit 0)))

(define (expr-backward-fill e #:limit [limit #f])
  (expr-backward-fill/raw e (if limit 1 0) (or limit 0)))

(define-compat expr-abs (_fun _Expr-ptr -> _Expr-ptr) #:wrap (allocator expr-drop))
(define-compat expr-sign (_fun _Expr-ptr -> _Expr-ptr) #:wrap (allocator expr-drop))
(define-compat expr-floor (_fun _Expr-ptr -> _Expr-ptr) #:wrap (allocator expr-drop))
(define-compat expr-ceil (_fun _Expr-ptr -> _Expr-ptr) #:wrap (allocator expr-drop))
(define-compat expr-sqrt (_fun _Expr-ptr -> _Expr-ptr) #:wrap (allocator expr-drop))
(define-compat expr-exp (_fun _Expr-ptr -> _Expr-ptr) #:wrap (allocator expr-drop))
(define-compat expr-log1p (_fun _Expr-ptr -> _Expr-ptr) #:wrap (allocator expr-drop))

(define-compat expr-round/raw
  (_fun _Expr-ptr _uint32 -> _Expr-ptr)
  #:c-id expr_round
  #:wrap (allocator expr-drop))

(define (expr-round e #:decimals [decimals 0])
  (expr-round/raw e decimals))

(define-compat expr-log/raw
  (_fun _Expr-ptr _double -> _Expr-ptr)
  #:c-id expr_log
  #:wrap (allocator expr-drop))

(define (expr-log e #:base [base (exp 1)])
  (expr-log/raw e (exact->inexact base)))

(define-compat expr-pow/raw
  (_fun _Expr-ptr _Expr-ptr -> _Expr-ptr)
  #:c-id expr_pow
  #:wrap (allocator expr-drop))

(define (expr-pow e exponent) (expr-pow/raw e (->expr/who 'expr-pow exponent)))

(define-compat expr-clip/raw
  (_fun _Expr-ptr _uint8 _Expr-ptr/null _uint8 _Expr-ptr/null -> _Expr-ptr)
  #:c-id expr_clip
  #:wrap (allocator expr-drop))

(define (expr-clip e #:lower [lower #f] #:upper [upper #f])
  (expr-clip/raw e
                 (if lower 1 0) (and lower (->expr/who 'expr-clip lower))
                 (if upper 1 0) (and upper (->expr/who 'expr-clip upper))))

(define-syntax-parse-rule (define-cum name:id raw:id c-id:id)
  (begin
    (define-compat raw
      (_fun _Expr-ptr _uint8 -> _Expr-ptr)
      #:c-id c-id
      #:wrap (allocator expr-drop))
    (define (name e #:reverse [reverse #f])
      (raw e (if reverse 1 0)))))

(define-cum expr-cum-sum   expr-cum-sum/raw   expr_cum_sum)
(define-cum expr-cum-prod  expr-cum-prod/raw  expr_cum_prod)
(define-cum expr-cum-min   expr-cum-min/raw   expr_cum_min)
(define-cum expr-cum-max   expr-cum-max/raw   expr_cum_max)
(define-cum expr-cum-count expr-cum-count/raw expr_cum_count)

(define-compat expr-shift/raw
  (_fun _Expr-ptr _int64 -> _Expr-ptr)
  #:c-id expr_shift
  #:wrap (allocator expr-drop))

(define-compat expr-shift-and-fill/raw
  (_fun _Expr-ptr _int64 _Expr-ptr -> _Expr-ptr)
  #:c-id expr_shift_and_fill
  #:wrap (allocator expr-drop))

(define (expr-shift e #:n [n 1] #:fill-value [fill-value #f])
  (if fill-value
      (expr-shift-and-fill/raw e n (->expr/who 'expr-shift fill-value))
      (expr-shift/raw e n)))

(define-compat expr-diff/raw
  (_fun _Expr-ptr _int64 _uint8 -> _Expr-ptr)
  #:c-id expr_diff
  #:wrap (allocator expr-drop))

(define null-behavior/c (or/c 'ignore 'drop))

(define (expr-diff e #:n [n 1] #:null-behavior [null-behavior 'ignore])
  (expr-diff/raw e n (if (eq? null-behavior 'drop) 1 0)))

(define-compat expr-cast/c
  (_fun _Expr-ptr _CompatDType -> _Expr-ptr)
  #:c-id expr_cast
  #:wrap (allocator expr-drop))

(define-compat expr-cast-enum/raw
  (_fun _Expr-ptr _str-list -> _Expr-ptr/null)
  #:c-id expr_cast_enum_v2
  #:wrap (allocator expr-drop))

(define-compat expr-cast-datetime-tz/raw
  (_fun _Expr-ptr _int32 _c-string -> _Expr-ptr/null)
  #:c-id expr_cast_datetime_tz
  #:wrap (allocator expr-drop))

(define (expr-cast e dtype)
  (expr-cast-to 'expr-cast e dtype))

(define (expr-cast-to who e dtype)
  (cond
    [(enum-dtype? dtype)
     (call/foreign-error who
                         (lambda () (expr-cast-enum/raw e (map symbol->string (cdr dtype))))
                         "cannot convert to ~v" dtype)]
    [(zoned-datetime-dtype? dtype)
     (match-define (list _ unit zone) dtype)
     (call/foreign-error who
                         (lambda ()
                           (expr-cast-datetime-tz/raw e (time-unit-symbol->code unit) zone))
                         "cannot convert to ~v" dtype)]
    [else (expr-cast/c e (->compat-dtype dtype))]))

(module+ internal
  (provide expr-cast-datetime-tz/raw expr-diff expr-forward-fill expr-round expr-shift))
