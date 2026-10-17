#lang racket/base

(require (only-in racket/list make-list)
         (only-in racket/match match match*)
         (only-in polars/private/foreign
                  call/foreign-error dataframe-column dataframe-drop dataframe-new enum-dtype?
                  polars-null? series-dtype series-len series-name)
         (only-in polars/private/expr
                  dataframe-lazy expr-alias expr-all lazyframe-collect/raw lazyframe-select lit/who)
         (only-in polars/private/generic/core null-series? series? wrap-series)
         (only-in polars/private/generic/dtype
                  coerce-elements dtype->constructor numeric-dtype? temporal-dtype?)
         (only-in polars/private/resource with-release)
         (only-in polars/private/series series-repeat-temporal)
         (only-in polars/private/temporal temporal-value-dtype))

(provide const-series
         expression-form-op
         logical-operand
         operand-series
         series-through-expr)

(define (const-series who dt n value)
  (wrap-series
   (if (temporal-dtype? dt)
       (series-repeat-temporal who "" value n dt)
       ((dtype->constructor dt #f) "" (coerce-elements dt (make-list n value))))))

(define integer-ranges
  (for*/hasheq ([bits (in-list '(8 16 32 64))]
                [kind (in-list '(int uint))])
    (define limit (expt 2 bits))
    (values (string->symbol (format "~a~a" kind bits))
            (match kind
              ['int (cons (- (quotient limit 2)) (sub1 (quotient limit 2)))]
              ['uint (cons 0 (sub1 limit))]))))

(define (in-range-of dt v)
  (match (hash-ref integer-ranges dt #f)
    [(cons low high) (<= low v high)]
    [#f #f]))

(define (int64-value? v)
  (and (exact-integer? v) (in-range-of 'int64 v)))

(define (non-integer-real? v)
  (and (real? v) (not (exact-integer? v))))

(define (literal-value? v)
  (or (boolean? v) (int64-value? v) (non-integer-real? v)
      (string? v) (symbol? v) (polars-null? v) (and (temporal-value-dtype v) #t)))

(struct constant (dtype value))

(define (plain-operand dt v)
  (cond
    [(temporal-value-dtype v) => (lambda (value-dtype) (constant value-dtype v))]
    [(and (memq dt '(float32 float64)) (real? v)) (constant dt (exact->inexact v))]
    [(and (exact-integer? v) (in-range-of dt v)) (constant dt v)]
    [(and (numeric-dtype? dt) (non-integer-real? v)) (constant 'float64 (exact->inexact v))]
    [(and (eq? dt 'boolean) (boolean? v)) (constant dt v)]
    [(and (memq dt '(string categorical)) (string? v)) (constant dt v)]
    [(and (memq dt '(string categorical)) (symbol? v)) (constant dt (symbol->string v))]
    [else #f]))

(define (expression-operand? dt v)
  (match dt
    [_ #:when (polars-null? v) #t]
    ['null (literal-value? v)]
    [(? enum-dtype?) (or (string? v) (symbol? v))]
    [(list 'decimal _ _) (or (int64-value? v) (non-integer-real? v))]
    [(or 'int8 'int16 'int32 'int64) (and (int64-value? v) (not (in-range-of dt v)))]
    [(or 'uint8 'uint16 'uint32 'uint64)
     (and (int64-value? v) (not (negative? v)) (not (in-range-of dt v)))]
    [_ #f]))

(define (operand-series who s other)
  (define dt (series-dtype s))
  (define o
    (match (if (series? other) other (plain-operand dt other))
      [(? series? o) o]
      [(constant dtype value) (const-series who dtype (series-len s) value)]
      [#f (raise-arguments-error who "the value cannot be an element of a series of this dtype"
                                 "value" other "series dtype" dt)]))
  (match* (dt (series-dtype o))
    [((list 'datetime _ zone) (list 'datetime _ other-zone))
     #:when (not (equal? zone other-zone))
     (raise-arguments-error who "datetimes in different time zones"
                            "series dtype" dt "other dtype" (series-dtype o))]
    [(_ _) o]))

(define (logical-operand who s other)
  (cond
    [(series? other) other]
    [(or (boolean? other) (polars-null? other)) (const-series who 'boolean (series-len s) other)]
    [else (raise-argument-error who "(or/c series? boolean? polars-null?)" other)]))

(define (series-through-expr who s build)
  (define name (series-name s))
  (with-release ([frame (dataframe-new (list s)) dataframe-drop]
                 [out (call/foreign-error
                       who
                       (lambda ()
                         (lazyframe-collect/raw
                          (lazyframe-select (dataframe-lazy frame)
                                            (list (expr-alias (build (expr-all)) name))))))
                      dataframe-drop])
    (wrap-series (dataframe-column out name))))

(define (expression-form-op who expr-op a b)
  (define (expression-form? s v)
    (and (series? s) (not (series? v)) (expression-operand? (series-dtype s) v)))
  (cond
    [(expression-form? a b)
     (define v (lit/who who b))
     (series-through-expr who a (lambda (e) (expr-op e v)))]
    [(expression-form? b a)
     (define v (lit/who who a))
     (series-through-expr who b (lambda (e) (expr-op v e)))]
    [else #f]))
