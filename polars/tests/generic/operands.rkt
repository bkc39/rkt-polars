#lang racket/base

(module+ test
  (require rackunit
           (only-in polars/private/expr expr-add expr-drop expr-neg)
           (only-in polars/private/expr-core col expr-drop-count lazyframe-drop-count)
           (only-in polars/private/foreign polars-null polars-null? series-new-i64 series-ref)
           (only-in polars/private/generic/core wrap-series)
           (only-in polars/private/generic/operands
                    expression-form-op operand-action series-through-expr)
           (submod polars/private/generic/operands internal)
           (only-in polars/tests/test-helpers settle!)
           (only-in gregor date))
  (define (noting build)
    (define given (box '()))
    (values given
            (lambda operands
              (define built (apply build operands))
              (set-box! given (cons built operands))
              built)))
  (define (check-all-dropped exprs)
    (for ([e (in-list exprs)])
      (check-exn #rx"^expr-drop: expression has been dropped" (lambda () (expr-drop e)))))
  (define ints (wrap-series (series-new-i64 "x" '(1 2))))

  (for ([v (list 1 -7 (expt 2 63) 1/3 2.5 1.0 -0.0 0.0 1e-5 0.0001 1e16 1e22 123456789.0 5e-324
                 0.30000000000000004 12345678901234567890.0 +inf.0 -inf.0 +nan.0 -2.5e-10
                 651483685541104.2 -651483685541104.2 #t #f)]
        [text (list "1" "-7" "9223372036854775808" "0.3333333333333333" "2.5" "1.0" "-0.0" "0.0"
                    "1e-05" "0.0001" "1e+16" "1e+22" "123456789.0" "5e-324" "0.30000000000000004"
                    "1.2345678901234567e+19" "inf" "-inf" "nan" "-2.5e-10"
                    "651483685541104.2" "-651483685541104.2" "True" "False")])
    (check-equal? (python-str v) text))
  (check-equal? (operand-action '+ 'int64 "x" 'left) 'expression)
  (check-equal? (operand-action '+ 'int64 "x" 'right) 'string)
  (check-equal? (operand-action 'mod 'date 2 'right) 'modulo)
  (check-equal? (operand-action 'mod 'int64 (date 2024 1 1) 'right) 'own)

  (let-values ([(given negate) (noting expr-neg)])
    (check-equal? (series-ref (series-through-expr '- ints negate) 1) -2)
    (check-equal? (length (unbox given)) 2)
    (check-all-dropped (unbox given)))

  (let-values ([(given add) (noting expr-add)])
    (check-pred polars-null? (series-ref (expression-form-op '+ add ints polars-null) 0))
    (check-equal? (length (unbox given)) 3)
    (check-all-dropped (unbox given)))

  (settle!)
  (let ([before (expr-drop-count)]
        [plans-before (lazyframe-drop-count)])
    (expression-form-op '+ expr-add ints polars-null)
    (check >= (- (expr-drop-count) before) 4)
    (check-equal? (- (lazyframe-drop-count) plans-before) 2))
  (settle!)
  (let ([plans-before (lazyframe-drop-count)])
    (check-exn exn:fail? (lambda () (series-through-expr '- ints (lambda (e) (col "absent")))))
    (check-equal? (- (lazyframe-drop-count) plans-before) 2)))
