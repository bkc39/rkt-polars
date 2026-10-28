#lang racket/base

;; Shared Expr / LazyFrame FFI plumbing and scalar leaves.

(require ffi/unsafe
         ffi/unsafe/alloc
         ffi/unsafe/define
         ffi/unsafe/define/conventions
         (only-in racket/contract
                  [-> ->/c] ->* ->i and/c any/c contract-name contract-out flat-named-contract
                  integer-in non-empty-listof not/c or/c rename-contract)
         racket/match
         racket/runtime-path
         (only-in polars/private/c-integer int32/c int64-max int64-min int64/c uint64-max uint64/c)
         polars/private/column-pattern
         (only-in polars/private/foreign
                  ->compat-dtype DataFrame-ptr? Series-ptr? _CompatDType _rsstr
                  allocator/or-fail call/foreign-error check-enum-categories
                  dataframe-drop define-owned-cpointer-type enum-dtype? polars-null? series-drop
                  printed-or-placeholder sort-flags-mismatch sort-flags/c time-unit-symbol->code
                  write-owned zoned-datetime-dtype?)
         (only-in polars/private/generic/dtype dtype-spec? normalize-dtype)
         (only-in polars/private/resource _string-list)
         (only-in polars/private/temporal temporal-encoder temporal-value-dtype))

(provide (contract-out [expr->string (->/c Expr-ptr? string?)]
                       [drop-owned (->/c any/c void?)]
                       [expr-drop (->/c Expr-ptr? void?)]
                       [lazyframe-drop (->/c LazyFrame-ptr? void?)])
         define-compat
         _Expr-ptr _Expr-ptr/null Expr-ptr?
         _LazyFrame-ptr _LazyFrame-ptr/null LazyFrame-ptr?
         expr-drop-count expr-dropped lazyframe-drop-count lazyframe-dropped
         sort-by/c
         explain/c lazyframe-explainer
         expr-col expr-lit-f64 expr-lit-bool expr-lit-str expr-lit-null
         expr-alias
         ->expr ->expr/who lit/who
         lit-integer/c
         dtype-spec?
         (contract-out
          [expr-lit-i32 (->/c int32/c Expr-ptr?)]
          [expr-lit-i64 (->/c int64/c Expr-ptr?)]
          [expr-lit-u64 (->/c uint64/c Expr-ptr?)]
          [lit (->/c lit-value/c Expr-ptr?)]
          [col (->/c col-spec/c Expr-ptr?)]
          [expr-all (->/c Expr-ptr?)]
          [expr-dtype-col (->/c dtype-spec? Expr-ptr?)]
          [expr-exclude (->/c multi-column-expr? (non-empty-listof column-pattern/c) Expr-ptr?)]
          [multi-column-expr? (->/c any/c boolean?)]))

(define-runtime-path expr-native-libs-dir "../native-libs")

