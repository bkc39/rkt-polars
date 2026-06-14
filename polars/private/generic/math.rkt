#lang racket/base

;; Element-wise math, completing the racket/base-shadowing operator family
;; (alongside + - * / mod in operators.rkt).  abs / round / floor / sqrt / exp
;; / log shadow racket/base and so are defined under p-* spellings here and
;; renamed on the way out by the aggregator (with main.rkt re-importing them,
;; like the arithmetic operators).  sign / ceil / log1p / pow / clip do not
;; collide and are provided directly.
;;
;; Each op takes an Expr or a bare column-name string (auto-lifted via col).
;; The racket/base-shadowing ones also accept a plain number and fall back to
;; racket/base, so ordinary numeric code keeps working.

(require (prefix-in base: racket/base)
         polars/private/foreign
         polars/private/expr
         polars/private/generic/expr-util)

(provide p-abs p-round p-floor p-sqrt p-exp p-log
         sign ceil log1p pow clip)

(define-math-unop p-abs   'abs   expr-abs   base:abs)
(define-math-unop p-floor 'floor expr-floor base:floor)
(define-math-unop p-sqrt  'sqrt  expr-sqrt  base:sqrt)
(define-math-unop p-exp   'exp   expr-exp   base:exp)

(define-expr-unop sign  'sign  expr-sign)
(define-expr-unop ceil  'ceil  expr-ceil)
(define-expr-unop log1p 'log1p expr-log1p)

;; round to #:decimals places (default 0); numbers round with the same rule.
(define (p-round x #:decimals [decimals 0])
  (cond [(number? x) (let ([f (base:expt 10 decimals)])
                       (base:/ (base:round (base:* x f)) f))]
        [else (expr-round (->col-expr 'round x) #:decimals decimals)]))

;; logarithm; #:base defaults to natural (e).  Numbers use racket/base log.
(define (p-log x #:base [base #f])
  (cond [(number? x) (if base (base:log x base) (base:log x))]
        [else (let ([e (->col-expr 'log x)])
                (if base (expr-log e #:base base) (expr-log e)))]))

;; raise to a power (exponent auto-lifted to a literal); clamp to [lower, upper]
;; (either bound may be omitted).
(define (pow x exponent) (expr-pow (->col-expr 'pow x) exponent))

(define (clip x #:lower [lower #f] #:upper [upper #f])
  (expr-clip (->col-expr 'clip x) #:lower lower #:upper upper))

(module+ test
  (require rackunit (only-in threading ~>)
           polars/private/generic/core
           polars/private/generic/reductions   ; alias
           polars/private/generic/reshape)     ; with-columns
  ;; numeric fall-through keeps racket/base behaviour for the shadowing ops
  (check-equal? (p-abs -3) 3)
  (check-equal? (p-floor 2.7) 2.0)
  (check-equal? (p-round 2.345 #:decimals 1) 2.3)
  (check-= (p-sqrt 9) 3.0 1e-9)
  (check-= (p-log 8 #:base 2) 3.0 1e-9)
  ;; Expr math through with-columns -> evaluated values
  (define df (dataframe (list (series '(-2.5 -1.0 0.0 1.5 4.0) #:name "x" #:dtype 'f64))))
  (define out
    (~> df (with-columns
             (alias (p-abs "x") "abs")
             (alias (sign "x") "sign")
             (alias (p-round "x" #:decimals 0) "r")
             (alias (p-floor "x") "fl")
             (alias (ceil "x") "ce")
             (alias (clip "x" #:lower -1.0 #:upper 2.0) "cl")
             (alias (p-sqrt (p-abs "x")) "sq")
             (alias (p-log (p-abs "x") #:base 2) "l2")
             (alias (pow (p-abs "x") 2) "p2"))))
  (define (c name i) (ref (ref out #:columns name) i))
  (check-equal? (c "abs" 0) 2.5)
  (check-equal? (c "sign" 0) -1)    ; sign yields an integer
  (check-equal? (c "fl" 0) -3.0)
  (check-equal? (c "ce" 0) -2.0)
  (check-equal? (c "cl" 0) -1.0)   ; clamped up to lower
  (check-equal? (c "cl" 4) 2.0)    ; clamped down to upper
  (check-= (c "sq" 4) 2.0 1e-9)    ; sqrt(|4.0|)
  (check-= (c "l2" 4) 2.0 1e-9)    ; log2(|4.0|)
  (check-= (c "p2" 0) 6.25 1e-9))  ; (-2.5)^2 via |x|^2