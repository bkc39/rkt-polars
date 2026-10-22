#lang racket/base

(require (only-in racket/list make-list)
         (only-in racket/match match match*)
         (only-in polars/private/foreign
                  call/foreign-error dataframe-column dataframe-drop dataframe-new enum-dtype?
                  polars-null? series-drop series-dtype series-len series-name)
         (only-in polars/private/expr
                  expr-alias expr-all expr-drop lazyframe-collect/raw lazyframe-select lit/who)
         (only-in (submod polars/private/expr internal) call-with-plan)
         (only-in polars/private/generic/core null-series? series? wrap-series)
         (only-in polars/private/generic/dtype
                  coerce-elements dtype->constructor numeric-dtype? temporal-dtype?)
         (only-in polars/private/resource with-release)
         (only-in polars/private/series series-repeat-temporal)
         (only-in polars/private/temporal temporal-value-dtype))

(provide call-with-logical-operand
         call-with-operand-series
         const-series
         expression-form-op
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

(define comparisons '(= != < > <= >=))

(define (string-like? v)
  (or (string? v) (symbol? v)))

(define (->text v)
  (if (symbol? v) (symbol->string v) v))

(define (comparable-temporal? dt value-dtype)
  (match* (dt value-dtype)
    [((list 'datetime _ _) (list 'datetime _ _)) #t]
    [('date (list 'datetime _ #f)) #t]
    [((list 'duration _) (list 'duration _)) #t]
    [(_ _) (equal? dt value-dtype)]))

(define (plain-operand who dt v)
  (define value-dtype (temporal-value-dtype v))
  (define compare? (and (memq who comparisons) #t))
  (cond
    [(and value-dtype compare?
          (not (and (memq dt '(string categorical)) (memq value-dtype '(date time))))
          (not (comparable-temporal? dt value-dtype)))
     #f]
    [(and (eq? value-dtype 'time) (not compare?)) #f]
    [value-dtype (constant value-dtype v)]
    [(and (string-like? v) (not compare?) (or (eq? who '+) (not (memq dt '(float32 float64)))))
     (constant 'string (->text v))]
    [(and (non-integer-real? v) (not compare?) (memq dt '(boolean string)))
     (constant 'float64 (exact->inexact v))]
    [(and (eq? dt 'string) compare? (real? v))
     (constant 'string (number->string (if (exact-integer? v) v (exact->inexact v))))]
    [(and (boolean? v) (numeric-dtype? dt)) (plain-operand who dt (if v 1 0))]
    [(and (memq dt '(float32 float64)) (real? v)) (constant dt (exact->inexact v))]
    [(and (exact-integer? v) (in-range-of dt v)) (constant dt v)]
    [(and (numeric-dtype? dt) (non-integer-real? v)) (constant 'float64 (exact->inexact v))]
    [(and (eq? dt 'boolean) (boolean? v)) (constant dt v)]
    [(and (memq dt '(string categorical)) (string-like? v)) (constant dt (->text v))]
    [else #f]))

(define (expression-operand? who dt v left?)
  (match dt
    [_ #:when (polars-null? v) #t]
    ['null (literal-value? v)]
    [_ #:when (and (eq? who '+) left? (string-like? v)) #t]
    [(? enum-dtype?) (string-like? v)]
    [(list 'decimal _ _)
     (or (int64-value? v) (non-integer-real? v) (and (boolean? v) (not (memq who comparisons))))]
    [(list 'duration _) (and (eq? who '*) (or (int64-value? v) (non-integer-real? v)))]
    [(or 'int8 'int16 'int32 'int64) (and (int64-value? v) (not (in-range-of dt v)))]
    [(or 'uint8 'uint16 'uint32 'uint64)
     (and (int64-value? v) (not (negative? v)) (not (in-range-of dt v)))]
    [_ #f]))

(define (operand-series who s other)
  (define dt (series-dtype s))
  (define o
    (match (if (series? other) other (plain-operand who dt other))
      [(? series? o) o]
      [(constant dtype value) (const-series who dtype (series-len s) value)]
      [#f (raise-arguments-error who "the value cannot be an element of a series of this dtype"
                                 "value" other "series dtype" dt)]))
  (match* (dt (series-dtype o))
    [((list 'datetime _ zone) (list 'datetime _ other-zone))
     #:when (not (equal? zone other-zone))
     (raise-arguments-error who "datetimes in different time zones"
                            "series dtype" dt "other dtype" (series-dtype o))]
    [(_ other-dt)
     #:when (and (eq? who 'mod) (or (temporal-dtype? dt) (temporal-dtype? other-dt)))
     (raise-arguments-error who "cannot take the modulo of a temporal dtype"
                            "series dtype" dt "other dtype" other-dt)]
    [(_ _) o]))

(define (logical-operand who s other)
  (cond
    [(series? other) other]
    [(or (boolean? other) (polars-null? other)) (const-series who 'boolean (series-len s) other)]
    [else (raise-argument-error who "(or/c series? boolean? polars-null?)" other)]))

(define (call-with-lifted lifted other proc)
  (define release (if (eq? lifted other) void series-drop))
  (with-release ([operand lifted release])
    (proc operand)))

(define (call-with-operand-series who s other proc)
  (call-with-lifted (operand-series who s other) other proc))

(define (call-with-logical-operand who s other proc)
  (call-with-lifted (logical-operand who s other) other proc))

(define (series-through-expr who s build)
  (define name (series-name s))
  (define (collect plan)
    (call/foreign-error who (lambda () (lazyframe-collect/raw plan))))
  (with-release ([frame (dataframe-new (list s)) dataframe-drop]
                 [all (expr-all) expr-drop]
                 [built (build all) expr-drop]
                 [named (expr-alias built name) expr-drop]
                 [out (call-with-plan frame
                                      (lambda (source) (lazyframe-select source (list named)))
                                      collect)
                      dataframe-drop])
    (wrap-series (dataframe-column out name))))

(define (expression-form-op who expr-op a b)
  (define (expression-form? s v left?)
    (and (series? s) (not (series? v)) (expression-operand? who (series-dtype s) v left?)))
  (cond
    [(expression-form? a b #f)
     (with-release ([v (lit/who who b) expr-drop])
       (series-through-expr who a (lambda (e) (expr-op e v))))]
    [(expression-form? b a #t)
     (with-release ([v (lit/who who a) expr-drop])
       (series-through-expr who b (lambda (e) (expr-op v e))))]
    [else #f]))

(module+ test
  (require rackunit
           (only-in polars/private/expr expr-add expr-neg)
           (only-in polars/private/expr-core expr-drop-count)
           (only-in polars/private/foreign polars-null series-new-i64 series-ref)
           (only-in polars/private/test-helpers settle!))
  (define (noting build)
    (define given (box '()))
    (values given
            (lambda operands
              (define built (apply build operands))
              (set-box! given (cons built operands))
              built)))
  (define (check-all-dropped exprs)
    (for ([e (in-list exprs)])
      (check-exn #rx"^expr-drop: expression has been dropped" (lambda () (expr-drop e)))))
  (define ints (wrap-series (series-new-i64 "x" '(1 2))))

  (let-values ([(given negate) (noting expr-neg)])
    (check-equal? (series-ref (series-through-expr '- ints negate) 1) -2)
    (check-equal? (length (unbox given)) 2)
    (check-all-dropped (unbox given)))

  (let-values ([(given add) (noting expr-add)])
    (check-pred polars-null? (series-ref (expression-form-op '+ add ints polars-null) 0))
    (check-equal? (length (unbox given)) 3)
    (check-all-dropped (unbox given)))

  (settle!)
  (let ([before (expr-drop-count)])
    (expression-form-op '+ expr-add ints polars-null)
    (check >= (- (expr-drop-count) before) 4)))
