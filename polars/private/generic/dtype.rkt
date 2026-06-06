#lang racket/base

;; dtype aliases, inference, and the dtype -> series-constructor map shared by
;; the `series` smart constructor (core) and `const-series` (operators).

(require racket/match
         (only-in gregor datetime?)
         polars/private/foreign
         polars/private/series)

(provide normalize-dtype dtype->constructor infer-dtype coerce-elements
         numeric-dtypes numeric-dtype?)

;; Accept both the short constructor spellings (i32, f64, str, bool) and the
;; canonical symbols returned by series-dtype (int32, float64, string,
;; boolean).  Maps everything to a canonical symbol.
(define dtype-aliases
  (hash 'i8 'int8    'int8 'int8
        'i16 'int16   'int16 'int16
        'i32 'int32   'int32 'int32
        'i64 'int64   'int64 'int64
        'u8 'uint8    'uint8 'uint8
        'u16 'uint16  'uint16 'uint16
        'u32 'uint32  'uint32 'uint32
        'u64 'uint64  'uint64 'uint64
        'f32 'float32 'float32 'float32
        'f64 'float64 'float64 'float64
        'bool 'boolean 'boolean 'boolean
        'str 'string   'string 'string
        'date 'date
        'time 'time
        'datetime 'datetime))

(define (normalize-dtype dt)
  (cond
    [(and (symbol? dt) (hash-ref dtype-aliases dt #f)) => values]
    [(and (pair? dt) (memq (car dt) '(datetime duration))) dt]
    [else (error 'series "unsupported dtype ~v" dt)]))

(define (infer-dtype elements)
  (define vals
    (for/list ([x (in-list (if (vector? elements)
                               (vector->list elements)
                               elements))]
               #:unless (polars-null? x))
      x))
  ;; Defaults mirror Polars' inference for a Python list: integers -> Int64,
  ;; reals -> Float64, strings -> String, booleans -> Boolean.
  (cond
    [(null? vals) 'int64]
    [(andmap boolean? vals) 'boolean]
    [(andmap exact-integer? vals) 'int64]
    [(andmap real? vals) 'float64]              ; mixed int/float -> float64
    [(andmap string? vals) 'string]
    [(andmap datetime? vals) 'datetime]
    [else (error 'series
                 "cannot infer a dtype from elements; pass #:dtype explicitly")]))

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
    [else
     (match canonical
       [(or 'datetime `(datetime . ,_))
        (if vec? series-new-datetime/vec series-new-datetime)]
       [_ (error 'series "no constructor for dtype ~v" canonical)])]))

;; The float constructors want flonums; accept exact reals too by coercing,
;; so (series '(1 2 3) #:dtype 'f64) does what the user means.
(define (coerce-elements canonical elements)
  (case canonical
    [(float32 float64)
     (define (->fl x) (if (and (not (polars-null? x)) (exact? x))
                          (exact->inexact x)
                          x))
     (if (vector? elements)
         (for/vector #:length (vector-length elements) ([x (in-vector elements)]) (->fl x))
         (map ->fl elements))]
    [else elements]))

(define numeric-dtypes
  '(int8 int16 int32 int64 uint8 uint16 uint32 uint64 float32 float64))

(define (numeric-dtype? dt) (and (symbol? dt) (memq dt numeric-dtypes) #t))
