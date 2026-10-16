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
;; and / or stay short-circuit macros; only an Expr/series operand routes into
;; the eager combiners.  not / xor are strict, so plain functions.

(define (series-logical who op a b)
  (if (series? a)
      (wrap-series (op a (logical-operand who a b) #:who who))
      (wrap-series (op (logical-operand who b a) b #:who who))))

(define (combine-and a b)
  (if (or (Expr-ptr? a) (Expr-ptr? b)) (expr-and a b) (series-logical 'and series-and a b)))
(define (combine-or a b)
  (if (or (Expr-ptr? a) (Expr-ptr? b)) (expr-or a b) (series-logical 'or series-or a b)))

(define-syntax-parser p-and
  [(_) #'#t]
  [(_ e:expr) #'e]
  [(_ e0:expr e:expr ...+)
   #'(let ([v e0])
       (if (or (Expr-ptr? v) (series? v))
           (combine-and v (p-and e ...))   ; predicate build (eager)
           (if v (p-and e ...) v)))])      ; booleans: racket `and`

(define-syntax-parser p-or
  [(_) #'#f]
  [(_ e:expr) #'e]
  [(_ e0:expr e:expr ...+)
   #'(let ([v e0])
       (if (or (Expr-ptr? v) (series? v))
           (combine-or v (p-or e ...))
           (if v v (p-or e ...))))])       ; booleans: racket `or`

(define (p-not x)
  (cond [(Expr-ptr? x) (expr-not x)]
        [(series? x)   (wrap-series (series-not x #:who 'not))]
        [else          (base:not x)]))

(define (p-xor a b)
  (cond [(or (Expr-ptr? a) (Expr-ptr? b)) (expr-xor a b)]
        [(or (series? a) (series? b))     (series-logical 'xor series-xor a b)]
        [else (and (or a b) (not (and a b)))]))   ; boolean xor
