#lang racket/base

(require racket/contract/base
         (only-in polars/private/expr
                  Expr-ptr? expr-meta-eq? expr-meta-output-name expr-meta-root-names)
         (only-in polars/private/generic/expr-util ->col-expr))

(provide (contract-out
          [meta-output-name (-> (or/c Expr-ptr? string?) string?)]
          [meta-root-names (-> (or/c Expr-ptr? string?) (listof string?))]
          [meta-eq? (-> (or/c Expr-ptr? string?) (or/c Expr-ptr? string?) boolean?)]))

(define (meta-output-name x)
  (error 'unimplemented))

(define (meta-root-names x)
  (error 'unimplemented))

(define (meta-eq? a b)
  (error 'unimplemented))

(module+ test
  (require rackunit
           (only-in threading ~>)
           (only-in polars/private/expr col expr-add lit)
           (only-in polars/private/generic/reductions alias sum)
           (prefix-in contracted: (submod "..")))
  (define ab (expr-add (col "a") (col "b")))
  (check-equal? (meta-output-name (alias (col "a") "b")) "b")
  (check-equal? (meta-output-name (col "a")) "a")
  (check-equal? (meta-output-name "a") "a")
  (check-equal? (meta-output-name ab) "a")
  (check-equal? (meta-output-name (~> ab sum (alias "t"))) "t")
  (check-equal? (meta-output-name (lit 2)) "literal")
  (check-equal? (meta-root-names ab) '("a" "b"))
  (check-equal? (meta-root-names (expr-add (col "b") (col "a"))) '("b" "a"))
  (check-equal? (meta-root-names (expr-add (col "a") (col "a"))) '("a" "a"))
  (check-equal? (meta-root-names (~> (col "a") sum (alias "t"))) '("a"))
  (check-equal? (meta-root-names (lit 2)) '())
  (check-equal? (meta-root-names "a") '("a"))
  (check-true (meta-eq? ab ab))
  (check-true (meta-eq? (col "a") (col "a")))
  (check-false (eq? (col "a") (col "a")))
  (check-false (meta-eq? (col "a") (col "b")))
  (check-false (meta-eq? (col "a") (alias (col "a") "a")))
  (check-false (meta-eq? ab (expr-add (col "b") (col "a"))))
  (check-true (meta-eq? "a" (col "a")))
  (check-exn exn:fail:contract:blame? (lambda () (contracted:meta-output-name 5)))
  (check-exn #rx"meta-output-name: contract violation.*expected: \\(or/c Expr-ptr\\? string\\?\\)"
             (lambda () (contracted:meta-output-name 5)))
  (check-exn exn:fail:contract:blame? (lambda () (contracted:meta-root-names 'a)))
  (check-exn exn:fail:contract:blame? (lambda () (contracted:meta-eq? (col "a") 5))))
