#lang racket/base

;; Polars' null / NaN Expr ops: fill-null / fill-nan, forward/backward fill,
;; is-null / is-not-null / is-nan / is-not-nan / is-finite / is-infinite, and
;; drop-nans.  Each takes an Expr or a bare column-name string (auto-lifted via
;; col), mirroring pl.col(x).<op>().  drop-nulls itself lives in reshape, where
;; it also covers eager series / dataframe; it accepts an Expr there too.

(require (only-in racket/contract/base ->* contract-out or/c)
         (only-in polars/private/c-integer uint32/c)
         polars/private/foreign
         polars/private/expr
         polars/private/generic/expr-util)

(provide is-null is-not-null is-nan is-not-nan is-finite is-infinite
         fill-null fill-nan drop-nans
         (contract-out
          [forward-fill (->* (col-expr/c) (#:limit (or/c #f uint32/c)) Expr-ptr?)]
          [backward-fill (->* (col-expr/c) (#:limit (or/c #f uint32/c)) Expr-ptr?)]))

(define-expr-unop is-null     'is-null     expr-is-null)
(define-expr-unop is-not-null 'is-not-null expr-is-not-null)
(define-expr-unop is-nan      'is-nan      expr-is-nan)
(define-expr-unop is-not-nan  'is-not-nan  expr-is-not-nan)
(define-expr-unop is-finite   'is-finite   expr-is-finite)
(define-expr-unop is-infinite 'is-infinite expr-is-infinite)

;; fill-null / fill-nan replace missing / NaN with a value (auto-lifted to a
;; literal); forward/backward-fill carry the last/next valid value forward or
;; back (#:limit caps how far a single run is carried).
(define (fill-null x value)
  (expr-fill-null (->col-expr 'fill-null x) (->expr/who 'fill-null value)))
(define (fill-nan x value)
  (expr-fill-nan (->col-expr 'fill-nan x) (->expr/who 'fill-nan value)))
(define (forward-fill x #:limit [limit #f])
  (expr-forward-fill (->col-expr 'forward-fill x) #:limit limit))
(define (backward-fill x #:limit [limit #f])
  (expr-backward-fill (->col-expr 'backward-fill x) #:limit limit))
(define-expr-unop drop-nans 'drop-nans expr-drop-nans)

(module+ internal
  (provide backward-fill forward-fill))
