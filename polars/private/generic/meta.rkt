#lang racket/base

(require racket/contract/base
         (only-in polars/private/expr
                  Expr-ptr? expr-meta-eq? expr-meta-output-name expr-meta-root-names)
         (only-in polars/private/generic/expr-util ->col-expr col-expr/c))

(provide (contract-out
          [meta-output-name (-> col-expr/c string?)]
          [meta-root-names (-> col-expr/c (listof string?))]
          [meta-eq? (-> col-expr/c col-expr/c boolean?)]))

(define (meta-output-name x)
  (expr-meta-output-name (->col-expr 'meta-output-name x)))

(define (meta-root-names x)
  (expr-meta-root-names (->col-expr 'meta-root-names x)))

(define (meta-eq? a b)
  (expr-meta-eq? (->col-expr 'meta-eq? a) (->col-expr 'meta-eq? b)))

(module+ test
  (require rackunit
           (only-in racket/contract exn:fail:contract:blame?)
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
  (check-exn #rx"^expr-meta-output-name: cannot determine the output name of "
             (lambda () (meta-output-name "*")))
  (check-exn exn:fail:contract:blame? (lambda () (contracted:meta-output-name 5)))
  (check-exn #rx"meta-output-name: contract violation.*expected: col-expr/c"
             (lambda () (contracted:meta-output-name 5)))
  (check-exn exn:fail:contract:blame? (lambda () (contracted:meta-root-names 'a)))
  (check-exn exn:fail:contract:blame? (lambda () (contracted:meta-eq? (col "a") 5))))