(define-ffi-definer define-compat
  (ffi-lib (build-path expr-native-libs-dir "libcompat"))
  #:make-c-id convention:hyphen->underscore)

(define-owned-cpointer-type _Expr-ptr expr #:noun "expression" #:wrap (lambda (p) (expr p))
  (define-compat expr-drop/raw
    (_fun _Expr-ptr -> _void)
    #:c-id expr_drop
    #:wrap (deallocator)))

(struct expr (ptr)
  #:property prop:cpointer 0
  #:property prop:custom-write
  (write-owned 'expr expr-dropped
               (lambda (e) (printed-or-placeholder 'expr (lambda () (expr->string/raw e))))))

(define-owned-cpointer-type _LazyFrame-ptr lazyframe
  (define-compat lazyframe-drop/raw
    (_fun _LazyFrame-ptr -> _void)
    #:c-id lazyframe_drop
    #:wrap (deallocator)))

(define (drop-owned v)
  (cond
    [(Series-ptr? v) (series-drop v)]
    [(DataFrame-ptr? v) (dataframe-drop v)]
    [(Expr-ptr? v) (expr-drop v)]
    [(LazyFrame-ptr? v) (lazyframe-drop v)]
    [else (void)]))

(define-compat expr-drop-count
  (_fun -> _size))

(define-compat lazyframe-drop-count
  (_fun -> _size))

(define-compat expr->string/raw
  (_fun _Expr-ptr -> _rsstr)
  #:c-id expr_to_string_v2)

(define (expr->string e)
  (call/foreign-error 'expr->string (lambda () (expr->string/raw e)) "cannot print the expression"))

(define-compat lazyframe-explain/raw
  (_fun _LazyFrame-ptr _stdbool _stdbool -> _rsstr)
  #:c-id lazyframe_explain_v2)

(define explain-format/c (rename-contract (or/c 'plain 'tree) 'explain-format/c))

(define (explain/c frame/c)
  (->* (frame/c) (#:optimized boolean? #:format explain-format/c) string?))

(define (lazyframe-explainer who)
  (procedure-rename
   (lambda (lf #:optimized [optimized #t] #:format [format 'plain])
     (call/foreign-error who
                         (lambda () (lazyframe-explain/raw lf optimized (eq? format 'tree)))
                         "failed to explain the query"))
   who))

(define-compat expr-col
  (_fun _string -> _Expr-ptr)
  #:wrap (allocator expr-drop))

(define-compat expr-lit-i32
  (_fun _int32 -> _Expr-ptr)
  #:wrap (allocator expr-drop))

(define-compat expr-lit-i64
  (_fun _int64 -> _Expr-ptr)
  #:wrap (allocator expr-drop))

(define-compat expr-lit-u64
  (_fun _uint64 -> _Expr-ptr)
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

(define-compat expr-lit-null
  (_fun -> _Expr-ptr)
  #:wrap (allocator expr-drop))

(define-compat expr-alias
  (_fun _Expr-ptr _string -> _Expr-ptr)
  #:wrap (allocator expr-drop))

(define-compat expr-lit-temporal
  (_fun _int64 _CompatDType -> _Expr-ptr/null)
  #:wrap (allocator/or-fail expr-drop 'expr-lit-temporal))

(define-compat expr-lit-datetime-tz/raw
  (_fun _int64 _int32 _string/utf-8 -> _Expr-ptr/null)
  #:c-id expr_lit_datetime_tz
  #:wrap (allocator expr-drop))

(define (temporal-lit who v dtype)
  (define value ((temporal-encoder who dtype) v))
  (match dtype
    [(list 'datetime unit (? string? zone))
     (define code (time-unit-symbol->code unit))
     (call/foreign-error who
                         (lambda () (expr-lit-datetime-tz/raw value code zone))
                         "no literal of ~v" dtype)]
    [_ (expr-lit-temporal value (->compat-dtype dtype))]))

(define lit-integer/c (integer-in int64-min uint64-max))

(define (lit-value? v)
  (or (boolean? v) (string? v) (symbol? v) (polars-null? v)
      (and (real? v) (or (not (exact-integer? v)) (lit-integer/c v)))
      (and (temporal-value-dtype v) #t)))

(define lit-value/c
  (flat-named-contract
   `(or/c boolean? ,(contract-name lit-integer/c) (and/c real? (not/c exact-integer?))
          string? symbol? polars-null? gregor-value)
   lit-value?))

(define (lit/who who v)
  (cond
    [(boolean? v) (expr-lit-bool v)]
    [(int32/c v) (expr-lit-i32 v)]
    [(int64/c v) (expr-lit-i64 v)]
    [(uint64/c v) (expr-lit-u64 v)]
    [(and (real? v) (not (exact-integer? v))) (expr-lit-f64 (exact->inexact v))]
    [(string? v) (expr-lit-str v)]
    [(symbol? v) (expr-lit-str (symbol->string v))]
    [(polars-null? v) (expr-lit-null)]
    [(temporal-value-dtype v) => (lambda (dtype) (temporal-lit who v dtype))]
    [else
     (define expected (if (exact-integer? v) lit-integer/c lit-value/c))
     (raise-argument-error who (format "~s" (contract-name expected)) v)]))

(define (lit v)
  (lit/who 'lit v))

(define-compat expr-all
  (_fun -> _Expr-ptr)
  #:wrap (allocator expr-drop))

(define-compat expr-multi-column/raw
  (_fun _Expr-ptr -> _uint8)
  #:c-id expr_multi_column)

(define (multi-column-expr? v)
  (and (Expr-ptr? v) (= 1 (expr-multi-column/raw v))))

(define-compat expr-exclude/raw
  (_fun _Expr-ptr
        (names : _string-list)
        (_size = (length names))
        -> _Expr-ptr/null)
  #:c-id expr_exclude
  #:wrap (allocator expr-drop))

(define-compat expr-dtype-col/raw
  (_fun _CompatDType -> _Expr-ptr/null)
  #:c-id expr_dtype_col
  #:wrap (allocator expr-drop))

(define (expr-exclude e names)
  (or (expr-exclude/raw e (map ->column-pattern names))
      (error 'expr-exclude "operation failed")))

(define-compat expr-dtype-col-enum/raw
  (_fun (categories : _string-list)
        (_size = (length categories))
        -> _Expr-ptr/null)
  #:c-id expr_dtype_col_enum
  #:wrap (allocator expr-drop))

(define-compat expr-dtype-col-datetime-tz/raw
  (_fun _int32 _string/utf-8 -> _Expr-ptr/null)
  #:c-id expr_dtype_col_datetime_tz
  #:wrap (allocator expr-drop))

(define (expr-dtype-col dtype)
  (dtype-col 'expr-dtype-col dtype))

(define (dtype-col who dtype)
  (match dtype
    [(? enum-dtype?)
     (check-enum-categories who dtype)
     (call/foreign-error who
                         (lambda () (expr-dtype-col-enum/raw (map symbol->string (cdr dtype))))
                         "cannot select ~v" dtype)]
    [(? zoned-datetime-dtype? (list _ unit zone))
     (define code (time-unit-symbol->code unit))
     (call/foreign-error who
                         (lambda () (expr-dtype-col-datetime-tz/raw code zone))
                         "cannot select ~v" dtype)]
    [_ (or (expr-dtype-col/raw (->compat-dtype (normalize-dtype dtype)))
           (error who "operation failed"))]))

(define (col spec)
  (if (dtype-spec? spec)
      (dtype-col 'col spec)
      (expr-col (->column-pattern spec))))

(define col-spec/c
  (column-spec-contract '(or/c string? regexp? dtype-spec?)
                        (lambda (v) (or (string? v) (regexp? v) (dtype-spec? v)))))

(define (->expr/who who v)
  (if (Expr-ptr? v) v (lit/who who v)))

(define (->expr v)
  (->expr/who 'lit v))

(define sort-by-keys/c
  (flat-named-contract 'sort-by-keys/c
                       (or/c string? Expr-ptr? (non-empty-listof (or/c string? Expr-ptr?)))))

(define (sort-by/c x/c name)
  (rename-contract
   (->i ([x x/c] #:by [by sort-by-keys/c])
        (#:descending [descending sort-flags/c]
         #:nulls-last [nulls-last sort-flags/c]
         #:maintain-order [maintain-order boolean?])
        #:pre/desc (by descending nulls-last)
        (sort-flags-mismatch by descending nulls-last)
        [result Expr-ptr?])
   name))

(module+ internal
  (provide col expr->string expr-all expr-drop expr-dtype-col expr-exclude lit lit-value/c
           multi-column-expr?))
