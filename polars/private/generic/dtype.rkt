#lang racket/base

;; dtype aliases, inference, and the dtype -> series-constructor map shared by
;; the `series` smart constructor (core) and `const-series` (operators).

(require racket/match
         (only-in gregor datetime?)
         polars/private/foreign
         polars/private/series
         syntax/parse/define
         (for-syntax racket/base syntax/parse))

(provide normalize-dtype dtype->constructor infer-dtype coerce-elements
         numeric-dtypes numeric-dtype? temporal-dtype?
         dtype-spec? define-enum)

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
                                   date time datetime categorical))])
    (hash-set aliases canonical canonical)))

(define (dtype-spec? v)
  (match v
    [(? symbol?) (hash-has-key? dtype-aliases v)]
    [(list* (or 'datetime 'duration)
            (or #f 'none 'nanoseconds 'microseconds 'milliseconds)
            (or '() (list #f)))
     #t]
    [_ (enum-dtype? v)]))

(define (normalize-dtype dt)
  (cond
    [(not (dtype-spec? dt)) (error 'series "unsupported dtype ~v" dt)]
    [(symbol? dt) (hash-ref dtype-aliases dt)]
    [else dt]))

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
    [(andmap symbol? vals) 'categorical]
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
       [(or 'categorical (? enum-dtype?))
        (define strings (if vec? series-new-str/vec series-new-str))
        (lambda (name elements)
          (define s (strings name elements))
          (begin0 (if (eq? canonical 'categorical)
                      (series-cast s 'categorical)
                      (series-cast-enum 'series s canonical))
                  (series-drop s)))]
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

(module+ test
  (require rackunit
           syntax/macro-testing)

  (define-enum log-levels debug info warning error)
  (check-equal? log-levels '(enum debug info warning error))
  (check-true (enum-dtype? log-levels))

  (define-enum sizes small "Very High")
  (check-equal? sizes '(enum small |Very High|))

  (check-exn #rx"duplicate enum category"
             (lambda () (convert-compile-time-error (let () (define-enum twice a b a) twice))))
  (check-exn #rx"duplicate enum category"
             (lambda () (convert-compile-time-error (let () (define-enum twice a "a") twice))))
  (check-exn #rx"expected more terms"
             (lambda () (convert-compile-time-error (let () (define-enum none) none)))))
