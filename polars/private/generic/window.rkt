#lang racket/base

(require (only-in racket/contract/base ->* contract-out listof)
         (only-in polars/private/expr Expr-ptr? expr-over)
         (only-in polars/private/generic/expr-util ->col-expr col-expr/c))

(provide (contract-out
          [over (->* (col-expr/c col-expr/c) #:rest (listof col-expr/c) Expr-ptr?)]))

(define (over e . keys)
  (expr-over (->col-expr 'over e) keys))

(module+ internal
  (provide over))
