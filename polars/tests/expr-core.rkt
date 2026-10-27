#lang racket/base

(module+ test
  (require rackunit
           (only-in ffi/unsafe _fun cpointer?)
           (only-in ffi/unsafe/alloc allocator)
           (only-in racket/contract contract-name)
           (prefix-in contracted: polars/private/expr-core)
           (only-in polars/private/c-integer int64-max int64-min uint64-max)
           (only-in polars/private/expr-core
                    ->expr/who Expr-ptr? _Expr-ptr define-compat expr-alias expr-col
                    expr-drop-count lit-integer/c)
           (only-in (submod polars/private/expr-core internal)
                    col expr->string expr-all expr-drop expr-dtype-col expr-exclude lit
                    lit-value/c multi-column-expr?)
           (only-in polars/private/foreign polars-null))

  (check-pred Expr-ptr? (expr-all))
  (check-pred Expr-ptr? (expr-dtype-col 'float64))
  (check-pred Expr-ptr? (expr-dtype-col 'f64))
  (check-pred Expr-ptr? (expr-dtype-col '(duration nanoseconds)))
  (check-pred Expr-ptr? (expr-exclude (expr-all) '("a")))
  (check-pred Expr-ptr? (expr-exclude (expr-dtype-col 'int32) (list "a" #rx"^b")))
  (check-pred Expr-ptr? (expr-exclude (expr-col "^a.*$") '("ab")))
  (check-true (multi-column-expr? (expr-all)))
  (check-true (multi-column-expr? (expr-dtype-col 'string)))
  (check-true (multi-column-expr? (col #rx"x")))
  (check-true (multi-column-expr? (expr-alias (expr-all) "y")))
  (check-false (multi-column-expr? (expr-col "a")))
  (check-false (multi-column-expr? (lit 1)))
  (check-false (multi-column-expr? "a"))
  (check-exn #rx"^expr-exclude: contract violation\n  expected: multi-column-expr\\?"
             (lambda () (contracted:expr-exclude (expr-col "a") '("b"))))
  (check-exn #rx"^expr-exclude: contract violation"
             (lambda () (contracted:expr-exclude (expr-all) '())))
  (check-exn #rx"^expr-dtype-col: contract violation"
             (lambda () (contracted:expr-dtype-col 'list)))
  (check-exn #rx"^col: contract violation\n  expected: \\(or/c string\\? regexp\\? dtype-spec\\?\\)\n  given: 42"
             (lambda () (contracted:col 42)))
  (check-exn #rx"^col: contract violation" (lambda () (contracted:col 'list)))
  (for ([v (list int64-min int64-max (add1 int64-max) uint64-max 1/2 +inf.0 "s" 's #t polars-null)])
    (check-pred Expr-ptr? (contracted:lit v)))
  (define lit-expected (regexp-quote (format "~s" (contract-name lit-value/c))))
  (for ([v (list (add1 uint64-max) (sub1 int64-min) #\a '(1) (vector))])
    (check-exn (regexp (format "^lit: contract violation\n  expected: ~a\n  given: ~a\n"
                               lit-expected (regexp-quote (format "~e" v))))
               (lambda () (contracted:lit v))))
  (check-exn (regexp (format "^expr-add: contract violation\n  expected: ~a\n  given: ~a$"
                             (regexp-quote (format "~s" (contract-name lit-integer/c)))
                             (add1 uint64-max)))
             (lambda () (->expr/who 'expr-add (add1 uint64-max))))
  (check-exn #rx"^\\+: contract violation\n  expected: \\(or/c boolean\\? [^\n]*\n  given: #\\\\a$"
             (lambda () (->expr/who '+ #\a)))
  (check-exn #rx"^col: contract violation" (lambda () (contracted:col #rx#"bytes")))
  (check-exn #rx"^col: contract violation" (lambda () (contracted:col '(datetime weeks))))
  (check-pred Expr-ptr? (contracted:col '(datetime microseconds "UTC")))
  (check-pred multi-column-expr? (expr-dtype-col '(datetime nanoseconds "Asia/Kathmandu")))
  (check-exn #rx"^col: contract violation" (lambda () (contracted:col '(datetime microseconds ""))))
  (check-exn #rx"^col: contract violation" (lambda () (contracted:col '(datetime #f "UTC"))))
  (check-exn (regexp (string-append "^col: cannot select '\\(datetime microseconds \"Mars/Base\"\\):"
                                    " unable to parse time zone: 'Mars/Base'"))
             (lambda () (col '(datetime microseconds "Mars/Base"))))
  (check-exn #rx"^expr-dtype-col: cannot select .*not a time zone: '\\*'"
             (lambda () (expr-dtype-col '(datetime microseconds "*"))))
  (define nul-enum (list 'enum 'a (string->symbol "b\u0000c")))
  (check-exn #rx"^col: contract violation\n  expected: an enum category without a NUL"
             (lambda () (contracted:col nul-enum)))
  (check-exn #rx"^expr-dtype-col: contract violation\n  expected: an enum category without a NUL"
             (lambda () (contracted:expr-dtype-col nul-enum)))

  (define-compat expr-add
    (_fun _Expr-ptr _Expr-ptr -> _Expr-ptr)
    #:wrap (allocator expr-drop))
  (define-compat expr-mul
    (_fun _Expr-ptr _Expr-ptr -> _Expr-ptr)
    #:wrap (allocator expr-drop))
  (define print-col (col "x"))
  (check-equal? (expr->string print-col) "col(\"x\")")
  (check-equal? (format "~a" print-col) "col(\"x\")")
  (check-equal? (format "~s" print-col) "col(\"x\")")
  (check-equal? (format "~v" print-col) "col(\"x\")")
  (check-equal? (expr->string (expr-add (col "a") (col "b")))
                "[(col(\"a\")) + (col(\"b\"))]")
  (check-equal? (expr->string (expr-alias (col "a") "b")) "col(\"a\").alias(\"b\")")
  (check-equal? (expr->string (expr-mul (col "v") (lit 10))) "[(col(\"v\")) * (dyn int: 10)]")
  (check-equal? (expr->string (lit "hi")) "\"hi\"")
  (check-equal? (expr->string (lit #t)) "true")
  (check-equal? (expr->string (lit polars-null)) "null")
  (check-pred Expr-ptr? print-col)
  (check-true (cpointer? print-col))
  (check-pred Expr-ptr? (expr-alias print-col "y"))
  (check-false (equal? (col "x") (col "x")))
  (define dropped (col "d"))
  (expr-drop dropped)
  (check-equal? (format "~a" dropped) "#<expr: dropped>")
  (check-exn exn:fail? (lambda () (expr-alias dropped "e")))
  (check-exn exn:fail? (lambda () (expr-drop dropped)))
  (define drop-before (expr-drop-count))
  (for ([_ (in-range 100)])
    (void (expr-alias (col "g") "h")))
  (for ([_ (in-range 10)])
    (collect-garbage)
    (sleep 0.01))
  (check-true (>= (- (expr-drop-count) drop-before) 200)))
