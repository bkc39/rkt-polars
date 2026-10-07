#lang racket/base

(require ffi/unsafe
         ffi/unsafe/alloc
         ffi/unsafe/atomic
         ffi/unsafe/define
         ffi/unsafe/define/conventions
         gregor
         gregor/period
         (only-in racket/contract/base
                  ->* ->i contract-out flat-named-contract listof non-empty-listof or/c
                  rename-contract)
         racket/match
         (only-in racket/dict in-dict)
         (only-in racket/list check-duplicates)
         (only-in racket/string string-replace)
         racket/runtime-path
         syntax/parse/define
         (only-in polars/private/resource with-raw-buffer)
         (for-syntax racket/base racket/syntax))

(module+ test
  (require rackunit))

(provide (except-out (all-defined-out) series-sort dataframe-sort)
         (contract-out
          [series-sort (->* (Series-ptr?) (#:descending boolean? #:nulls-last boolean?)
                            Series-ptr?)]
          [dataframe-sort (frame-sort/c DataFrame-ptr? 'dataframe-sort/c)]))

(define-runtime-path native-libs-dir "../native-libs")

(define-ffi-definer define-compat
  (ffi-lib (build-path native-libs-dir "libcompat"))
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
     (and ptr
          (let ([str (cast ptr _pointer _string)])
            (register-finalizer ptr string-drop)
            str)))))

(define-compat last-error-message
  (_fun -> _rsstring))

(define racket-spellings
  '(("`infer_schema_length` (e.g. `infer_schema_length=10000`)"
     . "#:infer-schema-length (e.g. #:infer-schema-length 10000, or #f for every row)")
    ("the `schema_overrides` argument" . "#:schema-overrides")
    ("setting `ignore_errors` to `True`" . "setting #:ignore-errors to #t")
    ("to the `null_values` list" . "to #:null-values")
    ("Try increasing `infer_schema_length` or specifying a schema."
     . "Try increasing #:infer-schema-length or passing #:schema.")
    ("consider increasing infer_schema_length, or manually specifying the full schema"
     . "consider increasing #:infer-schema-length, or passing the full #:schema")
    ("use the compression parameter to control compression, or set `check_extension` to `False` if you want to suffix an uncompressed filename with an ending intended for compression"
     . "pass #:check-extension #f to give an uncompressed file a compressed file's suffix")
    ("set `check_extension` to `False`" . "pass #:check-extension #f")))

(define empty-expansion
  #rx"^failed to retrieve [^:]*: expanded paths were empty \\(path expansion input: .*\\)\\.")

(define (respell reason)
  (for/fold ([reason (if (regexp-match? empty-expansion reason)
                         "no files match the pattern"
                         reason)])
            ([(python racket) (in-dict racket-spellings)])
    (string-replace reason python racket)))

;; only for entry points that call clear_last_error; elsewhere the slot is stale
(define (call/foreign-error who thunk #:ok? [ok? values] fmt . args)
  (define-values (result reason)
    (call-as-atomic
     (lambda ()
       (define result (thunk))
       (values result (and (not (ok? result)) (last-error-message))))))
  (cond
    [(ok? result) result]
    [reason (apply error who (string-append fmt ": ~a") (append args (list (respell reason))))]
    [else (apply error who fmt args)]))

;; only for entry points that record no reason; the others go through call/foreign-error
(define ((allocator/or-fail drop who) proc)
  (define allocate ((allocator drop) proc))
  (procedure-reduce-arity-mask
   (lambda args (or (apply allocate args) (error who "operation failed")))
   (procedure-arity-mask allocate)
   who))

(struct polars-null-sentinel ()
  #:property prop:custom-write
  (lambda (_ out mode)
    (write-string "polars-null" out)))

(define polars-null (polars-null-sentinel))

(define (polars-null? v)
  (eq? v polars-null))

(define compat-dtype-tag/unknown 0)
(define compat-dtype-tag/boolean 1)
(define compat-dtype-tag/uint8 2)
(define compat-dtype-tag/uint16 3)
(define compat-dtype-tag/uint32 4)
(define compat-dtype-tag/uint64 5)
(define compat-dtype-tag/int8 6)
(define compat-dtype-tag/int16 7)
(define compat-dtype-tag/int32 8)
(define compat-dtype-tag/int64 9)
(define compat-dtype-tag/float32 10)
(define compat-dtype-tag/float64 11)
(define compat-dtype-tag/string 12)
(define compat-dtype-tag/binary 13)
(define compat-dtype-tag/binary-offset 14)
(define compat-dtype-tag/date 15)
(define compat-dtype-tag/datetime 16)
(define compat-dtype-tag/duration 17)
(define compat-dtype-tag/time 18)
(define compat-dtype-tag/null 19)
(define compat-dtype-tag/list 20)
(define compat-dtype-tag/array 21)
(define compat-dtype-tag/struct 22)
(define compat-dtype-tag/categorical 23)
(define compat-dtype-tag/enum 24)
(define compat-dtype-tag/decimal 25)
(define compat-dtype-tag/object 26)

(define compat-time-unit/none 0)
(define compat-time-unit/nanoseconds 1)
(define compat-time-unit/microseconds 2)
(define compat-time-unit/milliseconds 3)

(define compat-dtype-flag/has-timezone #x1)

(define-cstruct _CompatDType
  ([dtype-tag _int32]
   [dtype-time-unit _int32]
   [dtype-flags _uint32]
   [dtype-array-width _size]))

(define (compat-time-unit->datum time-unit)
  (case time-unit
    [(1) 'nanoseconds]
    [(2) 'microseconds]
    [(3) 'milliseconds]
    [else #f]))

(define (compat-dtype->datum dtype)
  (define tag (CompatDType-dtype-tag dtype))
  (define time-unit (compat-time-unit->datum (CompatDType-dtype-time-unit dtype)))
  (define flags (CompatDType-dtype-flags dtype))
  (define array-width (CompatDType-dtype-array-width dtype))
  (case tag
    [(1) 'boolean]
    [(2) 'uint8]
    [(3) 'uint16]
    [(4) 'uint32]
    [(5) 'uint64]
    [(6) 'int8]
    [(7) 'int16]
    [(8) 'int32]
    [(9) 'int64]
    [(10) 'float32]
    [(11) 'float64]
    [(12) 'string]
    [(13) 'binary]
    [(14) 'binary-offset]
    [(15) 'date]
    [(16) (list 'datetime
                time-unit
                (and (positive? (bitwise-and flags compat-dtype-flag/has-timezone))
                     'todo-timezone))]
    [(17) (list 'duration time-unit)]
    [(18) 'time]
    [(19) 'null]
    [(20) '(todo nested-dtype-support list)]
    [(21) (list 'todo 'nested-dtype-support 'array array-width)]
    [(22) '(todo nested-dtype-support struct)]
    [(23) 'categorical]
    [(24) 'enum]
    [(25) (list 'decimal array-width (CompatDType-dtype-time-unit dtype))]
    [(26) '(todo parameterized-dtype-support object)]
    [else 'unknown]))

(define (enum-dtype? v)
  (match v
    [(cons 'enum (and (list (? symbol?) ...) categories)) (not (check-duplicates categories))]
    [_ #f]))

(define (decimal-dtype? v)
  (match v
    [(list 'decimal (? exact-positive-integer?) (? exact-nonnegative-integer?)) #t]
    [_ #f]))

(define-cstruct _CompatOptI32
  ([valid _int32]
   [value _int32]))

(define-cstruct _CompatOptI8
  ([valid _int32]
   [value _int8]))

(define-cstruct _CompatOptI16
  ([valid _int32]
   [value _int16]))

(define-cstruct _CompatOptF64
  ([valid _int32]
   [value _double]))

(define-cstruct _CompatOptF32
  ([valid _int32]
   [value _float]))

(define-cstruct _CompatOptI64
  ([valid _int32]
   [value _int64]))

(define-cstruct _CompatOptU8
  ([valid _int32]
   [value _uint8]))

(define-cstruct _CompatOptU16
  ([valid _int32]
   [value _uint16]))

(define-cstruct _CompatOptU32
  ([valid _int32]
   [value _uint32]))

(define-cstruct _CompatOptU64
  ([valid _int32]
   [value _uint64]))

(define-cstruct _CompatOptBool
  ([valid _int32]
   [value _int32]))

(define-cstruct _YMD
  ([ymd-year _int32]
   [ymd-month _uint32]
   [ymd-day _uint32]))

(define-cstruct _CompatOptYMD
  ([valid _int32]
   [value _YMD]))

(define (compat-opt-i32->datum o)
  (and (not (zero? (CompatOptI32-valid o)))
       (CompatOptI32-value o)))

(define (compat-opt-i8->datum o)
  (and (not (zero? (CompatOptI8-valid o)))
       (CompatOptI8-value o)))

(define (compat-opt-i16->datum o)
  (and (not (zero? (CompatOptI16-valid o)))
       (CompatOptI16-value o)))

(define (compat-opt-f64->datum o)
  (and (not (zero? (CompatOptF64-valid o)))
       (CompatOptF64-value o)))

(define (compat-opt-f32->datum o)
  (and (not (zero? (CompatOptF32-valid o)))
       (CompatOptF32-value o)))

(define (compat-opt-i64->datum o)
  (and (not (zero? (CompatOptI64-valid o)))
       (CompatOptI64-value o)))

(define (compat-opt-u8->datum o)
  (and (not (zero? (CompatOptU8-valid o)))
       (CompatOptU8-value o)))

(define (compat-opt-u16->datum o)
  (and (not (zero? (CompatOptU16-valid o)))
       (CompatOptU16-value o)))

(define (compat-opt-u32->datum o)
  (and (not (zero? (CompatOptU32-valid o)))
       (CompatOptU32-value o)))

(define (compat-opt-u64->datum o)
  (and (not (zero? (CompatOptU64-valid o)))
       (CompatOptU64-value o)))

(define (compat-opt-bool->datum o)
  (and (not (zero? (CompatOptBool-valid o)))
       (not (zero? (CompatOptBool-value o)))))

(define (ymd->date value)
  (date (YMD-ymd-year value)
        (YMD-ymd-month value)
        (YMD-ymd-day value)))

(define (compat-opt-ymd->datum o)
  (and (not (zero? (CompatOptYMD-valid o)))
       (ymd->date (CompatOptYMD-value o))))

;; allocator registers the release on the pointer a wrapper holds, not on the wrapper
(define-values (prop:owned-pointer owned-pointer? owned-pointer-accessor)
  (make-struct-type-property
   'owned-pointer
   (lambda (index info)
     (define field-ref (list-ref info 3))
     (lambda (v) (field-ref v index)))))

(define (owned-pointer-arg args)
  (let unwrap ([v (car args)])
    (if (owned-pointer? v) (unwrap ((owned-pointer-accessor v) v)) v)))

(define-cpointer-type _Series-ptr)

(define-compat series-drop
  (_fun _Series-ptr -> _void)
  #:wrap (deallocator owned-pointer-arg))

(define-compat series-drop-count
  (_fun -> _size))

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

(define-compat series-dtype/raw
  (_fun _Series-ptr -> _CompatDType)
  #:c-id series_dtype)

(define-compat series-enum-categories/raw
  (_fun _Series-ptr -> _Series-ptr/null)
  #:c-id series_enum_categories
  #:wrap (allocator/or-fail series-drop 'series-enum-categories))

(define (series-enum-categories s)
  (define names (series-enum-categories/raw s))
  (begin0 (for/list ([i (in-range (series-len names))])
            (string->symbol (series-ref-str/raw names i)))
          (series-drop names)))

(define (series-dtype series)
  (match (compat-dtype->datum (series-dtype/raw series))
    ['enum (cons 'enum (series-enum-categories series))]
    [dtype dtype]))

(define (time-unit-symbol->code tu)
  (case tu
    [(#f none) compat-time-unit/none]
    [(nanoseconds) compat-time-unit/nanoseconds]
    [(microseconds) compat-time-unit/microseconds]
    [(milliseconds) compat-time-unit/milliseconds]
    [else (error '->compat-dtype "unknown time unit ~v" tu)]))

(define (simple-dtype-tag sym)
  (case sym
    [(boolean)   compat-dtype-tag/boolean]
    [(uint8)     compat-dtype-tag/uint8]
    [(uint16)    compat-dtype-tag/uint16]
    [(uint32)    compat-dtype-tag/uint32]
    [(uint64)    compat-dtype-tag/uint64]
    [(int8)      compat-dtype-tag/int8]
    [(int16)     compat-dtype-tag/int16]
    [(int32)     compat-dtype-tag/int32]
    [(int64)     compat-dtype-tag/int64]
    [(float32)   compat-dtype-tag/float32]
    [(float64)   compat-dtype-tag/float64]
    [(string)    compat-dtype-tag/string]
    [(binary)    compat-dtype-tag/binary]
    [(date)      compat-dtype-tag/date]
    [(time)      compat-dtype-tag/time]
    [(null)      compat-dtype-tag/null]
    [(categorical) compat-dtype-tag/categorical]
    [else        #f]))

(define (->compat-dtype dtype)
  (cond
    [(symbol? dtype)
     (define tag (simple-dtype-tag dtype))
     (case dtype
       [(datetime)
        (make-CompatDType compat-dtype-tag/datetime
                          compat-time-unit/microseconds 0 0)]
       [(duration)
        (make-CompatDType compat-dtype-tag/duration
                          compat-time-unit/microseconds 0 0)]
       [else
        (unless tag
          (error '->compat-dtype "unsupported cast target ~v" dtype))
        (make-CompatDType tag compat-time-unit/none 0 0)])]
    [(and (pair? dtype) (eq? (car dtype) 'datetime))
     (make-CompatDType compat-dtype-tag/datetime
                       (time-unit-symbol->code (cadr dtype)) 0 0)]
    [(and (pair? dtype) (eq? (car dtype) 'duration))
     (make-CompatDType compat-dtype-tag/duration
                       (time-unit-symbol->code (cadr dtype)) 0 0)]
    [else (error '->compat-dtype "unsupported cast target ~v" dtype)]))

(define-compat series-rename
  (_fun _Series-ptr _string -> _void))

(module+ test
  (check-equal? (series-name (series-empty)) "")
  (check-equal? (series-dtype (series-empty)) 'int32)
  (check-equal?
   (let ([s (series-empty)])
     (series-rename s "hello")
     (series-name s))
   "hello"))

(define-compat series-len
  (_fun _Series-ptr -> _size))

(define-compat series-null-count
  (_fun _Series-ptr -> _size))

(define-compat series-sum-i32/raw
  (_fun _Series-ptr -> _CompatOptI32)
  #:c-id series_sum_i32)

(define (series-sum-i32 s)
  (compat-opt-i32->datum (series-sum-i32/raw s)))

(define-compat series-sum-f64/raw
  (_fun _Series-ptr -> _CompatOptF64)
  #:c-id series_sum_f64)

(define (series-sum-f64 s)
  (compat-opt-f64->datum (series-sum-f64/raw s)))

(define-compat series-mean-f64/raw
  (_fun _Series-ptr -> _CompatOptF64)
  #:c-id series_mean_f64)

(define (series-mean-f64 s)
  (compat-opt-f64->datum (series-mean-f64/raw s)))

(define-compat series-max-f64/raw
  (_fun _Series-ptr -> _CompatOptF64)
  #:c-id series_max_f64)

(define (series-max-f64 s)
  (compat-opt-f64->datum (series-max-f64/raw s)))

(define-compat series-min-i32/raw
  (_fun _Series-ptr -> _CompatOptI32)
  #:c-id series_min_i32)

(define (series-min-i32 s)
  (compat-opt-i32->datum (series-min-i32/raw s)))

(define-compat series-max-i32/raw
  (_fun _Series-ptr -> _CompatOptI32)
  #:c-id series_max_i32)

(define (series-max-i32 s)
  (compat-opt-i32->datum (series-max-i32/raw s)))

(define-compat series-mean-i32/raw
  (_fun _Series-ptr -> _CompatOptF64)
  #:c-id series_mean_i32)

(define (series-mean-i32 s)
  (compat-opt-f64->datum (series-mean-i32/raw s)))

(define-compat series-min-f64/raw
  (_fun _Series-ptr -> _CompatOptF64)
  #:c-id series_min_f64)

(define (series-min-f64 s)
  (compat-opt-f64->datum (series-min-f64/raw s)))

(define-syntax-parse-rule (define-int-reductions opt-type:id opt->datum:id
                            sum-id:id min-id:id max-id:id mean-id:id
                            sum-c:id min-c:id max-c:id mean-c:id)
  (begin
    (define-compat sum-id/raw
      (_fun _Series-ptr -> opt-type)
      #:c-id sum-c)
    (define (sum-id s)
      (opt->datum (sum-id/raw s)))

    (define-compat min-id/raw
      (_fun _Series-ptr -> opt-type)
      #:c-id min-c)
    (define (min-id s)
      (opt->datum (min-id/raw s)))

    (define-compat max-id/raw
      (_fun _Series-ptr -> opt-type)
      #:c-id max-c)
    (define (max-id s)
      (opt->datum (max-id/raw s)))

    (define-compat mean-id/raw
      (_fun _Series-ptr -> _CompatOptF64)
      #:c-id mean-c)
    (define (mean-id s)
      (compat-opt-f64->datum (mean-id/raw s)))))

(define-int-reductions _CompatOptI64 compat-opt-i64->datum
  series-sum-i64 series-min-i64 series-max-i64 series-mean-i64
  series_sum_i64 series_min_i64 series_max_i64 series_mean_i64)

(define-int-reductions _CompatOptI8 compat-opt-i8->datum
  series-sum-i8 series-min-i8 series-max-i8 series-mean-i8
  series_sum_i8 series_min_i8 series_max_i8 series_mean_i8)

(define-int-reductions _CompatOptI16 compat-opt-i16->datum
  series-sum-i16 series-min-i16 series-max-i16 series-mean-i16
  series_sum_i16 series_min_i16 series_max_i16 series_mean_i16)

(define-int-reductions _CompatOptU8 compat-opt-u8->datum
  series-sum-u8 series-min-u8 series-max-u8 series-mean-u8
  series_sum_u8 series_min_u8 series_max_u8 series_mean_u8)

(define-int-reductions _CompatOptU16 compat-opt-u16->datum
  series-sum-u16 series-min-u16 series-max-u16 series-mean-u16
  series_sum_u16 series_min_u16 series_max_u16 series_mean_u16)

(define-int-reductions _CompatOptU32 compat-opt-u32->datum
  series-sum-u32 series-min-u32 series-max-u32 series-mean-u32
  series_sum_u32 series_min_u32 series_max_u32 series_mean_u32)

(define-int-reductions _CompatOptU64 compat-opt-u64->datum
  series-sum-u64 series-min-u64 series-max-u64 series-mean-u64
  series_sum_u64 series_min_u64 series_max_u64 series_mean_u64)

(define-int-reductions _CompatOptF32 compat-opt-f32->datum
  series-sum-f32 series-min-f32 series-max-f32 series-mean-f32
  series_sum_f32 series_min_f32 series_max_f32 series_mean_f32)

(define-compat series-n-unique
  (_fun _Series-ptr -> _size))

(define-compat series-head
  (_fun _Series-ptr _size -> _Series-ptr)
  #:wrap (allocator series-drop))

(define-compat series-tail
  (_fun _Series-ptr _size -> _Series-ptr)
  #:wrap (allocator series-drop))

(define-compat series-slice
  (_fun _Series-ptr _int64 _size -> _Series-ptr)
  #:wrap (allocator series-drop))

(define-compat series-reverse
  (_fun _Series-ptr -> _Series-ptr)
  #:wrap (allocator series-drop))

(define-compat series-drop-nulls
  (_fun _Series-ptr -> _Series-ptr)
  #:wrap (allocator series-drop))

(define-compat series-unique
  (_fun _Series-ptr -> _Series-ptr/null)
  #:wrap (allocator/or-fail series-drop 'series-unique))

(define-compat series-sort/raw
  (_fun _Series-ptr _stdbool _stdbool -> _Series-ptr/null)
  #:c-id series_sort_with_options
  #:wrap (allocator series-drop))

(define (series-sort s #:descending [descending #f] #:nulls-last [nulls-last #f])
  (call/foreign-error 'series-sort
                      (lambda () (series-sort/raw s descending nulls-last))
                      "failed to sort the series"))

(module+ test
  (define s (series-new-i32 "x" '(3 1 4 1 5 9 2 6)))
  (check-equal? (series-len (series-head s 3)) 3)
  (check-equal? (series-sum-i32 (series-head s 3)) 8) ;; 3+1+4
  (check-equal? (series-len (series-tail s 3)) 3)
  (check-equal? (series-sum-i32 (series-tail s 3)) 17) ;; 9+2+6
  (check-equal? (series-len (series-slice s 2 3)) 3)
  (check-equal? (series-sum-i32 (series-slice s 2 3)) 10) ;; 4+1+5
  (check-equal? (series-len (series-reverse s)) 8)
  (check-equal? (series-sum-i32 (series-reverse s)) (series-sum-i32 s))
  (check-equal? (series-len (series-unique s)) 7) ;; one duplicate (1)

  ;; sort
  (check-equal? (series-min-i32 (series-head (series-sort s) 1)) 1)
  (check-equal? (series-max-i32
                 (series-head (series-sort s #:descending #t) 1))
                9)

  ;; drop_nulls on a series with no nulls is a no-op
  (check-equal? (series-len (series-drop-nulls s)) 8))

(module+ test
  (define red-i32 (series-new-i32 "x" '(3 1 4 1 5 9 2 6)))
  (check-equal? (series-min-i32 red-i32) 1)
  (check-equal? (series-max-i32 red-i32) 9)
  (check-= (series-mean-i32 red-i32) (/ 31.0 8.0) 1e-9)
  (check-equal? (series-n-unique red-i32) 7) ;; {1,2,3,4,5,6,9}

  (define red-f64 (series-new-f64 "y" '(1.5 2.0 4.25 8.0)))
  (check-equal? (series-min-f64 red-f64) 1.5)

  (define red-i64 (series-new-i64 "wide" (list 1099511627776 polars-null 4)))
  (check-equal? (series-sum-i64 red-i64) 1099511627780)
  (check-equal? (series-min-i64 red-i64) 4)
  (check-equal? (series-max-i64 red-i64) 1099511627776)
  (check-= (series-mean-i64 red-i64) (/ 1099511627780.0 2.0) 1e-9)

  (define red-u32 (series-new-u32 "count" (list 1 2 polars-null 7)))
  (check-equal? (series-sum-u32 red-u32) 10)
  (check-equal? (series-min-u32 red-u32) 1)
  (check-equal? (series-max-u32 red-u32) 7)
  (check-= (series-mean-u32 red-u32) (/ 10.0 3.0) 1e-9)

  (define red-u64 (series-new-u64 "big" (list 10 20 4294967296)))
  (check-equal? (series-sum-u64 red-u64) 4294967326)
  (check-equal? (series-min-u64 red-u64) 10)
  (check-equal? (series-max-u64 red-u64) 4294967296)
  (check-= (series-mean-u64 red-u64) (/ 4294967326.0 3.0) 1e-6)

  (define red-i8 (series-new-i8 "tiny" (list -4 polars-null 9)))
  (check-equal? (series-sum-i8 red-i8) 5)
  (check-equal? (series-min-i8 red-i8) -4)
  (check-equal? (series-max-i8 red-i8) 9)
  (check-= (series-mean-i8 red-i8) 2.5 1e-9)

  (define red-i16 (series-new-i16 "short" (list -300 polars-null 1200)))
  (check-equal? (series-sum-i16 red-i16) 900)
  (check-equal? (series-min-i16 red-i16) -300)
  (check-equal? (series-max-i16 red-i16) 1200)
  (check-= (series-mean-i16 red-i16) 450.0 1e-9)

  (define red-u8 (series-new-u8 "byte" (list 3 polars-null 12)))
  (check-equal? (series-sum-u8 red-u8) 15)
  (check-equal? (series-min-u8 red-u8) 3)
  (check-equal? (series-max-u8 red-u8) 12)
  (check-= (series-mean-u8 red-u8) 7.5 1e-9)

  (define red-u16 (series-new-u16 "ushort" (list 300 polars-null 1200)))
  (check-equal? (series-sum-u16 red-u16) 1500)
  (check-equal? (series-min-u16 red-u16) 300)
  (check-equal? (series-max-u16 red-u16) 1200)
  (check-= (series-mean-u16 red-u16) 750.0 1e-9)

  (define red-f32 (series-new-f32 "single" (list 1.5 polars-null 2.25)))
  (check-= (series-sum-f32 red-f32) 3.75 1e-6)
  (check-= (series-min-f32 red-f32) 1.5 1e-6)
  (check-= (series-max-f32 red-f32) 2.25 1e-6)
  (check-= (series-mean-f32 red-f32) 1.875 1e-6)

  (check-equal? (series-n-unique
                 (series-new-str "s" '("a" "b" "a" "c" "b")))
                3))

(module+ test
  (check-equal? (series-len (series-empty)) 0)
  (check-equal? (series-null-count (series-empty)) 0))

(define (values+valid input-values default-value)
  (for/lists (clean-values valid)
             ([value input-values])
    (if (polars-null? value)
        (values default-value 0)
        (values value 1))))

(define (contains-polars-null? values)
  (ormap polars-null? values))

(define-syntax-parse-rule (define-series-constructors rs-type:id ctype:id default-value:expr)
  #:with list-constructor-name (format-id #'rs-type "series-new-~a" #'rs-type)
  #:with vector-constructor-name (format-id #'rs-type
                                            "series-new-~a/vec"
                                            #'rs-type)
  #:with list-constructor-raw-name (format-id #'rs-type "series-new-~a/raw" #'rs-type)
  #:with vector-constructor-raw-name (format-id #'rs-type
                                                "series-new-~a/vec/raw"
                                                #'rs-type)
  #:with opt-constructor-name (format-id #'rs-type "series-new-~a/opt/raw" #'rs-type)
  #:with rust-id (format-id #'rs-type "series_new_~a" #'rs-type)
  #:with rust-opt-id (format-id #'rs-type "series_new_opt_~a" #'rs-type)
  (begin
    (define-compat list-constructor-raw-name
      (_fun _string
            (v : (_list i ctype))
            (_size = (length v))
            -> _Series-ptr/null)
      #:c-id rust-id
      #:wrap (allocator/or-fail series-drop 'list-constructor-name))
    (define-compat vector-constructor-raw-name
      (_fun _string
            (v : (_vector i ctype))
            (_size = (vector-length v))
            -> _Series-ptr/null)
      #:c-id rust-id
      #:wrap (allocator/or-fail series-drop 'vector-constructor-name))
    (define-compat opt-constructor-name
      (_fun _string
            (v : (_list i ctype))
            (valid : (_list i _uint8))
            (_size = (length v))
            -> _Series-ptr/null)
      #:c-id rust-opt-id
      #:wrap (allocator/or-fail series-drop 'list-constructor-name))
    (define (list-constructor-name name values)
      (if (contains-polars-null? values)
          (let-values ([(clean-values valid) (values+valid values default-value)])
            (opt-constructor-name name clean-values valid))
          (list-constructor-raw-name name values)))
    (define (vector-constructor-name name values)
      (if (for/or ([value (in-vector values)])
            (polars-null? value))
          (let-values ([(clean-values valid)
                        (values+valid (vector->list values) default-value)])
            (opt-constructor-name name clean-values valid))
          (vector-constructor-raw-name name values)))))

(define-series-constructors i32 _int32 0)

(define-series-constructors i8 _int8 0)
(define-series-constructors i16 _int16 0)

(module+ test
  (check-pred Series-ptr? (series-new-i32 "" '(1 2 3)))
  (check-equal?
   (series-len (series-new-i32 "series" '(0 1)))
   2)
  (check-equal?
   (series-dtype (series-new-i32 "series" '(0 1)))
   'int32)
  (check-equal?
   (series-sum-i32 (series-new-i32 "" '(1 2 3 4)))
   10)
  (check-false
   (series-sum-i32 (series-new-f64 "" '(1.0 2.0)))) ;; wrong dtype
  (check-exn
   #rx"^series-new-i32: operation failed$"
   (lambda ()
     (series-new-i32 "example" '())))

  (check-pred Series-ptr? (series-new-i32/vec "" (vector 1 2 3)))
  (check-equal?
   (series-len (series-new-i32/vec "" (vector 0)))
   1))

(module+ test
  (check-pred Series-ptr? (series-new-i8 "x" '(-8 0 12)))
  (check-equal? (series-dtype (series-new-i8 "x" '(-8 0 12))) 'int8)
  (check-pred Series-ptr? (series-new-i8/vec "x" (vector -8 0 12)))
  (check-pred Series-ptr? (series-new-i16 "x" '(-300 0 1200)))
  (check-equal? (series-dtype (series-new-i16 "x" '(-300 0 1200))) 'int16)
  (check-pred Series-ptr? (series-new-i16/vec "x" (vector -300 0 1200))))

(define-series-constructors f64 _double 0.0)

(define-series-constructors f32 _float 0.0)

(module+ test
  (check-pred Series-ptr? (series-new-f64 "" '(1.1 2.17)))
  (check-equal?
   (series-len (series-new-f64 "series" '(0.0 1.2)))
   2)
  (check-equal?
   (series-dtype (series-new-f64 "series" '(0.0 1.2)))
   'float64)
  (check-equal?
   (series-sum-f64 (series-new-f64 "" '(1.5 2.0 4.25 8.0)))
   15.75)
  (check-equal?
   (series-mean-f64 (series-new-f64 "" '(1.0 2.0 3.0 4.0)))
   2.5)
  (check-equal?
   (series-max-f64 (series-new-f64 "" '(1.5 2.0 4.25 8.0)))
   8.0)
  (check-exn
   #rx"^series-new-f64: operation failed$"
   (lambda ()
     (series-new-f64 "example" '())))
  (check-exn
   #rx"given value does not fit primitive C type"
   (λ ()
     (series-new-f64 "no-name" '(0))))

  (check-pred Series-ptr? (series-new-f64/vec "" (vector 17.29 40.2)))
  (check-equal?
   (series-len (series-new-f64/vec "" (vector 17.29 40.2)))
   2))

(module+ test
  (check-pred Series-ptr? (series-new-f32 "" '(1.5 2.25)))
  (check-equal? (series-dtype (series-new-f32 "x" '(1.5 2.25))) 'float32)
  (check-pred Series-ptr? (series-new-f32/vec "" (vector 1.5 2.25))))

(define-series-constructors i64 _int64 0)

(module+ test
  (check-pred Series-ptr? (series-new-i64 "" '(1 2 3)))
  (check-equal? (series-len (series-new-i64 "x" '(1 2))) 2)
  (check-equal? (series-dtype (series-new-i64 "x" '(1 2))) 'int64)
  (check-pred Series-ptr? (series-new-i64/vec "" (vector 1 2 3))))

(define-series-constructors u32 _uint32 0)

(define-series-constructors u8 _uint8 0)
(define-series-constructors u16 _uint16 0)

(module+ test
  (check-pred Series-ptr? (series-new-u32 "" '(1 2 3)))
  (check-equal? (series-len (series-new-u32 "x" '(0 1 2))) 3)
  (check-equal? (series-dtype (series-new-u32 "x" '(0 1))) 'uint32)
  (check-pred Series-ptr? (series-new-u32/vec "" (vector 1 2 3))))

(module+ test
  (check-pred Series-ptr? (series-new-u8 "x" '(0 1 255)))
  (check-equal? (series-dtype (series-new-u8 "x" '(0 1 255))) 'uint8)
  (check-pred Series-ptr? (series-new-u8/vec "x" (vector 0 1 255)))
  (check-pred Series-ptr? (series-new-u16 "x" '(0 1 65535)))
  (check-equal? (series-dtype (series-new-u16 "x" '(0 1 65535))) 'uint16)
  (check-pred Series-ptr? (series-new-u16/vec "x" (vector 0 1 65535))))

(define-series-constructors u64 _uint64 0)

(module+ test
  (check-pred Series-ptr? (series-new-u64 "" '(1 2 3)))
  (check-equal? (series-len (series-new-u64 "x" '(0 1 2))) 3)
  (check-equal? (series-dtype (series-new-u64 "x" '(0 1))) 'uint64)
  (check-pred Series-ptr? (series-new-u64/vec "" (vector 1 2 3))))

;; Bools cross the boundary as u8 (0/1).  Racket-side wrappers translate
;; #f/#t to 0/1.
(define-compat series-new-bool/raw
  (_fun _string
        (v : (_list i _uint8))
        (_size = (length v))
        -> _Series-ptr/null)
  #:c-id series_new_bool
  #:wrap (allocator/or-fail series-drop 'series-new-bool))

(define-compat series-new-bool/vec/raw
  (_fun _string
        (v : (_vector i _uint8))
        (_size = (vector-length v))
        -> _Series-ptr/null)
  #:c-id series_new_bool
  #:wrap (allocator/or-fail series-drop 'series-new-bool/vec))

(define-compat series-new-bool/opt/raw
  (_fun _string
        (v : (_list i _uint8))
        (valid : (_list i _uint8))
        (_size = (length v))
        -> _Series-ptr/null)
  #:c-id series_new_opt_bool
  #:wrap (allocator/or-fail series-drop 'series-new-bool))

(define (bool->u8 b) (if b 1 0))

(define (series-new-bool name bools)
  (cond
    [(contains-polars-null? bools)
     (define-values (clean-values valid) (values+valid bools #f))
     (series-new-bool/opt/raw name (map bool->u8 clean-values) valid)]
    [else (series-new-bool/raw name (map bool->u8 bools))]))

(define (series-new-bool/vec name bools)
  (cond
    [(for/or ([value (in-vector bools)])
       (polars-null? value))
     (define-values (clean-values valid) (values+valid (vector->list bools) #f))
     (series-new-bool/opt/raw name (map bool->u8 clean-values) valid)]
    [else
     (series-new-bool/vec/raw name
                              (for/vector #:length (vector-length bools)
                                          ([b (in-vector bools)])
                                (bool->u8 b)))]))

(module+ test
  (check-pred Series-ptr? (series-new-bool "" '(#t #f #t)))
  (check-equal? (series-len (series-new-bool "x" '(#t #f))) 2)
  (check-equal? (series-dtype (series-new-bool "x" '(#t #f))) 'boolean)
  (check-pred Series-ptr? (series-new-bool/vec "" (vector #t #f #t))))

(define-series-constructors str _string "")

(module+ test
  (check-pred Series-ptr? (series-new-str "" '("foo" "bar" "baz" "")))
  (check-equal?
   (series-len (series-new-str "str" '("" "")))
   2)
  (check-exn
   #rx"^series-new-str: operation failed$"
   (lambda ()
     (series-new-str "example" '())))
  (check-exn
   #rx"contract violation"
   (λ ()
     (series-new-str "" '(symbol))))

  (check-pred Series-ptr? (series-new-str/vec "" (vector "foo" "bar" "baz" "")))
  (check-equal?
   (series-name (series-new-str "str" '("" "")))
   "str")
  (check-equal?
   (series-dtype (series-new-str "str" '("" "")))
   'string))

;; Year, Month, Day, Hour, Minute, Second
(define-cstruct _YMDHMS
  ([year _int]
   [month _uint32]
   [day _uint32]
   [hour _uint32]
   [minute _uint32]
   [sescond _uint32]))

(define-cstruct _CompatOptYMDHMS
  ([valid _int32]
   [value _YMDHMS]))

(define (ymdhms->datetime value)
  (datetime (YMDHMS-year value)
            (YMDHMS-month value)
            (YMDHMS-day value)
            (YMDHMS-hour value)
            (YMDHMS-minute value)
            (YMDHMS-sescond value)))

(define (compat-opt-ymdhms->datum o)
  (and (not (zero? (CompatOptYMDHMS-valid o)))
       (ymdhms->datetime (CompatOptYMDHMS-value o))))

(module+ test
  (check-pred YMDHMS?
              (make-YMDHMS 2014 7 11 12 0 0)))

(define default-ymdhms (make-YMDHMS 1970 1 1 0 0 0))

(define-series-constructors ymdhms _YMDHMS default-ymdhms)

(define-compat series-ref-is-null
  (_fun _Series-ptr _size -> _int32))

(define-compat series-ref-i32/raw
  (_fun _Series-ptr _size -> _CompatOptI32)
  #:c-id series_ref_i32)

(define-compat series-ref-i8/raw
  (_fun _Series-ptr _size -> _CompatOptI8)
  #:c-id series_ref_i8)

(define-compat series-ref-i16/raw
  (_fun _Series-ptr _size -> _CompatOptI16)
  #:c-id series_ref_i16)

(define-compat series-ref-i64/raw
  (_fun _Series-ptr _size -> _CompatOptI64)
  #:c-id series_ref_i64)

(define-compat series-ref-u8/raw
  (_fun _Series-ptr _size -> _CompatOptU8)
  #:c-id series_ref_u8)

(define-compat series-ref-u16/raw
  (_fun _Series-ptr _size -> _CompatOptU16)
  #:c-id series_ref_u16)

(define-compat series-ref-u32/raw
  (_fun _Series-ptr _size -> _CompatOptU32)
  #:c-id series_ref_u32)

(define-compat series-ref-u64/raw
  (_fun _Series-ptr _size -> _CompatOptU64)
  #:c-id series_ref_u64)

(define-compat series-ref-f64/raw
  (_fun _Series-ptr _size -> _CompatOptF64)
  #:c-id series_ref_f64)

(define-compat series-ref-f32/raw
  (_fun _Series-ptr _size -> _CompatOptF32)
  #:c-id series_ref_f32)

(define-compat series-ref-bool/raw
  (_fun _Series-ptr _size -> _CompatOptBool)
  #:c-id series_ref_bool)

(define-compat series-ref-str/raw
  (_fun _Series-ptr _size -> _rsstring)
  #:c-id series_ref_str)

(define-compat series-ref-date/raw
  (_fun _Series-ptr _size -> _CompatOptYMD)
  #:c-id series_ref_date)

(define-compat series-ref-duration/raw
  (_fun _Series-ptr _size -> _CompatOptI64)
  #:c-id series_ref_duration)

(define-compat series-ref-time/raw
  (_fun _Series-ptr _size -> _CompatOptI64)
  #:c-id series_ref_time)

(define-compat series-ref-ymdhms/raw
  (_fun _Series-ptr _size -> _CompatOptYMDHMS)
  #:c-id series_ref_ymdhms)

(define (series-ref-unsupported dtype)
  (error 'series-ref "unsupported dtype ~v" dtype))

(define (require-ref-value dtype value)
  (or value (error 'series-ref "could not read non-null value for dtype ~v" dtype)))

(define (left-pad-number value width)
  (define s (number->string value))
  (if (>= (string-length s) width)
      s
      (string-append (make-string (- width (string-length s)) #\0) s)))

(define (nanoseconds->time value)
  (define-values (total-seconds nanosecond) (quotient/remainder value 1000000000))
  (define-values (total-minutes second) (quotient/remainder total-seconds 60))
  (define-values (hour minute) (quotient/remainder total-minutes 60))
  (define base
    (format "~a:~a:~a"
            (left-pad-number hour 2)
            (left-pad-number minute 2)
            (left-pad-number second 2)))
  (iso8601->time
   (if (zero? nanosecond)
       base
       (format "~a.~a" base (left-pad-number nanosecond 9)))))

(define (duration-value->period dtype value)
  (match dtype
    [`(duration nanoseconds) (nanoseconds value)]
    [`(duration microseconds) (microseconds value)]
    [`(duration milliseconds) (milliseconds value)]
    [`(duration ,_) (microseconds value)]
    [_ (error 'series-ref "expected duration dtype, got ~v" dtype)]))

(define-compat series-copy-decimal
  (_fun _Series-ptr _size _size _pointer _size _bytes _size -> _int64))

(define (decimal-ref words i scale)
  (/ (+ (ptr-ref words _uint64 (* 2 i))
        (arithmetic-shift (ptr-ref words _int64 (add1 (* 2 i))) 64))
     (expt 10 scale)))

(define (series-ref-decimal s index scale)
  (with-raw-buffer ([words 2 _uint64])
    (and (zero? (series-copy-decimal s index 1 words 2 #f 0))
         (decimal-ref words 0 scale))))

(define (series-ref s index)
  (unless (exact-nonnegative-integer? index)
    (error 'series-ref "index must be an exact nonnegative integer, got ~v" index))
  (define len (series-len s))
  (unless (< index len)
    (error 'series-ref "index ~a out of bounds for series of length ~a" index len))
  (case (series-ref-is-null s index)
    [(1) polars-null]
    [(0)
     (define dtype (compat-dtype->datum (series-dtype/raw s)))
     (case dtype
       [(int8) (require-ref-value dtype (compat-opt-i8->datum (series-ref-i8/raw s index)))]
       [(int16) (require-ref-value dtype (compat-opt-i16->datum (series-ref-i16/raw s index)))]
       [(int32) (require-ref-value dtype (compat-opt-i32->datum (series-ref-i32/raw s index)))]
       [(int64) (require-ref-value dtype (compat-opt-i64->datum (series-ref-i64/raw s index)))]
       [(uint8) (require-ref-value dtype (compat-opt-u8->datum (series-ref-u8/raw s index)))]
       [(uint16) (require-ref-value dtype (compat-opt-u16->datum (series-ref-u16/raw s index)))]
       [(uint32) (require-ref-value dtype (compat-opt-u32->datum (series-ref-u32/raw s index)))]
       [(uint64) (require-ref-value dtype (compat-opt-u64->datum (series-ref-u64/raw s index)))]
       [(float32) (require-ref-value dtype (compat-opt-f32->datum (series-ref-f32/raw s index)))]
       [(float64) (require-ref-value dtype (compat-opt-f64->datum (series-ref-f64/raw s index)))]
       [(boolean)
        (define value (series-ref-bool/raw s index))
        (when (zero? (CompatOptBool-valid value))
          (error 'series-ref "could not read non-null value for dtype ~v" dtype))
        (compat-opt-bool->datum value)]
       [(string) (require-ref-value dtype (series-ref-str/raw s index))]
       [(categorical enum)
        (string->symbol (require-ref-value dtype (series-ref-str/raw s index)))]
       [(date)
        (require-ref-value dtype
                           (compat-opt-ymd->datum (series-ref-date/raw s index)))]
       [(time)
        (define raw (compat-opt-i64->datum (series-ref-time/raw s index)))
        (require-ref-value dtype (and raw (nanoseconds->time raw)))]
       [else
        (match dtype
          [`(duration ,_)
           (define raw (compat-opt-i64->datum (series-ref-duration/raw s index)))
           (require-ref-value
            dtype
            (and raw (duration-value->period dtype raw)))]
          [`(datetime ,_ ,_)
           (require-ref-value dtype
                              (compat-opt-ymdhms->datum (series-ref-ymdhms/raw s index)))]
          [`(decimal ,_ ,scale) (require-ref-value dtype (series-ref-decimal s index scale))]
          [_ (series-ref-unsupported dtype)])])]
    [else (error 'series-ref "could not read null state at index ~a" index)]))

(module+ test
  (define-values (ex0 ex1)
    (values
     (list (make-YMDHMS 2010 1 1 0 0 0))
     (list (make-YMDHMS 2010 1 1 0 0 0)
           (make-YMDHMS 2011 1 1 0 0 0)
           (make-YMDHMS 2012 1 1 0 0 0))))
  (check-pred Series-ptr?
              (series-new-ymdhms "" ex0))
  (check-equal?
   (series-len (series-new-ymdhms "name" ex1))
   3)
  (check-pred Series-ptr?
              (series-new-ymdhms/vec "" (list->vector ex0)))
  (check-equal?
   (series-len (series-new-ymdhms/vec "name"
                                      (list->vector ex1)))
   3)
  (check-equal?
   (series-dtype (series-new-ymdhms "name" ex1))
   '(datetime milliseconds #f)))

(module+ test
  (define ref-i32 (series-new-i32 "x" (list 10 polars-null -3)))
  (check-equal? (series-len ref-i32) 3)
  (check-equal? (series-null-count ref-i32) 1)
  (check-equal? (series-ref ref-i32 0) 10)
  (check-equal? (series-ref ref-i32 1) polars-null)
  (check-equal? (series-ref ref-i32 2) -3)

  (define ref-i64 (series-new-i64 "x" (list 1099511627776 polars-null)))
  (check-equal? (series-ref ref-i64 0) 1099511627776)
  (check-equal? (series-ref ref-i64 1) polars-null)

  (define ref-i8 (series-new-i8 "x" (list -8 polars-null 12)))
  (check-equal? (series-ref ref-i8 0) -8)
  (check-equal? (series-ref ref-i8 1) polars-null)
  (check-equal? (series-ref ref-i8 2) 12)

  (define ref-i16 (series-new-i16 "x" (list -300 polars-null 1200)))
  (check-equal? (series-ref ref-i16 0) -300)
  (check-equal? (series-ref ref-i16 1) polars-null)
  (check-equal? (series-ref ref-i16 2) 1200)

  (define ref-u32 (series-new-u32 "x" (list 0 polars-null 4294967295)))
  (check-equal? (series-ref ref-u32 0) 0)
  (check-equal? (series-ref ref-u32 1) polars-null)
  (check-equal? (series-ref ref-u32 2) 4294967295)

  (define ref-u8 (series-new-u8 "x" (list 0 polars-null 255)))
  (check-equal? (series-ref ref-u8 0) 0)
  (check-equal? (series-ref ref-u8 1) polars-null)
  (check-equal? (series-ref ref-u8 2) 255)

  (define ref-u16 (series-new-u16 "x" (list 0 polars-null 65535)))
  (check-equal? (series-ref ref-u16 0) 0)
  (check-equal? (series-ref ref-u16 1) polars-null)
  (check-equal? (series-ref ref-u16 2) 65535)

  (define ref-u64 (series-new-u64 "x" (list 0 polars-null 4294967296)))
  (check-equal? (series-ref ref-u64 2) 4294967296)

  (define ref-f32 (series-new-f32 "x" (list 1.5 polars-null 2.25)))
  (check-equal? (series-dtype ref-f32) 'float32)
  (check-equal? (series-null-count ref-f32) 1)
  (check-= (series-ref ref-f32 0) 1.5 1e-6)
  (check-equal? (series-ref ref-f32 1) polars-null)

  (define ref-f64 (series-new-f64 "x" (list 1.5 polars-null 2.25)))
  (check-equal? (series-dtype ref-f64) 'float64)
  (check-equal? (series-null-count ref-f64) 1)
  (check-equal? (series-ref ref-f64 0) 1.5)
  (check-equal? (series-ref ref-f64 1) polars-null)

  (define ref-bool (series-new-bool "x" (list #t #f polars-null)))
  (check-equal? (series-ref ref-bool 0) #t)
  (check-equal? (series-ref ref-bool 1) #f)
  (check-equal? (series-ref ref-bool 2) polars-null)

  (define ref-str (series-new-str "x" (list "alpha" polars-null "")))
  (check-equal? (series-ref ref-str 0) "alpha")
  (check-equal? (series-ref ref-str 1) polars-null)
  (check-equal? (series-ref ref-str 2) "")

  (define ref-dt
    (series-new-ymdhms
     "x"
     (list (make-YMDHMS 2024 1 2 3 4 5)
           polars-null)))
  (check-equal? (series-ref ref-dt 0) (datetime 2024 1 2 3 4 5))
  (check-equal? (series-ref ref-dt 1) polars-null)

  (define ref-date
    (series-cast (series-new-i32 "d" (list 19724 polars-null -1)) 'date))
  (check-equal? (series-dtype ref-date) 'date)
  (check-equal? (series-ref ref-date 0) (date 2024 1 2))
  (check-equal? (series-ref ref-date 1) polars-null)
  (check-equal? (series-ref ref-date 2) (date 1969 12 31))

  (define ref-duration
    (series-cast (series-new-i64 "dur" (list 1500 polars-null -250))
                 '(duration milliseconds)))
  (check-equal? (series-dtype ref-duration) '(duration milliseconds))
  (check-equal? (series-ref ref-duration 0) (milliseconds 1500))
  (check-equal? (series-ref ref-duration 1) polars-null)
  (check-equal? (series-ref ref-duration 2) (milliseconds -250))

  (define ref-time
    (series-cast (series-new-i64 "tod" (list 11045123456789 polars-null 0))
                 'time))
  (check-equal? (series-dtype ref-time) 'time)
  (check-equal? (series-ref ref-time 0) (iso8601->time "03:04:05.123456789"))
  (check-equal? (series-ref ref-time 1) polars-null)
  (check-equal? (series-ref ref-time 2) (iso8601->time "00:00:00"))

  (define ref-vec (series-new-i32/vec "x" (vector 1 polars-null 3)))
  (check-equal? (series-ref ref-vec 1) polars-null)

  (check-exn #rx"nonnegative"
             (lambda () (series-ref ref-i32 -1)))
  (check-exn #rx"out of bounds"
             (lambda () (series-ref ref-i32 3))))

(define-compat series-cast/c
  (_fun _Series-ptr _CompatDType -> _Series-ptr/null)
  #:c-id series_cast
  #:wrap (allocator/or-fail series-drop 'series-cast))

(define-compat series-cast-enum/raw
  (_fun _Series-ptr
        (categories : (_list i _string/utf-8))
        (_size = (length categories))
        -> _Series-ptr/null)
  #:c-id series_cast_enum
  #:wrap (allocator series-drop))

(define (series-cast-enum who s dtype)
  (call/foreign-error who
                      (lambda () (series-cast-enum/raw s (map symbol->string (cdr dtype))))
                      "cannot convert to ~v" dtype))

(define (series-cast s dtype)
  (if (enum-dtype? dtype)
      (series-cast-enum 'series-cast s dtype)
      (series-cast/c s (->compat-dtype dtype))))

(define-compat series-std/raw
  (_fun _Series-ptr _uint8 -> _CompatOptF64)
  #:c-id series_std)

(define (series-std s #:ddof [ddof 1])
  (compat-opt-f64->datum (series-std/raw s ddof)))

(define-compat series-var/raw
  (_fun _Series-ptr _uint8 -> _CompatOptF64)
  #:c-id series_var)

(define (series-var s #:ddof [ddof 1])
  (compat-opt-f64->datum (series-var/raw s ddof)))

(define-compat series-quantile/raw
  (_fun _Series-ptr _double _uint8 -> _CompatOptF64)
  #:c-id series_quantile)

(define (quantile-interpolation->code who interpolation)
  (case interpolation
    [(nearest) 0]
    [(linear) 1]
    [(lower) 2]
    [(higher) 3]
    [(midpoint) 4]
    [else (error who
                 "interpolation must be one of 'nearest 'linear 'lower 'higher 'midpoint, got ~v"
                 interpolation)]))

;; Quantile of a series, computed in f64.  `quantile` is in [0, 1].
;; `#:interpolation` defaults to 'nearest, matching what describe uses.
;; Returns a flonum, or polars-null for an empty/all-null or non-numeric series.
(define (series-quantile s quantile #:interpolation [interpolation 'nearest])
  (unless (and (real? quantile) (<= 0 quantile 1))
    (error 'series-quantile "quantile must be a real in [0, 1], got ~v" quantile))
  (compat-opt-f64->datum
   (series-quantile/raw s (exact->inexact quantile)
                        (quantile-interpolation->code 'series-quantile interpolation))))

(define-syntax-parse-rule (define-series-series-op public-name:id rust-id:id)
  (define-compat public-name
    (_fun _Series-ptr _Series-ptr -> _Series-ptr/null)
    #:c-id rust-id
    #:wrap (allocator/or-fail series-drop 'public-name)))

(define-series-series-op series-eq series_eq)
(define-series-series-op series-ne series_ne)
(define-series-series-op series-gt series_gt)
(define-series-series-op series-ge series_ge)
(define-series-series-op series-lt series_lt)
(define-series-series-op series-le series_le)

(define-series-series-op series-add series_add)
(define-series-series-op series-sub series_sub)
(define-series-series-op series-mul series_mul)
(define-series-series-op series-div series_div)
(define-series-series-op series-mod series_mod)

(define-syntax-parse-rule (define-series-scalar-op public-name:id rust-id:id ctype:id)
  (define-compat public-name
    (_fun _Series-ptr ctype -> _Series-ptr/null)
    #:c-id rust-id
    #:wrap (allocator/or-fail series-drop 'public-name)))

(define-series-scalar-op series-add-i32 series_add_i32 _int32)
(define-series-scalar-op series-sub-i32 series_sub_i32 _int32)
(define-series-scalar-op series-mul-i32 series_mul_i32 _int32)
(define-series-scalar-op series-div-i32 series_div_i32 _int32)
(define-series-scalar-op series-mod-i32 series_mod_i32 _int32)

(define-series-scalar-op series-add-i64 series_add_i64 _int64)
(define-series-scalar-op series-sub-i64 series_sub_i64 _int64)
(define-series-scalar-op series-mul-i64 series_mul_i64 _int64)
(define-series-scalar-op series-div-i64 series_div_i64 _int64)
(define-series-scalar-op series-mod-i64 series_mod_i64 _int64)

(define-series-scalar-op series-add-u32 series_add_u32 _uint32)
(define-series-scalar-op series-sub-u32 series_sub_u32 _uint32)
(define-series-scalar-op series-mul-u32 series_mul_u32 _uint32)
(define-series-scalar-op series-div-u32 series_div_u32 _uint32)
(define-series-scalar-op series-mod-u32 series_mod_u32 _uint32)

(define-series-scalar-op series-add-u64 series_add_u64 _uint64)
(define-series-scalar-op series-sub-u64 series_sub_u64 _uint64)
(define-series-scalar-op series-mul-u64 series_mul_u64 _uint64)
(define-series-scalar-op series-div-u64 series_div_u64 _uint64)
(define-series-scalar-op series-mod-u64 series_mod_u64 _uint64)

(define-series-scalar-op series-add-f64 series_add_f64 _double)
(define-series-scalar-op series-sub-f64 series_sub_f64 _double)
(define-series-scalar-op series-mul-f64 series_mul_f64 _double)
(define-series-scalar-op series-div-f64 series_div_f64 _double)
(define-series-scalar-op series-mod-f64 series_mod_f64 _double)

(module+ test
  (define batch2-x (series-new-i32 "x" (list 1 2 polars-null 4)))
  (define batch2-y (series-new-i32 "y" '(10 20 30 40)))

  ;; cast
  (define x64 (series-cast batch2-x 'float64))
  (check-equal? (series-dtype x64) 'float64)
  (check-equal? (series-ref x64 0) 1.0)
  (check-equal? (series-ref x64 2) polars-null)
  (define xs (series-cast batch2-y 'string))
  (check-equal? (series-dtype xs) 'string)
  (check-equal? (series-ref xs 1) "20")
  (for ([dtype '(int8 int16 uint8 uint16 float32)])
    (define casted (series-cast (series-new-i32 "small" '(1 2 3)) dtype))
    (check-equal? (series-dtype casted) dtype)
    (check-equal? (series-ref casted 1) (if (eq? dtype 'float32) 2.0 2)))
  (check-exn #rx"unsupported cast target"
             (lambda () (series-cast batch2-x '(list int32))))

  (define bears (series-new-str "bears" (list "Polar" polars-null "Brown" "Polar")))
  (define bears/cat (series-cast bears 'categorical))
  (check-equal? (series-dtype bears/cat) 'categorical)
  (check-equal? (for/list ([i 4]) (series-ref bears/cat i)) (list 'Polar polars-null 'Brown 'Polar))
  (define bears/enum (series-cast bears '(enum Polar Panda Brown)))
  (check-equal? (series-dtype bears/enum) '(enum Polar Panda Brown))
  (check-equal? (series-ref bears/enum 2) 'Brown)
  (check-equal? (series-dtype (series-cast (series-head bears 0) '(enum))) '(enum))
  (check-equal? (series-ref (series-cast bears/enum 'string) 0) "Polar")
  (check-exn #rx"^series-cast: cannot convert to '\\(enum Polar Panda\\): .*\\[\"Brown\"\\]"
             (lambda () (series-cast bears '(enum Polar Panda))))
  (check-exn #rx"unsupported cast target '\\(enum Polar Polar\\)"
             (lambda () (series-cast bears '(enum Polar Polar))))
  (check-exn #rx"unsupported cast target '\\(enum \"Polar\"\\)"
             (lambda () (series-cast bears '(enum "Polar"))))
  (check-true (enum-dtype? '(enum)))
  (check-false (enum-dtype? '(enum a . b)))

  ;; reductions
  (define stats (series-new-f64 "s" '(1.0 2.0 3.0 4.0)))
  (check-= (series-var stats #:ddof 1) (/ 5.0 3.0) 1e-9)
  (check-= (series-var stats #:ddof 0) 1.25 1e-9)
  (check-= (series-std stats #:ddof 0) (sqrt 1.25) 1e-9)
  (check-false (series-std (series-new-str "s" '("a" "b"))))

  ;; series-series comparisons
  (define cmp-left (series-new-i32 "a" '(1 2 3 4)))
  (define cmp-right (series-new-i32 "b" '(1 0 3 9)))
  (check-equal? (series-dtype (series-eq cmp-left cmp-right)) 'boolean)
  (check-equal? (series-ref (series-eq cmp-left cmp-right) 0) #t)
  (check-equal? (series-ref (series-ne cmp-left cmp-right) 1) #t)
  (check-equal? (series-ref (series-gt cmp-left cmp-right) 1) #t)
  (check-equal? (series-ref (series-ge cmp-left cmp-right) 2) #t)
  (check-equal? (series-ref (series-lt cmp-left cmp-right) 3) #t)
  (check-equal? (series-ref (series-le cmp-left cmp-right) 0) #t)

  ;; element-wise arithmetic
  (define added (series-add batch2-x batch2-y))
  (check-equal? (series-dtype added) 'int32)
  (check-equal? (series-ref added 0) 11)
  (check-equal? (series-ref added 2) polars-null)
  (check-equal? (series-ref (series-sub batch2-y batch2-x) 1) 18)
  (check-equal? (series-ref (series-mul batch2-x batch2-y) 3) 160)
  (define divided (series-div batch2-y batch2-x))
  (check-equal? (series-dtype divided) 'int32)
  (check-equal? (series-ref divided 1) 10)
  (define divided-f64 (series-div (series-cast batch2-y 'float64)
                                  (series-cast batch2-x 'float64)))
  (check-equal? (series-dtype divided-f64) 'float64)
  (check-equal? (series-ref divided-f64 1) 10.0)
  (check-equal? (series-ref (series-mod batch2-y batch2-x) 3) 0)
  (check-exn #rx"operation failed"
             (lambda ()
               (series-add (series-new-i32 "short" '(1 2))
                           (series-new-i32 "long" '(1 2 3)))))

  ;; scalar arithmetic
  (define add-scalar (series-add-i32 batch2-x 5))
  (check-equal? (series-dtype add-scalar) 'int32)
  (check-equal? (series-ref add-scalar 0) 6)
  (check-equal? (series-ref add-scalar 2) polars-null)
  (check-equal? (series-ref (series-sub-i32 batch2-y 7) 1) 13)
  (check-equal? (series-ref (series-mul-i32 batch2-x 3) 3) 12)
  (check-equal? (series-ref (series-div-i32 batch2-y 10) 1) 2)
  (check-equal? (series-ref (series-mod-i32 batch2-y 7) 3) 5)
  (check-equal? (series-ref (series-add-i64 (series-new-i64 "wide" '(10000000000 2)) 5) 0)
                10000000005)
  (check-equal? (series-ref (series-mul-u32 (series-new-u32 "u" '(2 3 4)) 10) 2)
                40)
  (check-equal? (series-ref (series-sub-u64 (series-new-u64 "u" '(10 20 30)) 7) 1)
                13)
  (check-equal? (series-ref (series-div-f64 (series-new-f64 "f" '(3.0 7.5)) 2.5) 1)
                3.0)
  (check-equal? (series-ref (series-mod-f64 (series-new-f64 "f" '(3.0 7.5)) 2.0) 1)
                1.5)
  (check-exn #rx"operation failed"
             (lambda () (series-add-i32 (series-new-f64 "f" '(1.0 2.0)) 3))))

(define-cpointer-type _DataFrame-ptr)

(define-compat dataframe-drop
  (_fun _DataFrame-ptr -> _void)
  #:wrap (deallocator owned-pointer-arg))

(define-compat dataframe-drop-count
  (_fun -> _size))

(define-compat dataframe-make
  (_fun -> _DataFrame-ptr)
  #:wrap (allocator dataframe-drop))

(define-compat dataframe-empty
  (_fun -> _DataFrame-ptr)
  #:wrap (allocator dataframe-drop))

(define-cstruct _Shape
  ([rows _size]
   [cols _size]))

(define-compat dataframe-shape
  (_fun _DataFrame-ptr
        -> (s : _Shape)
        -> (values (Shape-rows s) (Shape-cols s))))

(define-compat dataframe-height
  (_fun _DataFrame-ptr -> _size))

(define-compat dataframe-width
  (_fun _DataFrame-ptr -> _size))

(define-compat dataframe-head
  (_fun _DataFrame-ptr _size -> _DataFrame-ptr)
  #:wrap (allocator dataframe-drop))

(define-compat dataframe-tail
  (_fun _DataFrame-ptr _size -> _DataFrame-ptr)
  #:wrap (allocator dataframe-drop))

(define-compat dataframe-slice
  (_fun _DataFrame-ptr _int64 _size -> _DataFrame-ptr)
  #:wrap (allocator dataframe-drop))

(define (dataframe-column-names df)
  (for/list ([i (in-range (dataframe-width df))])
    (dataframe-column-name df i)))

(define-compat dataframe-select/c
  (_fun _DataFrame-ptr
        (names : (_list i _string))
        (_size = (length names))
        -> _DataFrame-ptr/null)
  #:c-id dataframe_select
  #:wrap (allocator/or-fail dataframe-drop 'dataframe-select))

(define (dataframe-select df cols)
  (dataframe-select/c df cols))

(define-compat dataframe-drop-columns/c
  (_fun _DataFrame-ptr
        (names : (_list i _string))
        (_size = (length names))
        -> _DataFrame-ptr/null)
  #:c-id dataframe_drop_columns
  #:wrap (allocator/or-fail dataframe-drop 'dataframe-drop-columns))

(define (dataframe-drop-columns df cols)
  (dataframe-drop-columns/c df cols))

(define-compat dataframe-rename
  (_fun _DataFrame-ptr _string _string -> _DataFrame-ptr/null)
  #:wrap (allocator/or-fail dataframe-drop 'dataframe-rename))

(define-compat dataframe-with-column
  (_fun _DataFrame-ptr _Series-ptr -> _DataFrame-ptr/null)
  #:wrap (allocator/or-fail dataframe-drop 'dataframe-with-column))

(define-compat dataframe-hstack
  (_fun _DataFrame-ptr
        (v : (_list i _Series-ptr))
        (_size = (length v))
        -> _DataFrame-ptr/null)
  #:wrap (allocator/or-fail dataframe-drop 'dataframe-hstack))

(define-compat dataframe-new/raw
  (_fun (v : (_list i _Series-ptr))
        (_size = (length v))
        -> _DataFrame-ptr/null)
  #:c-id dataframe_new
  #:wrap (allocator/or-fail dataframe-drop 'dataframe-new))

(define (dataframe-new series-list)
  (dataframe-new/raw series-list))

(define-compat dataframe-column-name
  (_fun _DataFrame-ptr _size -> _rsstring))

(define-compat dataframe-column/raw
  (_fun _DataFrame-ptr _string -> _Series-ptr/null)
  #:c-id dataframe_column
  #:wrap (allocator series-drop))

(define (dataframe-column df name)
  (or (dataframe-column/raw df name)
      (error 'dataframe-column "no column named ~s" name)))

(define-compat dataframe->string
  (_fun _DataFrame-ptr -> _rsstring)
  #:c-id dataframe_to_string)

(define-compat dataframe-write-csv/raw
  (_fun _DataFrame-ptr _string -> _int32)
  #:c-id dataframe_write_csv)

(define (dataframe-write-csv df path)
  (define p (path->complete-string 'dataframe-write-csv path))
  (void (call/foreign-error 'dataframe-write-csv
                            (lambda () (dataframe-write-csv/raw df p))
                            #:ok? zero?
                            "failed to write csv to ~a" path)))

(define-compat dataframe-write-parquet/raw
  (_fun _DataFrame-ptr _string -> _int32)
  #:c-id dataframe_write_parquet)

(define (dataframe-write-parquet df path)
  (define p (path->complete-string 'dataframe-write-parquet path))
  (void (call/foreign-error 'dataframe-write-parquet
                            (lambda () (dataframe-write-parquet/raw df p))
                            #:ok? zero?
                            "failed to write parquet to ~a" path)))

(define-compat dataframe-read-parquet/raw
  (_fun _string -> _DataFrame-ptr/null)
  #:c-id dataframe_read_parquet
  #:wrap (allocator dataframe-drop))

(define (dataframe-read-parquet path)
  (define p (path->complete-string 'dataframe-read-parquet path #:glob? #t))
  (call/foreign-error 'dataframe-read-parquet
                      (lambda () (dataframe-read-parquet/raw p))
                      "failed to read parquet from ~a" path))

(define (glob-pattern? p)
  (regexp-match? #rx"[*?[]" (if (path? p) (path->string p) p)))

(define (path->complete-string who p #:glob? [glob? #f])
  (unless (path-string? p)
    (raise-argument-error who "path-string?" p))
  (define full (path->string (path->complete-path p)))
  (if (and glob? (relative-path? p) (not (directory-exists? full)))
      (path->string
       (build-path (regexp-replace* #rx"[][*?]" (path->string (current-directory)) "[&]") p))
      full))

(define-syntax-parse-rule (define-cmp-scalar name:id ctype:id)
  (define-compat name
    (_fun _Series-ptr ctype -> _Series-ptr/null)
    #:wrap (allocator/or-fail series-drop 'name)))

(define-cmp-scalar series-lt-i32 _int32)
(define-cmp-scalar series-le-i32 _int32)
(define-cmp-scalar series-gt-i32 _int32)
(define-cmp-scalar series-ge-i32 _int32)
(define-cmp-scalar series-eq-i32 _int32)
(define-cmp-scalar series-ne-i32 _int32)

(define-cmp-scalar series-lt-f64 _double)
(define-cmp-scalar series-le-f64 _double)
(define-cmp-scalar series-gt-f64 _double)
(define-cmp-scalar series-ge-f64 _double)
(define-cmp-scalar series-eq-f64 _double)
(define-cmp-scalar series-ne-f64 _double)

(define-cmp-scalar series-eq-str _string)
(define-cmp-scalar series-ne-str _string)

(module+ test
  ;; Use a small dataframe so we can read mask results back via dataframe-filter.
  (define cmp-df
    (dataframe-new
     (list (series-new-i32 "x" '(1 2 3 4 5))
           (series-new-f64 "y" '(1.0 2.0 3.0 4.0 5.0))
           (series-new-str "s" '("a" "b" "a" "b" "c")))))

  (define (count-where mask)
    (dataframe-height (dataframe-filter cmp-df mask)))

  ;; i32: each op returns a boolean Series
  (check-equal? (series-dtype (series-lt-i32 (dataframe-column cmp-df "x") 3))
                'boolean)
  (check-equal? (count-where (series-lt-i32 (dataframe-column cmp-df "x") 3)) 2)
  (check-equal? (count-where (series-le-i32 (dataframe-column cmp-df "x") 3)) 3)
  (check-equal? (count-where (series-ge-i32 (dataframe-column cmp-df "x") 3)) 3)
  (check-equal? (count-where (series-eq-i32 (dataframe-column cmp-df "x") 3)) 1)
  (check-equal? (count-where (series-ne-i32 (dataframe-column cmp-df "x") 3)) 4)

  ;; f64
  (check-equal? (count-where (series-gt-f64 (dataframe-column cmp-df "y") 2.5)) 3)
  (check-equal? (count-where (series-eq-f64 (dataframe-column cmp-df "y") 4.0)) 1)

  ;; str
  (check-equal? (count-where (series-eq-str (dataframe-column cmp-df "s") "a")) 2)
  (check-equal? (count-where (series-ne-str (dataframe-column cmp-df "s") "a")) 3))

(define-compat series-is-null
  (_fun _Series-ptr -> _Series-ptr)
  #:wrap (allocator series-drop))

(define-compat series-is-not-null
  (_fun _Series-ptr -> _Series-ptr)
  #:wrap (allocator series-drop))

(define-compat series-and
  (_fun _Series-ptr _Series-ptr -> _Series-ptr/null)
  #:wrap (allocator/or-fail series-drop 'series-and))

(define-compat series-or
  (_fun _Series-ptr _Series-ptr -> _Series-ptr/null)
  #:wrap (allocator/or-fail series-drop 'series-or))

(define-compat series-xor
  (_fun _Series-ptr _Series-ptr -> _Series-ptr/null)
  #:wrap (allocator/or-fail series-drop 'series-xor))

(define-compat series-not
  (_fun _Series-ptr -> _Series-ptr/null)
  #:wrap (allocator/or-fail series-drop 'series-not))

(module+ test
  (define bool-df
    (dataframe-new
     (list (series-new-i32 "x" '(1 2 3 4 5))
           (series-new-str "s" '("a" "b" "a" "b" "c")))))

  ;; Compose two masks: x > 2 AND s == "a"
  (define m1 (series-gt-i32 (dataframe-column bool-df "x") 2))
  (define m2 (series-eq-str (dataframe-column bool-df "s") "a"))
  (check-equal? (dataframe-height (dataframe-filter bool-df (series-and m1 m2)))
                1) ;; only x=3,s="a"
  (check-equal? (dataframe-height (dataframe-filter bool-df (series-or m1 m2)))
                4) ;; x>2 OR s=="a" : x=1,s="a"; x=3,s="a"; x=3,s="a"; x=4; x=5 -> 4 distinct rows
  (check-equal? (dataframe-height (dataframe-filter bool-df (series-not m1)))
                2) ;; x in {1,2}
  (check-equal? (series-dtype (series-and m1 m2)) 'boolean)

  ;; is-null / is-not-null
  (define non-null-mask (series-is-not-null (dataframe-column bool-df "x")))
  (check-equal? (dataframe-height (dataframe-filter bool-df non-null-mask)) 5)
  (define null-mask (series-is-null (dataframe-column bool-df "x")))
  (check-equal? (dataframe-height (dataframe-filter bool-df null-mask)) 0))

(define-compat dataframe-filter
  (_fun _DataFrame-ptr _Series-ptr -> _DataFrame-ptr/null)
  #:wrap (allocator/or-fail dataframe-drop 'dataframe-filter))

(define-compat dataframe-sort/raw
  (_fun _DataFrame-ptr
        (names : (_list i _string))
        (descending : (_list i _stdbool))
        (nulls-last : (_list i _stdbool))
        (_size = (length names))
        (maintain-order : _stdbool)
        -> _DataFrame-ptr/null)
  #:c-id dataframe_sort_with_options
  #:wrap (allocator dataframe-drop))

(define sort-flags/c
  (flat-named-contract 'sort-flags/c (or/c boolean? (listof boolean?))))

(define (sort-flags-mismatch keys descending nulls-last)
  (define n (if (list? keys) (length keys) 1))
  (or (for/first ([flags (in-list (list descending nulls-last))]
                  [keyword (in-list '("#:descending" "#:nulls-last"))]
                  #:when (and (list? flags) (not (= (length flags) n))))
        (format "the length of ~a (~a) does not match the number of sort keys (~a)"
                keyword (length flags) n))
      #t))

(define (frame-sort/c frame? name)
  (rename-contract
   (->i ([frame frame?] [names (non-empty-listof string?)])
        (#:descending [descending sort-flags/c]
         #:nulls-last [nulls-last sort-flags/c]
         #:maintain-order [maintain-order boolean?])
        #:pre/desc (names descending nulls-last)
        (sort-flags-mismatch names descending nulls-last)
        [result frame?])
   name))

;; the raw bindings read (length names) flags from each list: never pass a shorter one
(define (sort-flags who keyword flags keys)
  (cond
    [(boolean? flags) (for/list ([_ (in-list keys)]) flags)]
    [(= (length flags) (length keys)) flags]
    [else (raise-arguments-error who (format "~a needs one flag per sort key" keyword)
                                 keyword flags
                                 "keys" keys)]))

(define (dataframe-sort df names
                        #:descending [descending #f]
                        #:nulls-last [nulls-last #f]
                        #:maintain-order [maintain-order #f])
  (define flags (sort-flags 'dataframe-sort "#:descending" descending names))
  (define nulls (sort-flags 'dataframe-sort "#:nulls-last" nulls-last names))
  (call/foreign-error 'dataframe-sort
                      (lambda () (dataframe-sort/raw df names flags nulls maintain-order))
                      "failed to sort by ~v" names))

(define-syntax-parse-rule (define-group-by-agg name:id who:id rust-id:id)
  (define-compat name
    (_fun _DataFrame-ptr
          (by : (_list i _string))
          (_size = (length by))
          (agg : (_list i _string))
          (_size = (length agg))
          -> _DataFrame-ptr/null)
    #:c-id rust-id
    #:wrap (allocator/or-fail dataframe-drop 'who)))

(define-group-by-agg dataframe-group-by-sum/c   dataframe-group-by-sum   dataframe_group_by_sum)
(define-group-by-agg dataframe-group-by-mean/c  dataframe-group-by-mean  dataframe_group_by_mean)
(define-group-by-agg dataframe-group-by-min/c   dataframe-group-by-min   dataframe_group_by_min)
(define-group-by-agg dataframe-group-by-max/c   dataframe-group-by-max   dataframe_group_by_max)
(define-group-by-agg dataframe-group-by-count/c dataframe-group-by-count dataframe_group_by_count)

(define (dataframe-group-by-sum df #:by by #:agg agg)
  (dataframe-group-by-sum/c df by agg))
(define (dataframe-group-by-mean df #:by by #:agg agg)
  (dataframe-group-by-mean/c df by agg))
(define (dataframe-group-by-min df #:by by #:agg agg)
  (dataframe-group-by-min/c df by agg))
(define (dataframe-group-by-max df #:by by #:agg agg)
  (dataframe-group-by-max/c df by agg))
(define (dataframe-group-by-count df #:by by #:agg agg)
  (dataframe-group-by-count/c df by agg))

(define-compat dataframe-unique
  (_fun _DataFrame-ptr -> _DataFrame-ptr/null)
  #:wrap (allocator/or-fail dataframe-drop 'dataframe-unique))

(define-compat dataframe-drop-nulls
  (_fun _DataFrame-ptr -> _DataFrame-ptr/null)
  #:wrap (allocator/or-fail dataframe-drop 'dataframe-drop-nulls))

(define compat-join-kind/inner 1)
(define compat-join-kind/left  2)
(define compat-join-kind/outer 3)
(define compat-join-kind/cross 4)
(define compat-join-kind/semi  5)
(define compat-join-kind/anti  6)

(define (join-symbol->code sym)
  (case sym
    [(inner) compat-join-kind/inner]
    [(left)  compat-join-kind/left]
    [(outer full) compat-join-kind/outer]
    [(cross) compat-join-kind/cross]
    [(semi)  compat-join-kind/semi]
    [(anti)  compat-join-kind/anti]
    [else (error 'dataframe-join
                 "unknown join kind ~v (expected 'inner 'left 'outer 'cross 'semi 'anti)"
                 sym)]))

(define-compat dataframe-join/c
  (_fun _DataFrame-ptr _DataFrame-ptr
        (left-on : (_list i _string))
        (_size = (length left-on))
        (right-on : (_list i _string))
        (_size = (length right-on))
        _int32
        -> _DataFrame-ptr/null)
  #:c-id dataframe_join
  #:wrap (allocator/or-fail dataframe-drop 'dataframe-join))

(define (dataframe-join left right
                        #:on [on #f]
                        #:left-on [left-on #f]
                        #:right-on [right-on #f]
                        #:how [how 'inner])
  (define-values (lon ron)
    (cond
      [(eq? how 'cross) (values '() '())]
      [on (values on on)]
      [(and left-on right-on) (values left-on right-on)]
      [else (error 'dataframe-join
                   "must supply #:on, or #:left-on and #:right-on")]))
  (dataframe-join/c left right lon ron (join-symbol->code how)))

(define compat-asof-strategy/backward 1)
(define compat-asof-strategy/forward  2)
(define compat-asof-strategy/nearest  3)

(define compat-asof-tolerance/none    0)
(define compat-asof-tolerance/integer 1)
(define compat-asof-tolerance/float   2)

(define (asof-strategy-symbol->code sym)
  (case sym
    [(backward) compat-asof-strategy/backward]
    [(forward)  compat-asof-strategy/forward]
    [(nearest)  compat-asof-strategy/nearest]
    [else (error 'dataframe-join-asof
                 "unknown asof strategy ~v (expected 'backward 'forward 'nearest)"
                 sym)]))

(define-compat dataframe-join-asof/raw
  (_fun _DataFrame-ptr _DataFrame-ptr _string _string _int32 -> _DataFrame-ptr/null)
  #:c-id dataframe_join_asof
  #:wrap (allocator/or-fail dataframe-drop 'dataframe-join-asof))

(define-compat dataframe-join-asof-options/raw
  (_fun _DataFrame-ptr _DataFrame-ptr _string _string _int32
        (left-by : (_list i _string))
        (_size = (length left-by))
        (right-by : (_list i _string))
        (_size = (length right-by))
        _int32
        _int64
        _double
        -> _DataFrame-ptr/null)
  #:c-id dataframe_join_asof_options
  #:wrap (allocator/or-fail dataframe-drop 'dataframe-join-asof))

(define (asof-tolerance->parts tolerance)
  (cond
    [(not tolerance) (values compat-asof-tolerance/none 0 0.0)]
    [(exact-integer? tolerance)
     (values compat-asof-tolerance/integer tolerance 0.0)]
    [(real? tolerance)
     (values compat-asof-tolerance/float 0 (exact->inexact tolerance))]
    [else
     (error 'dataframe-join-asof
            "tolerance must be #f, an exact integer, or a real number, got ~v"
            tolerance)]))

(define (asof-by-values by left-by right-by)
  (cond
    [by
     (when (or left-by right-by)
       (error 'dataframe-join-asof
              "supply either #:by or #:left-by and #:right-by, not both"))
     (values by by)]
    [(or left-by right-by)
     (unless (and left-by right-by)
       (error 'dataframe-join-asof
              "must supply both #:left-by and #:right-by"))
     (unless (= (length left-by) (length right-by))
       (error 'dataframe-join-asof
              "left-by length ~a does not match right-by length ~a"
              (length left-by)
              (length right-by)))
     (values left-by right-by)]
    [else (values '() '())]))

(define (dataframe-join-asof left right
                             #:on [on #f]
                             #:left-on [left-on #f]
                             #:right-on [right-on #f]
                             #:by [by #f]
                             #:left-by [left-by #f]
                             #:right-by [right-by #f]
                             #:strategy [strategy 'backward]
                             #:tolerance [tolerance #f])
  (define-values (lon ron)
    (cond
      [on (values on on)]
      [(and left-on right-on) (values left-on right-on)]
      [else (error 'dataframe-join-asof
                   "must supply #:on, or #:left-on and #:right-on")]))
  (define-values (lby rby) (asof-by-values by left-by right-by))
  (define-values (tolerance-kind tolerance-integer tolerance-float)
    (asof-tolerance->parts tolerance))
  (dataframe-join-asof-options/raw left right lon ron
                                   (asof-strategy-symbol->code strategy)
                                   lby rby
                                   tolerance-kind
                                   tolerance-integer
                                   tolerance-float))

(define-compat dataframe-vstack
  (_fun _DataFrame-ptr _DataFrame-ptr -> _DataFrame-ptr/null)
  #:wrap (allocator/or-fail dataframe-drop 'dataframe-vstack))

(define compat-pivot-agg/none  0)
(define compat-pivot-agg/first 1)
(define compat-pivot-agg/sum   2)
(define compat-pivot-agg/min   3)
(define compat-pivot-agg/max   4)
(define compat-pivot-agg/mean  5)
(define compat-pivot-agg/count 6)

(define (pivot-agg-symbol->code sym)
  (case sym
    [(none #f) compat-pivot-agg/none]
    [(first)   compat-pivot-agg/first]
    [(sum)     compat-pivot-agg/sum]
    [(min)     compat-pivot-agg/min]
    [(max)     compat-pivot-agg/max]
    [(mean)    compat-pivot-agg/mean]
    [(count)   compat-pivot-agg/count]
    [else (error 'dataframe-pivot
                 "unknown pivot aggregation ~v (expected #f 'first 'sum 'min 'max 'mean 'count)"
                 sym)]))

(define-compat dataframe-pivot/raw
  (_fun _DataFrame-ptr
        (on : (_list i _string))
        (_size = (length on))
        (index : (_list i _string))
        (_size = (length index))
        (values : (_list i _string))
        (_size = (length values))
        _int32
        -> _DataFrame-ptr/null)
  #:c-id dataframe_pivot
  #:wrap (allocator/or-fail dataframe-drop 'dataframe-pivot))

(define (dataframe-pivot df #:on on #:index index #:values values
                         #:agg [agg 'first])
  (dataframe-pivot/raw df on index values (pivot-agg-symbol->code agg)))

(define-compat dataframe-unpivot/raw
  (_fun _DataFrame-ptr
        (on : (_list i _string))
        (_size = (length on))
        (index : (_list i _string))
        (_size = (length index))
        -> _DataFrame-ptr/null)
  #:c-id dataframe_unpivot
  #:wrap (allocator/or-fail dataframe-drop 'dataframe-unpivot))

(define (dataframe-unpivot df #:on on #:index index)
  (dataframe-unpivot/raw df on index))

(define (display-dataframe df [out (current-output-port)])
  (display (dataframe->string df) out)
  (newline out))

(module+ test
  (check-pred DataFrame-ptr? (dataframe-make))
  (check-pred DataFrame-ptr? (dataframe-empty))
  (check-pred void? (dataframe-drop (dataframe-make)))
  (check-pred void? (dataframe-drop (dataframe-empty)))

  (define-values (r c)
    (dataframe-shape (dataframe-make)))
  (check-equal? r 0)
  (check-equal? c 0)

  (define-values (er ec)
    (dataframe-shape (dataframe-empty)))
  (check-equal? er 0)
  (check-equal? ec 0)

  (define example-df
    (dataframe-new
     (list (series-new-str "user" '("alice" "bob" "carol" "dora"))
           (series-new-i32 "score" '(10 25 18 41))
           (series-new-f64 "cost" '(1.2 3.5 2.0 8.4)))))
  (check-pred DataFrame-ptr? example-df)
  (define-values (dr dc) (dataframe-shape example-df))
  (check-equal? dr 4)
  (check-equal? dc 3)
  (check-equal? (dataframe-height example-df) 4)
  (check-equal? (dataframe-width example-df) 3)
  (check-equal? (dataframe-column-name example-df 0) "user")
  (check-equal? (dataframe-column-name example-df 1) "score")
  (check-equal? (dataframe-column-name example-df 2) "cost")

  (define score-col (dataframe-column example-df "score"))
  (check-pred Series-ptr? score-col)
  (check-equal? (series-name score-col) "score")
  (check-equal? (series-dtype score-col) 'int32)
  (check-equal? (series-len score-col) 4)
  (check-equal? (series-sum-i32 score-col) 94)
  (check-exn #rx"^dataframe-column: no column named \"points\"$"
             (lambda () (dataframe-column example-df "points")))

  ;; column-names helper
  (check-equal? (dataframe-column-names example-df)
                '("user" "score" "cost"))

  ;; head / tail / slice
  (check-equal? (dataframe-height (dataframe-head example-df 2)) 2)
  (check-equal? (dataframe-height (dataframe-tail example-df 2)) 2)
  (check-equal? (series-sum-i32
                 (dataframe-column (dataframe-head example-df 2) "score"))
                35) ;; 10 + 25
  (check-equal? (series-sum-i32
                 (dataframe-column (dataframe-tail example-df 2) "score"))
                59) ;; 18 + 41
  (check-equal? (dataframe-height (dataframe-slice example-df 1 2)) 2)
  (check-equal? (series-sum-i32
                 (dataframe-column (dataframe-slice example-df 1 2) "score"))
                43) ;; 25 + 18

  ;; Column ops
  (define just-score (dataframe-select example-df '("score")))
  (check-equal? (dataframe-width just-score) 1)
  (check-equal? (dataframe-column-names just-score) '("score"))

  (define no-cost (dataframe-drop-columns example-df '("cost")))
  (check-equal? (dataframe-column-names no-cost) '("user" "score"))

  (define renamed (dataframe-rename example-df "score" "points"))
  (check-equal? (dataframe-column-names renamed) '("user" "points" "cost"))
  (check-equal? (series-sum-i32 (dataframe-column renamed "points")) 94)

  (define with-bonus
    (dataframe-with-column example-df
                           (series-new-i32 "bonus" '(1 2 3 4))))
  (check-equal? (dataframe-column-names with-bonus)
                '("user" "score" "cost" "bonus"))
  (check-equal? (series-sum-i32 (dataframe-column with-bonus "bonus")) 10)

  ;; with-column replaces if name already exists
  (define replaced
    (dataframe-with-column example-df
                           (series-new-i32 "score" '(0 0 0 0))))
  (check-equal? (dataframe-width replaced) 3) ;; not 4
  (check-equal? (series-sum-i32 (dataframe-column replaced "score")) 0)

  (define stacked-cols
    (dataframe-hstack example-df
                      (list (series-new-i32 "rank" '(4 2 3 1))
                            (series-new-str "tier" '("b" "a" "b" "a")))))
  (check-equal? (dataframe-column-names stacked-cols)
                '("user" "score" "cost" "rank" "tier"))
  (check-equal? (series-sum-i32 (dataframe-column stacked-cols "rank")) 10)
  (check-exn #rx"operation failed"
             (lambda ()
               (dataframe-hstack
                example-df
                (list (series-new-i32 "score" '(1 2 3 4))))))
  (check-exn #rx"operation failed"
             (lambda ()
               (dataframe-hstack
                example-df
                (list (series-new-i32 "too-short" '(1 2))))))

  ;; --- Example 3: filter / sort / group-by ---
  (define ops-df
    (dataframe-new
     (list (series-new-str "group" '("a" "a" "b" "b" "c"))
           (series-new-i32 "value" '(10 25 7 30 18))
           (series-new-f64 "cost"  '(1.2 2.4 0.5 3.1 1.8)))))

  ;; filter value > 15
  (define mask (series-gt-i32 (dataframe-column ops-df "value") 15))
  (check-equal? (series-dtype mask) 'boolean)
  (define filtered (dataframe-filter ops-df mask))
  (check-equal? (dataframe-height filtered) 3) ;; 25, 30, 18
  (check-equal?
   (series-sum-i32 (dataframe-column filtered "value"))
   73)

  ;; sort by group asc, value desc
  (define sorted
    (dataframe-sort ops-df '("group" "value") #:descending '(#f #t)))
  (check-equal? (dataframe-height sorted) 5)
  ;; First row of each group should be the max value within that group.
  ;; (a, 25), (b, 30), (c, 18) -> sum = 73
  ;; Just spot-check the value column came back sorted.
  (let ([vs (dataframe-column sorted "value")])
    (check-equal? (series-len vs) 5))

  ;; group by group, sum value
  (define grouped
    (dataframe-group-by-sum ops-df #:by '("group") #:agg '("value")))
  (check-equal? (dataframe-height grouped) 3)
  (check-equal? (dataframe-width grouped) 2) ;; group + value
  (check-equal?
   (series-sum-i32 (dataframe-column grouped "value_sum"))
   90) ;; 35 + 37 + 18

  ;; Mean / min / max / count
  (define grouped-mean
    (dataframe-group-by-mean ops-df #:by '("group") #:agg '("value")))
  (check-equal? (dataframe-height grouped-mean) 3)
  ;; means: a=17.5, b=18.5, c=18 — sum = 54
  (check-= (series-sum-f64 (dataframe-column grouped-mean "value_mean"))
           54.0 1e-9)

  (define grouped-min
    (dataframe-group-by-min ops-df #:by '("group") #:agg '("value")))
  ;; mins: a=10, b=7, c=18 — sum = 35
  (check-equal? (series-sum-i32 (dataframe-column grouped-min "value_min")) 35)

  (define grouped-max
    (dataframe-group-by-max ops-df #:by '("group") #:agg '("value")))
  ;; maxes: a=25, b=30, c=18 — sum = 73
  (check-equal? (series-sum-i32 (dataframe-column grouped-max "value_max")) 73)

  (define grouped-count
    (dataframe-group-by-count ops-df #:by '("group") #:agg '("value")))
  ;; counts: a=2, b=2, c=1 — total rows = 5
  (check-equal? (dataframe-height grouped-count) 3)

  ;; --- Dedup + null cleanup ---
  (define dup-df
    (dataframe-new
     (list (series-new-i32 "x" '(1 2 1 3 2 1))
           (series-new-str "y" '("a" "b" "a" "c" "b" "a")))))
  (check-equal? (dataframe-height (dataframe-unique dup-df)) 3)

  (define np-df
    (dataframe-new
     (list (series-new-str "name" '("a" "b" "c"))
           (series-new-i64 "score" (list 10 polars-null 30)))))
  (check-equal? (dataframe-height np-df) 3)
  (check-equal? (dataframe-height (dataframe-drop-nulls np-df)) 2)

  ;; --- Joins + vstack ---
  (define users-df
    (dataframe-new
     (list (series-new-i32 "uid" '(1 2 3 4))
           (series-new-str "name" '("alice" "bob" "carol" "dora")))))
  (define orders-df
    (dataframe-new
     (list (series-new-i32 "uid" '(1 2 2 5))
           (series-new-i32 "amount" '(10 20 30 40)))))

  (define inner (dataframe-join users-df orders-df #:on '("uid") #:how 'inner))
  (check-equal? (dataframe-height inner) 3) ;; uid 1,2,2

  (define left (dataframe-join users-df orders-df #:on '("uid") #:how 'left))
  (check-equal? (dataframe-height left) 5) ;; 1,2,2,3 (null),4 (null)

  (define outer (dataframe-join users-df orders-df #:on '("uid") #:how 'outer))
  (check-equal? (dataframe-height outer) 6) ;; 1,2,2,3,4,5

  (define semi (dataframe-join users-df orders-df #:on '("uid") #:how 'semi))
  (check-equal? (dataframe-height semi) 2) ;; uid 1,2
  (check-equal? (dataframe-column-names semi) '("uid" "name"))

  (define anti (dataframe-join users-df orders-df #:on '("uid") #:how 'anti))
  (check-equal? (dataframe-height anti) 2) ;; uid 3,4
  (check-equal? (dataframe-column-names anti) '("uid" "name"))

  (define observations-df
    (dataframe-new
     (list (series-new-i32 "time" '(1 3 5))
           (series-new-i32 "reading" '(100 300 500)))))
  (define calibration-df
    (dataframe-new
     (list (series-new-i32 "time" '(1 2 4))
           (series-new-i32 "offset" '(10 20 40)))))
  (define asof-backward
    (dataframe-join-asof observations-df calibration-df
                         #:on "time"
                         #:strategy 'backward))
  (check-equal? (dataframe-height asof-backward) 3)
  (check-equal? (series-sum-i32 (dataframe-column asof-backward "offset")) 70)

  (define asof-exact
    (dataframe-join-asof observations-df calibration-df
                         #:on "time"
                         #:strategy 'backward
                         #:tolerance 0))
  (check-equal? (series-sum-i32 (dataframe-column asof-exact "offset")) 10)
  (check-equal? (series-null-count (dataframe-column asof-exact "offset")) 2)

  (define grouped-observations-df
    (dataframe-new
     (list (series-new-str "sensor" '("a" "a" "b" "b"))
           (series-new-i32 "time" '(3 5 3 5))
           (series-new-i32 "reading" '(300 500 30 50)))))
  (define grouped-calibration-df
    (dataframe-new
     (list (series-new-str "sensor" '("a" "a" "b" "b"))
           (series-new-i32 "time" '(1 4 1 4))
           (series-new-i32 "offset" '(10 40 100 400)))))
  (define asof-by
    (dataframe-join-asof grouped-observations-df grouped-calibration-df
                         #:on "time"
                         #:by '("sensor")
                         #:strategy 'backward))
  (check-equal? (series-sum-i32 (dataframe-column asof-by "offset")) 550)
  (define asof-by-tolerance
    (dataframe-join-asof grouped-observations-df grouped-calibration-df
                         #:on "time"
                         #:by '("sensor")
                         #:strategy 'backward
                         #:tolerance 0))
  (check-equal? (series-null-count (dataframe-column asof-by-tolerance "offset")) 4)

  (define crossed
    (dataframe-join (dataframe-head users-df 2) (dataframe-head orders-df 2)
                    #:how 'cross))
  (check-equal? (dataframe-height crossed) 4) ;; 2 * 2

  ;; vstack — append rows from a compatible dataframe
  (define more-users
    (dataframe-new
     (list (series-new-i32 "uid" '(5 6))
           (series-new-str "name" '("eve" "frank")))))
  (check-equal? (dataframe-height (dataframe-vstack users-df more-users)) 6)

  ;; --- Pivot / unpivot ---
  (define sales-df
    (dataframe-new
     (list (series-new-str "store" '("a" "a" "b" "b"))
           (series-new-str "quarter" '("q1" "q2" "q1" "q2"))
           (series-new-i32 "sales" '(10 20 30 40)))))
  (define pivoted-sales
    (dataframe-pivot sales-df
                     #:on '("quarter")
                     #:index '("store")
                     #:values '("sales")
                     #:agg 'sum))
  (check-equal? (dataframe-column-names pivoted-sales) '("store" "q1" "q2"))
  (check-equal? (series-sum-i32 (dataframe-column pivoted-sales "q1")) 40)
  (check-equal? (series-sum-i32 (dataframe-column pivoted-sales "q2")) 60)

  (define unpivoted-sales
    (dataframe-unpivot pivoted-sales
                       #:on '("q1" "q2")
                       #:index '("store")))
  (check-equal? (dataframe-height unpivoted-sales) 4)
  (check-equal? (dataframe-column-names unpivoted-sales)
                '("store" "variable" "value"))
  (check-equal? (series-sum-i32 (dataframe-column unpivoted-sales "value")) 100)

  ;; --- Parquet roundtrip ---
  (define csv-df
    (dataframe-new
     (list (series-new-str "city" '("Boston" "New York" "Chicago"))
           (series-new-f64 "population_millions" '(0.65 8.8 2.7))
           (series-new-i32 "founded" '(1630 1624 1837)))))
  (define tmp-parquet
    (build-path (find-system-path 'temp-dir) "rkt-polars-test.parquet"))
  (dataframe-write-parquet csv-df tmp-parquet)
  (define parquet-round (dataframe-read-parquet tmp-parquet))
  (define-values (pr pc) (dataframe-shape parquet-round))
  (check-equal? pr 3)
  (check-equal? pc 3)
  (check-equal? (dataframe-column-names parquet-round)
                '("city" "population_millions" "founded"))
  (check-equal? (series-dtype (dataframe-column parquet-round "founded")) 'int32)
  (check-= (series-sum-f64 (dataframe-column parquet-round "population_millions"))
           12.15
           1e-9)
  (delete-file tmp-parquet))

(module+ test
  (define tmp-dir (find-system-path 'temp-dir))
  (define unwritable (build-path "/" "rkt-polars-no-such-directory-45" "out.csv"))
  (define one-col (dataframe-new (list (series-new-i32 "x" '(1 2 3)))))
  (check-exn #rx"^dataframe-write-csv: failed to write csv to .*: cannot create file: "
             (lambda () (dataframe-write-csv one-col unwritable)))
  (check-exn #rx"^dataframe-write-parquet: failed to write parquet to .*: cannot create file: "
             (lambda () (dataframe-write-parquet one-col unwritable)))

  (define junk (build-path tmp-dir "rkt-polars-junk.bin"))
  (call-with-output-file junk
    (lambda (out) (write-string "this is not parquet" out))
    #:exists 'replace)
  (check-exn #rx"^dataframe-read-parquet: failed to read parquet from .*: .*PAR1"
             (lambda () (dataframe-read-parquet junk)))
  (delete-file junk)
  (check-exn #rx"^dataframe-read-parquet: failed to read parquet from [^:]*: cannot open file: [Nn]o such file"
             (lambda () (dataframe-read-parquet (build-path tmp-dir "rkt-polars-no-such.parquet")))))

(module+ test
  (require (only-in racket/contract exn:fail:contract:blame?)
           (prefix-in contracted: (submod "..")))
  (define (settle!)
    (for ([_ (in-range 4)])
      (collect-garbage)
      (sleep 0.1)))
  (define ((sort-blame? rx) e)
    (and (exn:fail:contract:blame? e) (regexp-match? rx (exn-message e))))
  (define sort-src (dataframe-new (list (series-new-i64 "x" (list 3 polars-null 1))
                                        (series-new-i64 "y" '(1 2 3)))))
  (check-exn (sort-blame? #rx"^dataframe-sort: contract violation.*#:descending \\(2\\) does not match the number of sort keys \\(1\\)")
             (lambda () (contracted:dataframe-sort sort-src '("x") #:descending '(#t #f))))
  (check-exn (sort-blame? #rx"^dataframe-sort: contract violation")
             (lambda () (contracted:dataframe-sort sort-src '())))
  (check-exn (sort-blame? #rx"^dataframe-sort: contract violation")
             (lambda () (contracted:dataframe-sort sort-src "x")))
  (check-exn (sort-blame? #rx"^series-sort: contract violation")
             (lambda () (contracted:series-sort (series-new-i64 "x" '(1)) #:nulls-last '(#t))))
  (check-exn #rx"^dataframe-sort: failed to sort by .*nope"
             (lambda () (contracted:dataframe-sort sort-src '("nope"))))
  (check-equal? (let ([s (contracted:series-sort (dataframe-column sort-src "x") #:nulls-last #t)])
                  (for/list ([i (in-range (series-len s))]) (series-ref s i)))
                (list 1 3 polars-null))

  (settle!)
  (let ([before (dataframe-drop-count)])
    (dataframe-drop (contracted:dataframe-sort sort-src '("x") #:descending #t #:nulls-last #t
                                               #:maintain-order #t))
    (settle!)
    (check-equal? (- (dataframe-drop-count) before) 1))
  (let ([before (dataframe-drop-count)])
    (for ([_ (in-range 20)])
      (contracted:dataframe-sort sort-src '("x" "y") #:nulls-last '(#t #f)))
    (settle!)
    (check >= (- (dataframe-drop-count) before) 10)))

(module+ test
  (define (releases count thunk)
    (define before (count))
    (for ([_ (in-range 20)])
      (thunk))
    (let wait ([tries 0])
      (collect-garbage (if (< tries 4) 'minor 'major))
      (sleep 0.001)
      (when (and (< (- (count) before) 20) (< tries 12))
        (wait (add1 tries))))
    (- (count) before))

  (define (drops-once count drop make)
    (settle!)
    (define before (count))
    (drop (make))
    (settle!)
    (- (count) before))

  (define owned-i32 (series-new-i32 "x" '(3 1 4 1 5)))
  (define owned-i64 (series-new-i64 "w" '(3 1 4 1 5)))
  (define owned-u32 (series-new-u32 "u" '(3 1 4 1 5)))
  (define owned-u64 (series-new-u64 "v" '(3 1 4 1 5)))
  (define owned-f64 (series-new-f64 "f" '(3.0 1.0 4.0 1.0 5.0)))
  (define owned-str (series-new-str "s" '("a" "b" "a" "c" "b")))
  (define owned-bool (series-new-bool "b" '(#t #f #t #t #f)))
  (define owned-enum (series-cast owned-str '(enum a b c)))
  (define owned-stamp (make-YMDHMS 2024 1 2 3 4 5))
  (define owned-frame
    (dataframe-new (list (series-new-i32 "x" '(1 2 1))
                         (series-new-str "k" '("p" "q" "p"))
                         (series-new-i32 "v" '(10 20 30)))))
  (define owned-mask (series-new-bool "m" '(#t #f #t)))
  (define owned-extra (series-new-i32 "e" '(7 8 9)))

  (define series-cases
    (list (list 'series-empty series-empty)
          (list 'series-sort (lambda () (series-sort owned-i32 #:descending #t)))
          (list 'dataframe-column (lambda () (dataframe-column owned-frame "x")))
          (list 'series-head (lambda () (series-head owned-i32 2)))
          (list 'series-tail (lambda () (series-tail owned-i32 2)))
          (list 'series-slice (lambda () (series-slice owned-i32 1 2)))
          (list 'series-reverse (lambda () (series-reverse owned-i32)))
          (list 'series-drop-nulls (lambda () (series-drop-nulls owned-i32)))
          (list 'series-unique (lambda () (series-unique owned-i32)))
          (list 'series-is-null (lambda () (series-is-null owned-i32)))
          (list 'series-is-not-null (lambda () (series-is-not-null owned-i32)))
          (list 'series-and (lambda () (series-and owned-bool owned-bool)))
          (list 'series-or (lambda () (series-or owned-bool owned-bool)))
          (list 'series-xor (lambda () (series-xor owned-bool owned-bool)))
          (list 'series-not (lambda () (series-not owned-bool)))
          (list 'series-lt-i32 (lambda () (series-lt-i32 owned-i32 3)))
          (list 'series-le-i32 (lambda () (series-le-i32 owned-i32 3)))
          (list 'series-gt-i32 (lambda () (series-gt-i32 owned-i32 3)))
          (list 'series-ge-i32 (lambda () (series-ge-i32 owned-i32 3)))
          (list 'series-eq-i32 (lambda () (series-eq-i32 owned-i32 3)))
          (list 'series-ne-i32 (lambda () (series-ne-i32 owned-i32 3)))
          (list 'series-lt-f64 (lambda () (series-lt-f64 owned-f64 3.0)))
          (list 'series-le-f64 (lambda () (series-le-f64 owned-f64 3.0)))
          (list 'series-gt-f64 (lambda () (series-gt-f64 owned-f64 3.0)))
          (list 'series-ge-f64 (lambda () (series-ge-f64 owned-f64 3.0)))
          (list 'series-eq-f64 (lambda () (series-eq-f64 owned-f64 3.0)))
          (list 'series-ne-f64 (lambda () (series-ne-f64 owned-f64 3.0)))
          (list 'series-eq-str (lambda () (series-eq-str owned-str "a")))
          (list 'series-ne-str (lambda () (series-ne-str owned-str "a")))
          (list 'series-cast (lambda () (series-cast owned-i32 'float64)))
          (list 'series-cast/categorical (lambda () (series-cast owned-str 'categorical)))
          (list 'series-cast-enum/raw (lambda () (series-cast owned-str '(enum a b c))))
          (list 'series-enum-categories/raw
                (lambda () (series-enum-categories/raw owned-enum)))
          (list 'series-new-bool (lambda () (series-new-bool "b" '(#t #f))))
          (list 'series-new-bool/opt (lambda () (series-new-bool "b" (list #t polars-null))))
          (list 'series-new-bool/vec (lambda () (series-new-bool/vec "b" (vector #t #f))))))

  (define series-op-cases
    (for/list ([op (in-list (list series-eq series-ne series-gt series-ge series-lt series-le
                                  series-add series-sub series-mul series-div series-mod))])
      (list (object-name op) (lambda () (op owned-i32 owned-i32)))))

  (define scalar-op-cases
    (for*/list ([family (in-list
                         (list (list owned-i32 1 series-add-i32 series-sub-i32 series-mul-i32
                                     series-div-i32 series-mod-i32)
                               (list owned-i64 1 series-add-i64 series-sub-i64 series-mul-i64
                                     series-div-i64 series-mod-i64)
                               (list owned-u32 1 series-add-u32 series-sub-u32 series-mul-u32
                                     series-div-u32 series-mod-u32)
                               (list owned-u64 1 series-add-u64 series-sub-u64 series-mul-u64
                                     series-div-u64 series-mod-u64)
                               (list owned-f64 1.0 series-add-f64 series-sub-f64 series-mul-f64
                                     series-div-f64 series-mod-f64)))]
                [op (in-list (cddr family))])
      (list (object-name op) (lambda () (op (car family) (cadr family))))))

  (define constructor-cases
    (for*/list ([ctor (in-list (list (list series-new-i8 series-new-i8/vec 1)
                                     (list series-new-i16 series-new-i16/vec 1)
                                     (list series-new-i32 series-new-i32/vec 1)
                                     (list series-new-i64 series-new-i64/vec 1)
                                     (list series-new-u8 series-new-u8/vec 1)
                                     (list series-new-u16 series-new-u16/vec 1)
                                     (list series-new-u32 series-new-u32/vec 1)
                                     (list series-new-u64 series-new-u64/vec 1)
                                     (list series-new-f32 series-new-f32/vec 1.0)
                                     (list series-new-f64 series-new-f64/vec 1.0)
                                     (list series-new-str series-new-str/vec "a")
                                     (list series-new-ymdhms series-new-ymdhms/vec owned-stamp)))]
                [shape (in-list '(list opt vec))])
      (define-values (from-list from-vector value) (apply values ctor))
      (list (format "~a ~a" (object-name from-list) shape)
            (case shape
              [(list) (lambda () (from-list "c" (list value value)))]
              [(opt) (lambda () (from-list "c" (list value polars-null)))]
              [(vec) (lambda () (from-vector "c" (vector value value)))]))))

  (define dataframe-cases
    (list (list 'dataframe-make dataframe-make)
          (list 'dataframe-empty dataframe-empty)
          (list 'dataframe-head (lambda () (dataframe-head owned-frame 2)))
          (list 'dataframe-tail (lambda () (dataframe-tail owned-frame 2)))
          (list 'dataframe-slice (lambda () (dataframe-slice owned-frame 1 2)))
          (list 'dataframe-sort (lambda () (dataframe-sort owned-frame '("v"))))
          (list 'dataframe-new (lambda () (dataframe-new (list owned-i32 owned-str))))
          (list 'dataframe-select (lambda () (dataframe-select owned-frame '("x"))))
          (list 'dataframe-drop-columns (lambda () (dataframe-drop-columns owned-frame '("x"))))
          (list 'dataframe-rename (lambda () (dataframe-rename owned-frame "x" "y")))
          (list 'dataframe-with-column (lambda () (dataframe-with-column owned-frame owned-extra)))
          (list 'dataframe-hstack (lambda () (dataframe-hstack owned-frame (list owned-extra))))
          (list 'dataframe-filter (lambda () (dataframe-filter owned-frame owned-mask)))
          (list 'dataframe-unique (lambda () (dataframe-unique owned-frame)))
          (list 'dataframe-drop-nulls (lambda () (dataframe-drop-nulls owned-frame)))
          (list 'dataframe-vstack (lambda () (dataframe-vstack owned-frame owned-frame)))
          (list 'dataframe-join (lambda () (dataframe-join owned-frame owned-frame #:on '("x"))))
          (list 'dataframe-join-asof
                (lambda () (dataframe-join-asof owned-frame owned-frame #:on "v")))
          (list 'dataframe-join-asof/raw
                (lambda () (dataframe-join-asof/raw owned-frame owned-frame "v" "v" 1)))
          (list 'dataframe-pivot
                (lambda () (dataframe-pivot owned-frame #:on '("k") #:index '("x")
                                            #:values '("v") #:agg 'sum)))
          (list 'dataframe-unpivot
                (lambda () (dataframe-unpivot owned-frame #:on '("v") #:index '("x"))))
          (list 'dataframe-group-by-sum
                (lambda () (dataframe-group-by-sum owned-frame #:by '("k") #:agg '("v"))))
          (list 'dataframe-group-by-mean
                (lambda () (dataframe-group-by-mean owned-frame #:by '("k") #:agg '("v"))))
          (list 'dataframe-group-by-min
                (lambda () (dataframe-group-by-min owned-frame #:by '("k") #:agg '("v"))))
          (list 'dataframe-group-by-max
                (lambda () (dataframe-group-by-max owned-frame #:by '("k") #:agg '("v"))))
          (list 'dataframe-group-by-count
                (lambda () (dataframe-group-by-count owned-frame #:by '("k") #:agg '("v"))))))

  (settle!)
  (for ([owned (in-list (append series-cases series-op-cases scalar-op-cases constructor-cases))])
    (check >= (releases series-drop-count (cadr owned)) 10 (format "~a" (car owned))))
  (for ([owned (in-list dataframe-cases)])
    (check >= (releases dataframe-drop-count (cadr owned)) 10 (format "~a" (car owned))))

  (check-equal? (drops-once series-drop-count series-drop
                            (lambda () (series-head owned-i32 2)))
                1)
  (check-equal? (drops-once series-drop-count series-drop
                            (lambda () (series-cast owned-i32 'float64)))
                1)
  (check-equal? (drops-once series-drop-count series-drop
                            (lambda () (series-new-i32 "c" '(1 2))))
                1)
  (check-equal? (drops-once series-drop-count series-drop
                            (lambda () (series-cast owned-str '(enum a b c))))
                1)
  (check-equal? (drops-once dataframe-drop-count dataframe-drop
                            (lambda () (dataframe-hstack owned-frame (list owned-extra))))
                1)
  (check-equal? (drops-once dataframe-drop-count dataframe-drop
                            (lambda () (dataframe-pivot owned-frame #:on '("k") #:index '("x")
                                                        #:values '("v"))))
                1)

  (check-exn #rx"^series-not: operation failed$" (lambda () (series-not owned-i32)))
  (check-exn #rx"^series-and: operation failed$" (lambda () (series-and owned-i32 owned-bool)))
  (check-exn #rx"^series-lt-i32: operation failed$" (lambda () (series-lt-i32 owned-f64 1)))
  (check-exn #rx"^series-eq-str: operation failed$" (lambda () (series-eq-str owned-i32 "a")))
  (check-exn #rx"^series-add-i32: operation failed$" (lambda () (series-add-i32 owned-f64 1)))
  (check-exn #rx"^series-new-i32/vec: operation failed$"
             (lambda () (series-new-i32/vec "c" (vector))))
  (check-exn #rx"^dataframe-new: operation failed$"
             (lambda () (dataframe-new (list owned-i32 (series-head owned-i32 2)))))
  (check-exn #rx"^dataframe-drop-columns: operation failed$"
             (lambda () (dataframe-drop-columns owned-frame '("nope"))))
  (check-exn #rx"^dataframe-vstack: operation failed$"
             (lambda () (dataframe-vstack owned-frame (dataframe-select owned-frame '("x")))))
  (check-exn #rx"^dataframe-filter: operation failed$"
             (lambda () (dataframe-filter owned-frame owned-i32)))
  (check-exn #rx"^dataframe-join-asof: operation failed$"
             (lambda () (dataframe-join-asof owned-frame owned-frame #:on "nope"))))

(module+ test
  (require (only-in racket/path path-has-extension?))
  (define-runtime-path private-dir ".")

  (define owned-drops
    (hash '_Series-ptr 'series-drop '_Series-ptr/null 'series-drop
          '_DataFrame-ptr 'dataframe-drop '_DataFrame-ptr/null 'dataframe-drop
          '_Expr-ptr 'expr-drop '_Expr-ptr/null 'expr-drop
          '_LazyFrame-ptr 'lazyframe-drop '_LazyFrame-ptr/null 'lazyframe-drop))

  (define (compat-forms v)
    (cond
      [(and (pair? v) (eq? (car v) 'define-compat)) (list v)]
      [(pair? v) (append (compat-forms (car v)) (compat-forms (cdr v)))]
      [else '()]))

  (define (result-type signature)
    (match (memq '-> signature)
      [(list* '-> (list _ ': type) _) type]
      [(list* '-> type _) type]
      [_ #f]))

  (define (releases-result? form)
    (match form
      [(list* 'define-compat _ (list* '_fun signature) options)
       (define type (result-type signature))
       (define drop (hash-ref owned-drops type #f))
       (cond
         [(eq? type '_pointer) #f]
         [drop (match (memq '#:wrap options)
                 [(list* _ (list* (or 'allocator 'allocator/or-fail) (== drop) _) _) #t]
                 [_ #f])]
         [else #t])]
      [_ #t]))

  (define bindings
    (for*/list ([file (in-directory private-dir)]
                #:when (path-has-extension? file #".rkt")
                [form (in-list (compat-forms
                                (parameterize ([read-accept-reader #t] [read-accept-lang #t])
                                  (call-with-input-file file read))))])
      form))
  (define (compat-form . parts) (cons 'define-compat parts))
  (check-true (releases-result?
               (compat-form 'good '(_fun _string -> _DataFrame-ptr/null)
                            '#:wrap '(allocator dataframe-drop))))
  (check-false (releases-result?
                (compat-form 'swapped '(_fun _string -> _DataFrame-ptr/null)
                             '#:wrap '(allocator lazyframe-drop))))
  (check-false (releases-result?
                (compat-form 'unwrapped '(_fun _string -> _LazyFrame-ptr/null))))
  (check > (length bindings) 200)
  (check-equal? (for/list ([form (in-list bindings)]
                           #:unless (releases-result? form))
                  (cadr form))
                '()))
