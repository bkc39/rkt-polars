#lang racket/base

(module+ test
  (require rackunit
           (only-in racket/contract exn:fail:contract:blame?)
           (only-in threading ~>)
           (only-in polars/private/expr
                    col expr-add expr-is-in expr-meta-output-name expr-mul lit)
           (only-in polars/private/foreign series-cast series-new-i32)
           (only-in polars/private/generic/reductions alias sum)
           (prefix-in contracted: polars/private/generic/meta)
           (only-in (submod polars/private/generic/meta internal)
                    meta-eq? meta-output-name meta-root-names))
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
  (check-exn #rx"^meta-output-name: cannot determine the output name of cs\\.all\\(\\)$"
             (lambda () (meta-output-name "*")))
  (check-exn #rx"^meta-output-name: cannot determine the output name of cs\\.matches\\("
             (lambda () (meta-output-name (col #rx"^he"))))
  (check-exn #rx"^meta-output-name: cannot determine the output name of cs\\.by_dtype\\(\\[Float64\\]\\)$"
             (lambda () (meta-output-name (col 'float64))))
  (check-exn #rx"^expr-meta-output-name: cannot determine the output name of cs\\.all\\(\\)$"
             (lambda () (expr-meta-output-name (col "*"))))
  (define past-chrono-in
    (expr-is-in (col "*") (series-cast (series-new-i32 "d" '(2000000000)) 'date)))
  (check-exn #rx"^meta-output-name: cannot determine the output name of #<expr: cannot print: polars panicked: [^>]+>$"
             (lambda () (meta-output-name past-chrono-in)))
  (check-exn #rx"^expr-meta-output-name: cannot determine the output name of #<expr: cannot print: polars panicked: [^>]+>$"
             (lambda () (expr-meta-output-name past-chrono-in)))
  (check-equal? (meta-root-names (col #rx"^he")) '())
  (check-equal? (meta-root-names (expr-mul (col 'float64) (lit 2))) '())
  (check-true (meta-eq? (col 'float64) (col 'f64)))
  (check-false (equal? (alias (col "a") "t") (alias (col "a") "t")))
  (check-exn exn:fail:contract:blame? (lambda () (contracted:meta-output-name 5)))
  (check-exn #rx"meta-output-name: contract violation.*expected: col-expr/c"
             (lambda () (contracted:meta-output-name 5)))
  (check-exn exn:fail:contract:blame? (lambda () (contracted:meta-root-names 'a)))
  (check-exn exn:fail:contract:blame? (lambda () (contracted:meta-eq? (col "a") 5))))
