#lang racket/base

(require (only-in racket/list make-list)
         (only-in racket/match match match*)
         polars/private/foreign
         polars/private/expr
         polars/private/generic/core
         polars/private/generic/dtype
         (only-in polars/private/resource with-release)
         (only-in polars/private/series series-repeat-temporal)
         (only-in polars/private/temporal temporal-value-dtype))

(provide const-series
         failure-cause
         logical-operand
         expression-form-op
         operand-series
         raise-cause
         series-through-expr)

(define (const-series dt n value)
  (wrap-series
   (if (temporal-dtype? dt)
       (series-repeat-temporal 'series "" value n dt)
       ((dtype->constructor dt #f) "" (coerce-elements dt (make-list n value))))))

(define integer-ranges
  (for/hash ([(dt bits) (in-hash #hasheq((int8 . 8) (int16 . 16) (int32 . 32) (int64 . 64)))])
    (values dt (cons (- (expt 2 (sub1 bits))) (sub1 (expt 2 (sub1 bits)))))))

(define unsigned-ranges
  (for/hash ([(dt bits) (in-hash #hasheq((uint8 . 8) (uint16 . 16) (uint32 . 32) (uint64 . 64)))])
    (values dt (cons 0 (sub1 (expt 2 bits))))))

(define (in-range-of dt v)
  (match (or (hash-ref integer-ranges dt #f) (hash-ref unsigned-ranges dt #f))
    [(cons low high) (<= low v high)]
    [#f #f]))

(define (constructible-dtype? dt)
  (or (numeric-dtype? dt) (temporal-dtype? dt) (enum-dtype? dt)
      (and (memq dt '(boolean string categorical null)) #t)))

(define (decimal-dtype? dt)
  (match dt
    [(list 'decimal _ _) #t]
    [_ #f]))

(define (plain-operand dt v)
  (define numeric (or (numeric-dtype? dt) (decimal-dtype? dt)))
  (cond
    [(polars-null? v) (cons (if (constructible-dtype? dt) dt 'null) v)]
    [(temporal-value-dtype v) => (lambda (value-dtype) (cons value-dtype v))]
    [(and (memq dt '(float32 float64)) (real? v)) (cons dt (exact->inexact v))]
    [(and (exact-integer? v) (in-range-of dt v)) (cons dt v)]
    [(and numeric (exact-integer? v) (in-range-of 'int64 v)) (cons 'int64 v)]
    [(and numeric (real? v) (not (exact-integer? v))) (cons 'float64 (exact->inexact v))]
    [(and (eq? dt 'boolean) (boolean? v)) (cons dt v)]
    [(and (or (memq dt '(string categorical)) (enum-dtype? dt)) (string? v)) (cons dt v)]
    [(and (or (memq dt '(string categorical)) (enum-dtype? dt)) (symbol? v))
     (cons dt (symbol->string v))]
    [else #f]))

(define (lifted who dt n v)
  (if (enum-dtype? dt)
      (with-release ([strings (series-new-str "" (make-list n v)) series-drop])
        (wrap-series (series-cast-enum who strings dt)))
      (const-series dt n v)))

(define (operand-series who s other)
  (define dt (series-dtype s))
  (define o
    (cond
      [(series? other) other]
      [(plain-operand dt other)
       => (lambda (operand) (lifted who (car operand) (series-len s) (cdr operand)))]
      [else (raise-arguments-error who "the value cannot be an element of a series of this dtype"
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
    [(or (boolean? other) (polars-null? other)) (const-series 'boolean (series-len s) other)]
    [else (raise-argument-error who "(or/c series? boolean? polars-null?)" other)]))

(define (failure-cause e)
  (define message (exn-message e))
  (match (regexp-match #rx"^[^:]*: (?:failed to collect the query: )?(.*?)(?:\n\nResolved plan.*)?$"
                       message)
    [(list _ cause) cause]
    [#f message]))

(define (raise-cause who e #:contract? [contract? (exn:fail:contract? e)])
  (define make-exn (if contract? exn:fail:contract exn:fail))
  (raise (make-exn (format "~a: ~a" who (failure-cause e)) (exn-continuation-marks e))))

(define (series-through-expr s build)
  (define name (series-name s))
  (with-release ([frame (dataframe-new (list s)) dataframe-drop]
                 [out (dataframe-select-exprs frame (list (expr-alias (build (expr-all)) name)))
                      dataframe-drop])
    (wrap-series (dataframe-column out name))))

(define (expression-form-op who expr-op a b)
  (define (literal v)
    (with-handlers ([exn:fail? (lambda (e) (raise-cause who e #:contract? #t))])
      (lit v)))
  (define (run s build)
    (with-handlers ([exn:fail? (lambda (e) (raise-cause who e))])
      (series-through-expr s build)))
  (define (expression-form? s v)
    (and (series? s) (or (polars-null? v) (and (null-series? s) (not (series? v))))))
  (cond
    [(expression-form? a b)
     (define v (literal b))
     (run a (lambda (e) (expr-op e v)))]
    [(expression-form? b a)
     (define v (literal a))
     (run b (lambda (e) (expr-op v e)))]
    [else #f]))

