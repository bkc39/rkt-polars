#lang racket/base

;; Shared plumbing for the Expr-building UX layers (math / strings / datetime /
;; nullable / predicates / cumulative / ordering / reductions).  Every `.str` /
;; `.dt` / aggregation op begins by lifting its first argument: a bare
;; column-name string becomes `(col …)`, an Expr passes through, anything else
;; errors.  `->col-expr` is the single home for that dispatch (was copy-pasted as
;; ->str-expr / ->dt-expr / ->agg-expr / … in each module), and
;; define-expr-unop / define-math-unop generate the two common unary wrapper
;; shapes on top of it.

(require (only-in racket/contract/base flat-named-contract or/c)
         polars/private/foreign
         polars/private/expr
         syntax/parse/define)

(provide ->col-expr col-expr/c define-expr-unop define-math-unop)

;; Lift a column-name string to an Expr; pass an Expr through unchanged.
(define (->col-expr who x)
  (cond [(Expr-ptr? x) x]
        [(string? x)   (col x)]
        [else (error who "expected an Expr or column name, got ~v" x)]))

(define col-expr/c
  (flat-named-contract 'col-expr/c (or/c string? Expr-ptr?)))

;; unary, non-shadowing (Polars-only): Expr/colname -> Expr.
(define-syntax-parse-rule (define-expr-unop name:id who:expr expr-op:expr)
  (define (name x) (expr-op (->col-expr who x))))

;; unary, racket/base-shadowing: Expr/colname -> Expr; number -> racket/base.
(define-syntax-parse-rule (define-math-unop name:id who:expr expr-op:expr base-op:expr)
  (define (name x)
    (cond [(Expr-ptr? x) (expr-op x)]
          [(string? x)   (expr-op (col x))]
          [(number? x)   (base-op x)]
          [else (error who "expected an Expr, column name, or number, got ~v" x)])))
