#lang racket/base

(require racket/contract/base
         (only-in polars/private/expr
                  Expr-ptr? expr-meta-eq? expr-meta-output-name/who expr-meta-root-names)
         (only-in polars/private/generic/expr-util ->col-expr col-expr/c))

(provide (contract-out
          [meta-output-name (-> col-expr/c string?)]
          [meta-root-names (-> col-expr/c (listof string?))]
          [meta-eq? (-> col-expr/c col-expr/c boolean?)]))

(define (meta-output-name x)
  (expr-meta-output-name/who 'meta-output-name (->col-expr 'meta-output-name x)))

(define (meta-root-names x)
  (expr-meta-root-names (->col-expr 'meta-root-names x)))

(define (meta-eq? a b)
  (expr-meta-eq? (->col-expr 'meta-eq? a) (->col-expr 'meta-eq? b)))

(module+ internal
  (provide meta-eq? meta-output-name meta-root-names))
