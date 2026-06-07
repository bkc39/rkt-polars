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
         polars/private/expr)

(provide p-abs p-round p-floor p-sqrt p-exp p-log
         sign ceil log1p pow clip)

;; unary, racket/base-shadowing: Expr/colname -> Expr; number -> racket/base.
(define-syntax-rule (define-math-unop name who expr-op base-op)
  (define (name x)
    (cond [(Expr-ptr? x) (expr-op x)]
          [(string? x)   (expr-op (col x))]
          [(number? x)   (base-op x)]
          [else (error who "expected an Expr, column name, or number, got ~v" x)])))

;; unary, non-shadowing (Polars-only): Expr/colname -> Expr.
(define-syntax-rule (define-expr-unop name who expr-op)
  (define (name x)
    (cond [(Expr-ptr? x) (expr-op x)]
          [(string? x)   (expr-op (col x))]
          [else (error who "expected an Expr or column name, got ~v" x)])))

(define-math-unop p-abs   'abs   expr-abs   base:abs)
(define-math-unop p-floor 'floor expr-floor base:floor)
(define-math-unop p-sqrt  'sqrt  expr-sqrt  base:sqrt)
(define-math-unop p-exp   'exp   expr-exp   base:exp)

(define-expr-unop sign  'sign  expr-sign)
(define-expr-unop ceil  'ceil  expr-ceil)
(define-expr-unop log1p 'log1p expr-log1p)

;; round to #:decimals places (default 0); numbers round with the same rule.
(define (p-round x #:decimals [decimals 0])
  (cond [(Expr-ptr? x) (expr-round x #:decimals decimals)]
        [(string? x)   (expr-round (col x) #:decimals decimals)]
        [(number? x)   (let ([f (base:expt 10 decimals)])
                         (base:/ (base:round (base:* x f)) f))]
        [else (error 'round "expected an Expr, column name, or number, got ~v" x)]))

;; logarithm; #:base defaults to natural (e).  Numbers use racket/base log.
(define (p-log x #:base [base #f])
  (cond [(Expr-ptr? x) (if base (expr-log x #:base base) (expr-log x))]
        [(string? x)   (if base (expr-log (col x) #:base base) (expr-log (col x)))]
        [(number? x)   (if base (base:log x base) (base:log x))]
        [else (error 'log "expected an Expr, column name, or number, got ~v" x)]))

;; raise to a power (exponent auto-lifted to a literal); clamp to [lower, upper]
;; (either bound may be omitted).
(define (pow x exponent)
  (cond [(Expr-ptr? x) (expr-pow x exponent)]
        [(string? x)   (expr-pow (col x) exponent)]
        [else (error 'pow "expected an Expr or column name, got ~v" x)]))

(define (clip x #:lower [lower #f] #:upper [upper #f])
  (cond [(Expr-ptr? x) (expr-clip x #:lower lower #:upper upper)]
        [(string? x)   (expr-clip (col x) #:lower lower #:upper upper)]
        [else (error 'clip "expected an Expr or column name, got ~v" x)]))

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