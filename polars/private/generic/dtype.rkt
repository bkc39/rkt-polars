#lang racket/base

;; dtype aliases, inference, and the dtype -> series-constructor map shared by
;; the `series` smart constructor (core) and `const-series` (operators).

(require racket/match
         (only-in racket/contract flat-contract-with-explanation raise-blame-error)
         (only-in racket/contract/base
                  and/c contract-name flat-contract-predicate integer-in or/c rename-contract
                  unsupplied-arg?)
         (only-in racket/function negate)
         (only-in racket/sequence sequence-length)
         (only-in polars/private/c-integer
                  int16/c int32/c int64-min int64/c int8/c uint16/c uint32/c uint64-max uint64/c
                  uint8/c)
         polars/private/foreign
         (only-in polars/private/resource with-release)
         polars/private/series
         (only-in polars/private/temporal temporal-values-dtype)
         syntax/parse/define
         (for-syntax racket/base syntax/parse))

(provide normalize-dtype dtype->constructor infer-dtype coerce-elements
         numeric-dtypes numeric-dtype? temporal-dtype?
         dtype-spec? define-enum series-elements/c)

(begin-for-syntax
  (define-syntax-class enum-category
    #:description "an enum category (an identifier or a string)"
    (pattern name:id #:with symbol #'name)
    (pattern text:str
             #:with symbol (datum->syntax #'text (string->symbol (syntax-e #'text)) #'text))))

(define-syntax-parse-rule (define-enum name:id category:enum-category ...+)
  #:fail-when (check-duplicate-identifier (syntax->list #'(category.symbol ...)))
              "duplicate enum category"
  (define name '(enum category.symbol ...)))

;; Accept both the short constructor spellings (i32, f64, str, bool) and the
;; canonical symbols returned by series-dtype (int32, float64, string,
;; boolean).  Maps everything to a canonical symbol.
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

(define (infer-dtype elements)
  (define all (if (vector? elements) (vector->list elements) elements))
  (define vals
    (for/list ([x (in-list all)]
               #:unless (polars-null? x))
      x))
  ;; Defaults mirror Polars' inference for a Python list: integers -> Int64,
  ;; reals -> Float64, strings -> String, booleans -> Boolean.
  (cond
    [(null? vals) 'null]
    [(andmap boolean? vals) 'boolean]
    [(andmap exact-integer? vals) (if (andmap int64/c vals) 'int64 'uint64)]
    [(andmap real? vals) 'float64]              ; mixed int/float -> float64
    [(andmap string? vals) 'string]
    [(andmap symbol? vals) 'categorical]
    [(temporal-values-dtype vals)]
    [else (error 'series
                 "cannot infer a dtype from elements; pass #:dtype explicitly")]))

(define integer-dtype-ranges
  (for/hash ([dtype (in-list '(int8 int16 int32 int64 uint8 uint16 uint32 uint64))]
             [range (in-list (list int8/c int16/c int32/c int64/c uint8/c uint16/c uint32/c
                                   uint64/c))])
    (values dtype (rename-contract range (string->symbol (format "~a/c" dtype))))))

(define series-integer/c (integer-in int64-min uint64-max))

(define elements/c (or/c list? vector?))

(define (element-list elements)
  (if (vector? elements) (vector->list elements) elements))

(define ((refuse-element elements expected given) blame)
  (raise-blame-error blame elements '(expected: "~a" given: "~e") expected given))

(define (inferred-integers-explanation elements)
  (define present (filter (negate polars-null?) (element-list elements)))
  (define integers? (andmap exact-integer? present))
  (define wide (and integers? (memf (negate series-integer/c) present)))
  (cond
    [(not integers?) #t]
    [wide (refuse-element elements (contract-name series-integer/c) (car wide))]
    [(or (andmap int64/c present) (andmap uint64/c present)) #t]
    [else (refuse-element elements
                          (format "~a, beside a negative integer" (contract-name int64/c))
                          (findf (negate int64/c) present))]))

(define inferred-integers/c
  (flat-contract-with-explanation inferred-integers-explanation #:name 'series-elements/c))

(define ((ranged-explanation range) elements)
  (define in-range? (flat-contract-predicate range))
  (match (memf (lambda (x) (not (or (polars-null? x) (in-range? x)))) (element-list elements))
    [#f #t]
    [(cons x _) (refuse-element elements (contract-name range) x)]))

(define (series-elements/c dtype)
  (cond
    [(or (unsupplied-arg? dtype) (not dtype)) (and/c elements/c inferred-integers/c)]
    [(and (symbol? dtype)
          (hash-ref integer-dtype-ranges (hash-ref dtype-aliases dtype #f) #f))
     => (lambda (range)
          (and/c elements/c
                 (flat-contract-with-explanation (ranged-explanation range)
                                                 #:name 'series-elements/c)))]
    [else elements/c]))

(define (dtype->constructor canonical vec?)
  (case canonical
    [(int8)    (if vec? series-new-i8/vec  series-new-i8)]
    [(int16)   (if vec? series-new-i16/vec series-new-i16)]
    [(int32)   (if vec? series-new-i32/vec series-new-i32)]
    [(int64)   (if vec? series-new-i64/vec series-new-i64)]
    [(uint8)   (if vec? series-new-u8/vec  series-new-u8)]
    [(uint16)  (if vec? series-new-u16/vec series-new-u16)]
    [(uint32)  (if vec? series-new-u32/vec series-new-u32)]
    [(uint64)  (if vec? series-new-u64/vec series-new-u64)]
    [(float32) (if vec? series-new-f32/vec series-new-f32)]
    [(float64) (if vec? series-new-f64/vec series-new-f64)]
    [(boolean) (if vec? series-new-bool/vec series-new-bool)]
    [(string)  (if vec? series-new-str/vec series-new-str)]
    [(null)
     (lambda (name elements)
       (unless (for/and ([x elements]) (polars-null? x))
         (raise-arguments-error 'series "a 'null series holds only polars-null"
                                "elements" elements))
       (series-new-null name (sequence-length elements)))]
    [else
     (match canonical
       [(or 'date 'time 'datetime `(datetime . ,_) `(duration . ,_))
        (lambda (name elements) (series-new-temporal 'series name elements canonical))]
       [(or 'categorical (? enum-dtype?))
        (define strings (if vec? series-new-str/vec series-new-str))
        (lambda (name elements)
          (with-release ([s (strings name elements) series-drop])
            (if (eq? canonical 'categorical)
                (series-cast s 'categorical)
                (series-cast-enum 'series s canonical))))]
       [_ (error 'series "no constructor for dtype ~v" canonical)])]))

;; The float constructors want flonums; accept exact reals too by coercing,
;; so (series '(1 2 3) #:dtype 'f64) does what the user means.
(define (coerce-elements canonical elements)
  (define (coerce convert)
    (if (vector? elements)
        (for/vector #:length (vector-length elements) ([x (in-vector elements)]) (convert x))
        (map convert elements)))
  (match canonical
    [(or 'float32 'float64)
     (coerce (lambda (x) (if (and (not (polars-null? x)) (exact? x)) (exact->inexact x) x)))]
    [(or 'categorical (? enum-dtype?))
     (coerce (lambda (x) (if (symbol? x) (symbol->string x) x)))]
    [_ elements]))

(define numeric-dtypes
  '(int8 int16 int32 int64 uint8 uint16 uint32 uint64 float32 float64))

(define (numeric-dtype? dt) (and (symbol? dt) (memq dt numeric-dtypes) #t))

(define (temporal-dtype? dt)
  (match dt
    [(or 'date 'time (list 'datetime _ _) (list 'duration _)) #t]
    [_ #f]))
