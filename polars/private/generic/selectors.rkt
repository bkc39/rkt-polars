#lang racket/base

(require racket/contract
         (only-in polars/private/expr Expr-ptr? expr-all expr-exclude multi-column-expr?))

(provide (contract-out
          [all (-> Expr-ptr?)]
          [exclude (->* (multi-column-expr? (or/c string? regexp?))
                        #:rest (listof (or/c string? regexp?))
                        Expr-ptr?)]))

(define (all)
  (expr-all))

(define (exclude e name . names)
  (expr-exclude e (cons name names)))

(module+ test
  (require rackunit
           (only-in gregor datetime)
           (only-in threading ~>)
           (prefix-in contracted: (submod ".."))
           polars/private/generic/core
           polars/private/generic/operators
           polars/private/generic/reductions
           polars/private/generic/reshape
           polars/private/generic/test-fixtures)

  (define people
    (dataframe
     (list (series '("Alice Archer" "Ben Brown" "Chloe Cooper" "Daniel Donovan")
                   #:name "name")
           (series (list (datetime 1997 1 10) (datetime 1985 2 15)
                         (datetime 1983 3 22) (datetime 1981 4 30))
                   #:name "birthdate")
           (series '(57.9 72.5 53.6 83.1) #:name "weight")
           (series '(1.56 1.77 1.65 1.75) #:name "height"))))
  (define people/date (with-columns people (cast "birthdate" 'date)))
  (define iris
    (dataframe (list (series '(5.1 4.9) #:name "sepal_length")
                     (series '(3.5 3.0) #:name "sepal_width")
                     (series '(1.4 1.3) #:name "petal_length")
                     (series '(0.2 0.2) #:name "petal_width")
                     (series '("setosa" "setosa") #:name "species"))))
  (define ints-only (dataframe (list (series '(1 2) #:name "a" #:dtype 'i32))))

  (check-equal? (column-names (select people (all))) (column-names people))
  (check-equal? (format "~a" (select people (all))) (format "~a" people))
  (check-pred lazyframe? (select (lazy people) (all)))
  (check-equal? (format "~a" (collect (select (lazy people) (all))))
                (format "~a" people))

  (check-equal? (column-names (select ops-df (exclude (all) "group")))
                '("value" "cost"))
  (check-equal? (format "~a" (select ops-df (exclude (all) "group")))
                (format "~a" (drop ops-df "group")))
  (check-equal? (column-names (select ops-df (exclude (all) "group" "cost")))
                '("value"))
  (check-equal? (column-names (select ops-df (~> (all) (exclude "group") (exclude "cost"))))
                '("value"))
  (check-equal? (column-names (select ops-df (exclude (all) "nope")))
                '("group" "value" "cost"))
  (check-equal? (column-names (select iris (exclude (all) #rx"^sepal_")))
                '("petal_length" "petal_width" "species"))
  (check-equal? (column-names (select people (exclude (col 'float64) "height")))
                '("weight"))
  (check-equal? (column-names (~> ops-df (group-by "group") (agg (sum (exclude (all) "cost")))))
                '("group" "value"))

  (check-equal? (column-names (select people (col 'float64))) '("weight" "height"))
  (check-equal? (column-names (select people (col 'f64))) '("weight" "height"))
  (check-equal? (column-names (select people (col 'string))) '("name"))
  (check-equal? (column-names (select people (col 'str))) '("name"))
  (check-equal? (column-names (select people/date (col 'date))) '("birthdate"))
  (check-equal? (column-names (select people (col '(datetime milliseconds)))) '("birthdate"))
  (check-equal? (column-names (select people (col (dtype (ref people "birthdate")))))
                '("birthdate"))
  (check-equal? (column-names (select people (col 'datetime))) '())
  (check-equal? (shape (select ints-only (col 'float64))) '(0 0))

  (check-equal? (column-names (select iris (col #rx"^sepal_")))
                '("sepal_length" "sepal_width"))
  (check-equal? (column-names (select iris (col #rx"_width$")))
                '("sepal_width" "petal_width"))
  (check-equal? (column-names (select iris (col #rx"tal")))
                '("petal_length" "petal_width"))
  (check-equal? (column-names (select iris (col #rx"^species$"))) '("species"))
  (check-equal? (column-names (select iris (col #rx"length|species")))
                '("sepal_length" "petal_length" "species"))
  (check-equal? (column-names (select iris (col #px"^[sp]e.*_length$")))
                '("sepal_length" "petal_length"))
  (check-equal? (column-names (select iris (col #rx"zzz"))) '())

  (let ([out (select iris (p* (col #rx"^sepal_") 2))])
    (check-equal? (column-names out) '("sepal_length" "sepal_width"))
    (check-equal? (ref (ref out "sepal_length") 0) 10.2))
  (let ([out (select people (p* (col 'float64) 1.1))])
    (check-equal? (column-names out) '("weight" "height"))
    (check-= (ref (ref out "weight") 0) (* 57.9 1.1) 1e-9))
  (check-exn exn:fail? (lambda () (select people (alias (p* (col 'float64) 2) "x"))))
  (check-pred Expr-ptr? (col #px"(?=a)"))
  (check-exn exn:fail? (lambda () (select iris (col #px"(?=a)"))))

  (check-exn #rx"^exclude: contract violation\n  expected: multi-column-expr\\?\n  given: 5"
             (lambda () (contracted:exclude 5 "a")))
  (check-exn #rx"^exclude: contract violation\n  expected: multi-column-expr\\?"
             (lambda () (contracted:exclude (col "value") "cost")))
  (check-exn #rx"^exclude: contract violation\n  expected: multi-column-expr\\?"
             (lambda () (contracted:exclude (sum "value") "cost")))
  (check-exn #rx"^exclude: contract violation\n  expected: \\(or/c string\\? regexp\\?\\)\n  given: 'a"
             (lambda () (contracted:exclude (all) 'a)))
  (check-exn exn:fail:contract:arity? (lambda () (contracted:exclude (all))))
  (check-exn exn:fail:contract:arity? (lambda () (contracted:all 1)))
  (check-exn #rx"^col: contract violation" (lambda () (col 'nope))))
