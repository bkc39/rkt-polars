#lang racket/base

(require (prefix-in base: racket/base)
         polars/private/foreign
         polars/private/expr
         polars/private/generic/core
         polars/private/generic/operands
         syntax/parse/define
         (for-syntax racket/base))

(provide combine-and combine-or p-and p-not p-or p-xor)

;; --- boolean / logical operators --------------------------------------------

(define (series-logical who op a b)
  (if (series? a)
      (wrap-series (op a (logical-operand who a b) #:who who))
      (wrap-series (op (logical-operand who b a) b #:who who))))

(define (eager-logical who expr-op series-op a b)
  (cond [(or (Expr-ptr? a) (Expr-ptr? b)) (expr-op a b)]
        [(expression-form-op who expr-op a b) => values]
        [else (series-logical who series-op a b)]))
(define (combine-and a b) (eager-logical 'and expr-and series-and a b))
(define (combine-or a b) (eager-logical 'or expr-or series-or a b))

(define (operand? v) (or (Expr-ptr? v) (series? v)))
(define (null-and v w) (if (operand? w) (combine-and v w) w))
(define (null-or v w) (if (operand? w) (combine-or v w) v))

(define-syntax-parser p-and
  [(_) #'#t]
  [(_ e:expr) #'e]
  [(_ e0:expr e:expr ...+)
   #'(let ([v e0])
       (cond [(operand? v) (combine-and v (p-and e ...))]
             [(polars-null? v) (null-and v (p-and e ...))]
             [v (p-and e ...)]
             [else v]))])

(define-syntax-parser p-or
  [(_) #'#f]
  [(_ e:expr) #'e]
  [(_ e0:expr e:expr ...+)
   #'(let ([v e0])
       (cond [(operand? v) (combine-or v (p-or e ...))]
             [(polars-null? v) (null-or v (p-or e ...))]
             [v v]
             [else (p-or e ...)]))])

(define (p-not x)
  (cond [(Expr-ptr? x) (expr-not x)]
        [(series? x)   (wrap-series (series-not x #:who 'not))]
        [else          (base:not x)]))

(define (p-xor a b)
  (cond [(or (operand? a) (operand? b)) (eager-logical 'xor expr-xor series-xor a b)]
        [else (and (or a b) (not (and a b)))]))
