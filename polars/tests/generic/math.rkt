#lang racket/base

(module+ test
  (require rackunit (only-in threading ~>)
           (only-in polars/private/generic/core dataframe ref series)
           (only-in polars/private/generic/reductions alias)
           (only-in polars/private/generic/reshape select with-columns)
           (only-in polars/tests/generic/test-fixtures column)
           (only-in polars/private/generic/math
                    ceil clip log1p p-abs p-exp p-floor [log p-log] p-sqrt pow round sign))
  ;; numeric fall-through keeps racket/base behaviour for the shadowing ops
  (check-equal? (p-abs -3) 3)
  (check-equal? (p-floor 2.7) 2.0)
  (check-equal? (round 2.345 #:decimals 1) 2.3)
  (check-= (p-sqrt 9) 3.0 1e-9)
  (check-= (p-log 8 #:base 2) 3.0 1e-9)
  ;; Expr math through with-columns -> evaluated values
  (define df (dataframe (list (series '(-2.5 -1.0 0.0 1.5 4.0) #:name "x" #:dtype 'f64))))
  (define out
    (~> df (with-columns
             (alias (p-abs "x") "abs")
             (alias (sign "x") "sign")
             (alias (round "x" #:decimals 0) "r")
             (alias (p-floor "x") "fl")
             (alias (ceil "x") "ce")
             (alias (clip "x" #:lower -1.0 #:upper 2.0) "cl")
             (alias (p-sqrt (p-abs "x")) "sq")
             (alias (p-log (p-abs "x") #:base 2) "l2")
             (alias (pow (p-abs "x") 2) "p2"))))
  (define (c name i) (ref (ref out #:columns name) i))
  (check-equal? (c "abs" 0) 2.5)
  (check-equal? (c "sign" 0) -1.0)
  (check-equal? (c "fl" 0) -3.0)
  (check-equal? (c "ce" 0) -2.0)
  (check-equal? (c "cl" 0) -1.0)
  (check-equal? (c "cl" 4) 2.0)
  (check-= (c "sq" 4) 2.0 1e-9)
  (check-= (c "l2" 4) 2.0 1e-9)
  (check-= (c "p2" 0) 6.25 1e-9)

  (define ties (dataframe (list (series '(-2.5 -1.5 -0.5 0.5 1.5 2.5 0.125 2.345) #:name "x"))))
  (check-equal? (column (select ties (round "x")) "x")
                '(-2.0 -2.0 -0.0 0.0 2.0 2.0 0.0 2.0))
  (for ([decimals (in-list '(1 2))])
    (check-equal? (column (select ties (round "x" #:decimals decimals)) "x")
                  (map (lambda (x) (round x #:decimals decimals)) (column ties "x"))))

  (test-case "the reference's abs, sqrt, exp, floor, log, ceil, log1p and clip example"
    (define readings (dataframe (list (series '(-2.25 0.5 4.0) #:name "x"))))
    (define rounded
      (select readings
              (alias (p-abs "x") "abs") (alias (p-sqrt (p-abs "x")) "sqrt")
              (alias (p-floor "x") "floor") (alias (ceil "x") "ceil")))
    (check-equal? (column rounded "abs") '(2.25 0.5 4.0))
    (check-equal? (column rounded "sqrt") (list 1.5 (sqrt 0.5) 2.0))
    (check-equal? (column rounded "floor") '(-3.0 0.0 4.0))
    (check-equal? (column rounded "ceil") '(-2.0 1.0 4.0))
    (define curved
      (select readings
              (alias (p-exp "x") "exp") (alias (p-log (p-abs "x") #:base 2) "log2")
              (alias (log1p (p-abs "x")) "log1p") (alias (clip "x" #:lower 0 #:upper 1) "clip")))
    (for ([got (in-list (column curved "exp"))] [x (in-list '(-2.25 0.5 4.0))])
      (check-= got (exp x) 1e-12))
    (for ([got (in-list (column curved "log2"))] [want (in-list (list (/ (log 2.25) (log 2)) -1.0 2.0))])
      (check-= got want 1e-12))
    (for ([got (in-list (column curved "log1p"))] [x (in-list '(2.25 0.5 4.0))])
      (check-= got (log (+ 1 x)) 1e-12))
    (check-equal? (column curved "clip") '(0.0 0.5 1.0))
    (check-equal? (list (p-abs -3) (p-sqrt 16) (p-floor 2.5)) '(3 4 2.0))
    (check-= (p-log 8 #:base 2) 3.0 1e-12)
    (check-exn #rx"^ceil: expected an Expr or column name, got 2.5" (lambda () (ceil 2.5)))))
