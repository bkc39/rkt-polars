#lang racket/base

(require ffi/unsafe
         (only-in gregor date)
         (only-in racket/contract/base and/c flat-contract-predicate flat-named-contract not/c)
         (only-in racket/contract flat-contract-with-explanation raise-blame-error)
         racket/match
         (only-in racket/list check-duplicates)
         (only-in racket/string non-empty-string?))

(provide (all-defined-out))

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
                     'zoned))]
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

(define time-zone-name/c
  (flat-named-contract 'time-zone-name/c (and/c non-empty-string? (not/c #rx"\0"))))

(define datetime-zone/c
  (flat-contract-with-explanation
   (lambda (v)
     (match v
       [(list 'datetime _ (and (? string?) (not (? (flat-contract-predicate time-zone-name/c)))
                               zone))
        (lambda (blame)
          (raise-blame-error blame zone '(expected: "time-zone-name/c" given: "~e") zone))]
       [_ #t]))
   #:name 'datetime-zone/c))

(define (zoned-datetime-dtype? v)
  (match v
    [(list 'datetime (or 'nanoseconds 'microseconds 'milliseconds) (? string? zone))
     (positive? (string-length zone))]
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

(define dtype-short-names
  (hash 'i8 'int8   'i16 'int16   'i32 'int32   'i64 'int64
        'u8 'uint8  'u16 'uint16  'u32 'uint32  'u64 'uint64
        'f32 'float32 'f64 'float64 'bool 'boolean 'str 'string))

;; a naive datetime only: a zoned one crosses through the _datetime_tz entry
;; points, which take its zone's name
(define (->compat-dtype dtype)
  (match dtype
    [(? symbol?)
     (define canonical (hash-ref dtype-short-names dtype dtype))
     (define tag (simple-dtype-tag canonical))
     (case canonical
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
    [(list* 'datetime unit (or '() (list #f)))
     (make-CompatDType compat-dtype-tag/datetime (time-unit-symbol->code unit) 0 0)]
    [(cons 'duration (cons unit _))
     (make-CompatDType compat-dtype-tag/duration (time-unit-symbol->code unit) 0 0)]
    [_ (error '->compat-dtype "unsupported cast target ~v" dtype)]))

(define dtype-aliases
  (for/fold ([aliases dtype-short-names])
            ([canonical (in-list '(int8 int16 int32 int64 uint8 uint16 uint32 uint64
                                   float32 float64 boolean string
                                   date time datetime categorical null))])
    (hash-set aliases canonical canonical)))

(define (dtype-spec? v)
  (match v
    [(? symbol?) (hash-has-key? dtype-aliases v)]
    [(list* (or 'datetime 'duration)
            (or #f 'none 'nanoseconds 'microseconds 'milliseconds)
            (or '() (list #f)))
     #t]
    [_ (or (enum-dtype? v) (zoned-datetime-dtype? v))]))

(define (normalize-dtype dt)
  (cond
    [(not (dtype-spec? dt)) (error 'series "unsupported dtype ~v" dt)]
    [(symbol? dt) (hash-ref dtype-aliases dt)]
    [else dt]))
