#lang racket/base

(require (only-in polars/private/foreign
                  polars-null? series-and/who series-not/who series-or/who series-xor/who)
         (only-in polars/private/expr ->expr/who Expr-ptr? expr-and expr-not expr-or expr-xor)
         (only-in polars/private/generic/core series? wrap-series)
         (only-in polars/private/generic/expr-util define-named)
         (only-in polars/private/generic/operands call-with-logical-operand)
         syntax/parse/define
         (for-syntax racket/base))

(provide p-and p-not p-or p-xor)

(define (operand? v) (or (Expr-ptr? v) (series? v)))

(define (combine who expr-op series-op a b)
  (cond
    [(or (Expr-ptr? a) (Expr-ptr? b)) (expr-op (->expr/who who a) (->expr/who who b))]
    [(series? a) (call-with-logical-operand who a b (lambda (o) (wrap-series (series-op who a o))))]
    [else (call-with-logical-operand who b a (lambda (o) (wrap-series (series-op who o b))))]))

(define (combine-and a b) (combine 'and expr-and series-and/who a b))
(define (combine-or a b) (combine 'or expr-or series-or/who a b))

(define (decided? identity v)
  (not (eq? (and v #t) identity)))

(define (beside-null identity combine v w)
  (cond
    [(operand? w) (combine v w)]
    [(decided? identity v) v]
    [else w]))

(define-syntax-parser connective
  [(_ identity:boolean _:id) #'identity]
  [(_ _:boolean _:id e:expr) #'e]
  [(_ identity:boolean combine:id e0:expr e:expr ...+)
   #'(let ([v e0])
       (cond
         [(operand? v) (combine v (connective identity combine e ...))]
         [(polars-null? v) (beside-null identity combine v (connective identity combine e ...))]
         [(decided? identity v) v]
         [else (connective identity combine e ...)]))])

(define-syntax-parse-rule (p-and e:expr ...)
  (connective #t combine-and e ...))

(define-syntax-parse-rule (p-or e:expr ...)
  (connective #f combine-or e ...))

(define-named (p-not not x)
  (cond
    [(Expr-ptr? x) (expr-not x)]
    [(series? x) (wrap-series (series-not/who 'not x))]
    [else (not x)]))

(define-named (p-xor xor a b)
  (cond
    [(or (operand? a) (operand? b)) (combine 'xor expr-xor series-xor/who a b)]
    [else (and (or a b) (not (and a b)))]))
