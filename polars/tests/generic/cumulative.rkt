#lang racket/base

(module+ test
  (require rackunit (only-in threading ~>)
           (only-in polars/private/bulk series->list)
           (only-in polars/private/foreign polars-null)
           (only-in polars/private/generic/core column-names dataframe ref series)
           (only-in polars/private/generic/reductions alias)
           (only-in polars/private/generic/reshape select with-columns)
           (prefix-in contracted: polars/private/generic/cumulative)
           (only-in polars/private/generic/cumulative cum-count cum-max cum-min cum-prod cum-sum)
           (only-in (submod polars/private/generic/cumulative internal) diff shift)
           (only-in polars/tests/generic/test-fixtures column)
           (only-in polars/tests/test-helpers contract-violation-of))
  (define df (dataframe (list (series '(1 2 3 4 5) #:name "x" #:dtype 'i64))))
  (define out
    (~> df (with-columns
             (alias (cum-sum "x") "cs")
             (alias (cum-sum "x" #:reverse #t) "csr")
             (alias (cum-prod "x") "cp")
             (alias (cum-min "x") "cmin")
             (alias (cum-max "x") "cmax")
             (alias (cum-count "x") "cc")
             (alias (shift "x" #:n 1) "s1")
             (alias (shift "x" #:n -1) "sm1")
             (alias (shift "x" #:n 1 #:fill-value 0) "s1f")
             (alias (diff "x" #:n 1) "d1"))))
  (define (c name i) (ref (ref out #:columns name) i))
  ;; x = (1 2 3 4 5)
  (check-equal? (c "cs" 4) 15)        ; 1+2+3+4+5
  (check-equal? (c "csr" 0) 15)       ; reversed cumulative sum
  (check-equal? (c "cp" 4) 120)       ; 5!
  (check-equal? (c "cmin" 4) 1)
  (check-equal? (c "cmax" 4) 5)
  (check-equal? (c "cc" 4) 5)
  (check-equal? (c "s1" 0) polars-null)   ; shifted down -> leading null
  (check-equal? (c "s1" 1) 1)
  (check-equal? (c "sm1" 4) polars-null)  ; shifted up -> trailing null
  (check-equal? (c "s1f" 0) 0)            ; vacated slot filled with 0
  (check-equal? (c "d1" 0) polars-null)
  (check-equal? (c "d1" 1) 1)             ; 2-1
  (define (columns d)
    (map (lambda (name) (series->list (ref d name))) (column-names d)))
  (define steps (dataframe (list (series '(1 3 6 10) #:name "v"))))
  (check-equal? (columns (select steps
                                 (alias (shift "v") "down")
                                 (alias (shift "v" #:n -1 #:fill-value 0) "up")
                                 (alias (diff "v") "change")))
                (list (list polars-null 1 3 6) '(3 6 10 0) (list polars-null 2 3 4)))
  (check-equal? (columns (select steps (diff "v" #:null-behavior 'drop))) '((2 3 4)))

  (check-exn (contract-violation-of 'shift) (lambda () (contracted:shift "v" #:n (expt 2 63))))

  (test-case "the reference's running-aggregate example"
    (define tally (dataframe (list (series (list 1 2 polars-null 4) #:name "n"))))
    (define running
      (select tally
              (alias (cum-sum "n") "sum") (alias (cum-prod "n") "prod")
              (alias (cum-min "n") "min") (alias (cum-max "n") "max")
              (alias (cum-count "n") "count")))
    (check-equal? (column running "sum") (list 1 3 polars-null 7))
    (check-equal? (column running "prod") (list 1 2 polars-null 8))
    (check-equal? (column running "min") (list 1 1 polars-null 1))
    (check-equal? (column running "max") (list 1 2 polars-null 4))
    (check-equal? (column running "count") '(1 2 2 3))
    (check-equal? (column (select tally (cum-sum "n" #:reverse #t)) "n") (list 7 6 polars-null 4))
    (check-exn #rx"^cum-sum: expected an Expr or column name, got 'n" (lambda () (cum-sum 'n)))))
