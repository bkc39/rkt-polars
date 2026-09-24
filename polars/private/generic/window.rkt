#lang racket/base

(require (only-in racket/contract/base ->* contract-out listof)
         (only-in polars/private/expr Expr-ptr? expr-over)
         (only-in polars/private/generic/expr-util ->col-expr col-expr/c))

(provide (contract-out
          [over (->* (col-expr/c col-expr/c) #:rest (listof col-expr/c) Expr-ptr?)]))

(define (over e . keys)
  (expr-over (->col-expr 'over e) keys))

(module+ test
  (require rackunit (only-in threading ~>)
           (only-in (submod "..") [over provided-over])
           polars/private/generic/core
           polars/private/generic/operators
           polars/private/generic/reductions
           polars/private/generic/reshape
           polars/private/generic/test-fixtures)
  (define total (~> (col "value") sum (over "group") (alias "group_total")))
  (check-pred Expr-ptr? total)
  (define df (with-columns ops-df total))
  (check-equal? (height df) (height ops-df))
  (check-equal? (column-names df) '("group" "value" "cost" "group_total"))
  (check-equal? (column df "group_total") '(35 35 37 37 18))
  (check-equal? (column (with-columns ops-df (~> (col "value") max (over "group") (alias "m"))) "m")
                '(25 25 30 30 18))
  (define agged (~> ops-df (group-by "group") (agg (alias (sum "value") "group_total"))))
  (define totals (for/hash ([g (column agged "group")] [t (column agged "group_total")])
                   (values g t)))
  (check-equal? (column df "group_total")
                (for/list ([g (column df "group")]) (hash-ref totals g)))
  (check-equal? (column (select ops-df (alias (over "value" "group") "w")) "w")
                (column ops-df "value"))
  (define gh (dataframe (list (series '("a" "a" "a" "b") #:name "g")
                              (series '("x" "y" "x" "x") #:name "h")
                              (series '(1 2 3 4) #:name "v" #:dtype 'i32))))
  (check-equal? (column (with-columns gh (~> (col "v") sum (over "g" "h") (alias "t"))) "t")
                '(4 2 4 4))
  (check-equal? (column (with-columns ops-df
                          (~> (col "value") sum (over (> (col "value") 15)) (alias "t")))
                        "t")
                '(17 73 17 73 73))
  (define by-col
    (with-columns ops-df (~> (col "value") sum (over (col "group")) (alias "group_total"))))
  (check-equal? (column-names by-col) (column-names df))
  (check-equal? (column by-col "group_total") (column df "group_total"))
  (check-equal? (column (~> ops-df lazy (with-columns total) collect) "group_total")
                (column df "group_total"))
  (check-exn #rx"^over: contract violation" (lambda () (provided-over 42 "group")))
  (check-exn #rx"^over: contract violation" (lambda () (provided-over (col "value") 'group)))
  (check-exn #rx"^over: contract violation" (lambda () (provided-over (col "value") "group" 7)))
  (check-exn #rx"^over:" (lambda () (provided-over (col "value")))))
