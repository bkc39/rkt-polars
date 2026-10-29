#lang racket/base

(require racket/contract
         (only-in polars/private/column-pattern column-pattern/c)
         (only-in polars/private/expr Expr-ptr? expr-all multi-column-expr?)
         (only-in (submod polars/private/expr-core internal) expr-exclude/who))

(provide (contract-out
          [all (-> Expr-ptr?)]
          [exclude (-> multi-column-expr? column-pattern/c column-pattern/c ... Expr-ptr?)]))

(define all expr-all)

(define (exclude e name . names)
  (expr-exclude/who 'exclude e (cons name names)))

(module+ internal
  (provide all exclude))
