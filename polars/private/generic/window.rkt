#lang racket/base

(require (only-in racket/contract/base ->* contract-out listof)
         polars/private/expr
         polars/private/generic/expr-util)

(provide (contract-out
          [over (->* (col-expr/c col-expr/c) #:rest (listof col-expr/c) Expr-ptr?)]))

(define (over e key . keys)
  (expr-over (->col-expr 'over e) (cons key keys)))

(module+ test
  (require rackunit (only-in threading ~>)
           (only-in (submod "..") [over provided-over])
           polars/private/generic/core
           polars/private/generic/operators
           polars/private/generic/reductions
           polars/private/generic/reshape
           polars/private/generic/test-fixtures)
  (define (column d name)
    (for/list ([i (in-range (height d))]) (ref (ref d #:columns name) i)))
  (define total (~> (col "value") sum (over "group") (alias "group_total")))
  (check-pred Expr-ptr? total)
  (define df (with-columns ops-df total))
  ;; same height, columns appended
  (check-equal? (height df) (height ops-df))
  (check-equal? (column-names df) '("group" "value" "cost" "group_total"))
  ;; every row carries its group's aggregate
  (check-equal? (column df "group_total") '(35 35 37 37 18))
  (check-equal? (column (with-columns ops-df (~> (col "value") max (over "group") (alias "m"))) "m")
                '(25 25 30 30 18))
  ;; the same aggregation group-by/agg computes, row for row
  (define agged (~> ops-df (group-by "group") (agg (alias (sum "value") "group_total"))))
  (for ([g (column df "group")]
        [t (column df "group_total")])
    (check-equal? t (for/first ([ag (column agged "group")]
                                [at (column agged "group_total")]
                                #:when (string=? ag g))
                      at)))
  ;; a non-aggregating expression comes back row for row; bare name for e
  (check-equal? (column (select ops-df (alias (over "value" "group") "w")) "w")
                (column ops-df "value"))
  ;; multiple keys
  (define gh (dataframe (list (series '("a" "a" "a" "b") #:name "g")
                              (series '("x" "y" "x" "x") #:name "h")
                              (series '(1 2 3 4) #:name "v" #:dtype 'i32))))
  (check-equal? (column (with-columns gh (~> (col "v") sum (over "g" "h") (alias "t"))) "t")
                '(4 2 4 4))
  ;; an expression as key
  (check-equal? (column (with-columns ops-df
                          (~> (col "value") sum (over (> (col "value") 15)) (alias "t")))
                        "t")
                '(17 73 17 73 73))
  ;; a name key and a (col name) key give the same frame
  (define by-col
    (with-columns ops-df (~> (col "value") sum (over (col "group")) (alias "group_total"))))
  (check-equal? (column-names by-col) (column-names df))
  (check-equal? (column by-col "group_total") (column df "group_total"))
  ;; the lazy plan agrees with eager
  (check-equal? (column (~> ops-df lazy (with-columns total) collect) "group_total")
                (column df "group_total"))
  ;; contract blame names over, never the lift helpers
  (check-exn #rx"^over: contract violation" (lambda () (provided-over 42 "group")))
  (check-exn #rx"^over: contract violation" (lambda () (provided-over (col "value") 'group)))
  (check-exn #rx"^over: contract violation" (lambda () (provided-over (col "value") "group" 7)))
  (check-exn #rx"^over:" (lambda () (provided-over (col "value")))))
