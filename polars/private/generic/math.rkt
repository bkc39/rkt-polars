#lang racket/base

;; Element-wise math, completing the racket/base-shadowing operator family
;; (alongside + - * / mod in operators.rkt).  abs / floor / sqrt / exp / log
;; shadow racket/base and so are defined under p-* spellings here and renamed
;; on the way out by the aggregator (with main.rkt re-importing them, like the
;; arithmetic operators); round is defined under its own name so its errors
;; report it, and the aggregator imports it as p-round.  sign / ceil / log1p /
;; pow / clip do not collide and are provided directly.
;;
;; Each op takes an Expr or a bare column-name string (auto-lifted via col).
;; The racket/base-shadowing ones also accept a plain number and fall back to
;; racket/base, so ordinary numeric code keeps working.

(require (prefix-in base: racket/base)
         (only-in racket/contract/base contract-name)
         (only-in polars/private/c-integer uint32/c)
         polars/private/foreign
         polars/private/expr
         polars/private/generic/expr-util)

(provide p-abs p-floor p-sqrt p-exp p-log round
         sign ceil log1p pow clip)

(define-math-unop p-abs   'abs   expr-abs   base:abs)
(define-math-unop p-floor 'floor expr-floor base:floor)
(define-math-unop p-sqrt  'sqrt  expr-sqrt  base:sqrt)
(define-math-unop p-exp   'exp   expr-exp   base:exp)

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

;; logarithm; #:base defaults to natural (e).  Numbers use racket/base log.
(define (p-log x #:base [base #f])
  (cond [(number? x) (if base (base:log x base) (base:log x))]
        [else
         (define e (->col-expr 'log x))
         (if base (expr-log e #:base base) (expr-log e))]))

;; raise to a power (exponent auto-lifted to a literal); clamp to [lower, upper]
;; (either bound may be omitted).
(define (pow x exponent) (expr-pow (->col-expr 'pow x) (->expr/who 'pow exponent)))

(define (clip x #:lower [lower #f] #:upper [upper #f])
  (expr-clip (->col-expr 'clip x)
             #:lower (and lower (->expr/who 'clip lower))
             #:upper (and upper (->expr/who 'clip upper))))
