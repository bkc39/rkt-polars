#lang racket/base

(require (prefix-in base: racket/base)
         (only-in racket/contract/base contract-name)
         (only-in polars/private/c-integer uint32/c)
         polars/private/expr
         polars/private/generic/expr-util)

(provide p-abs p-floor p-sqrt p-exp round log
         sign ceil log1p pow clip)

(define-math-unop abs   expr-abs   base:abs)
(define-math-unop floor expr-floor base:floor)
(define-math-unop sqrt  expr-sqrt  base:sqrt)
(define-math-unop exp   expr-exp   base:exp)

(define-expr-unop sign  'sign  expr-sign)
(define-expr-unop ceil  'ceil  expr-ceil)
(define-expr-unop log1p 'log1p expr-log1p)

(define (round x #:decimals [decimals 0])
  (cond [(and (number? x) (number? decimals))
         (define f (base:expt 10 decimals))
         (base:/ (base:round (base:* x f)) f)]
        [(number? x) (raise-argument-error 'round "number?" decimals)]
        [(not (or (Expr-ptr? x) (string? x)))
         (raise-argument-error 'round "(or/c Expr-ptr? string? number?)" x)]
        [(uint32/c decimals) (expr-round (->col-expr 'round x) #:decimals decimals)]
        [else (raise-argument-error 'round (format "~s" (contract-name uint32/c)) decimals)]))

(define (log x #:base [base #f])
  (cond [(number? x) (if base (base:log x base) (base:log x))]
        [(not (or (Expr-ptr? x) (string? x)))
         (raise-argument-error 'log "(or/c Expr-ptr? string? number?)" x)]
        [(not base) (expr-log (->col-expr 'log x))]
        [(and (real? base) (positive? base)) (expr-log (->col-expr 'log x) #:base base)]
        [else (raise-argument-error 'log "(or/c #f (and/c real? positive?))" base)]))

;; raise to a power (exponent auto-lifted to a literal); clamp to [lower, upper]
;; (either bound may be omitted).
(define (pow x exponent) (expr-pow (->col-expr 'pow x) (->expr/who 'pow exponent)))

(define (clip x #:lower [lower #f] #:upper [upper #f])
  (expr-clip (->col-expr 'clip x)
             #:lower (and lower (->expr/who 'clip lower))
             #:upper (and upper (->expr/who 'clip upper))))
