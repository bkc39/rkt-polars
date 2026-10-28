#lang racket/base

(module+ test
  (require rackunit (only-in racket/match match-define) (only-in threading ~>)
           (only-in polars/private/bulk series->list)
           (only-in polars/private/foreign polars-null)
           (only-in polars/private/generic/core dataframe ref series)
           (only-in polars/private/generic/reductions alias)
           (only-in polars/private/generic/reshape select with-columns)
           (only-in polars/private/generic/predicates
                    is-duplicated is-first-distinct is-in is-last-distinct is-unique)
           (only-in (submod polars/private/generic/predicates internal) is-between))
  (define df (dataframe (list (series '(1 2 2 3 5 5 8) #:name "x" #:dtype 'i64))))
  (define out
    (~> df (with-columns
             (alias (is-in "x" '(2 3 8)) "in")
             (alias (is-between "x" 2 5) "btw")
             (alias (is-between "x" 2 5 #:closed 'left) "btw_l")
             (alias (is-unique "x") "uniq")
             (alias (is-duplicated "x") "dup")
             (alias (is-first-distinct "x") "first")
             (alias (is-last-distinct "x") "last"))))
  (define (c name i) (ref (ref out #:columns name) i))
  ;; x = (1 2 2 3 5 5 8)
  (check-equal? (c "in" 0) #f)      ; 1 not in (2 3 8)
  (check-equal? (c "in" 1) #t)      ; 2 in
  (check-equal? (c "btw" 1) #t)     ; 2 in [2,5]
  (check-equal? (c "btw" 4) #t)     ; 5 in [2,5]
  (check-equal? (c "btw_l" 4) #f)   ; 5 not in [2,5)
  (check-equal? (c "uniq" 0) #t)    ; 1 appears once
  (check-equal? (c "uniq" 1) #f)    ; 2 appears twice
  (check-equal? (c "dup" 1) #t)
  (check-equal? (c "first" 1) #t)   ; first 2
  (check-equal? (c "first" 2) #f)   ; second 2
  (check-equal? (c "last" 1) #f)
  (check-equal? (c "last" 2) #t)    ; last 2

  (define carriers (dataframe (list (series '(UA AA UA B6) #:name "carrier"))))
  (check-equal? (for/list ([x (~> carriers
                                  (with-columns (alias (is-in "carrier" '(AA B6)) "in"))
                                  (ref "in"))])
                  x)
                '(#f #t #f #t))
  (define gappy (dataframe (list (series (list 1 polars-null 3) #:name "x"))))
  (define (membership rhs)
    (~> gappy (select (is-in "x" rhs)) (ref "x") series->list))
  (check-equal? (membership (list polars-null)) (list #f polars-null #f))
  (check-equal? (membership (list 1 polars-null)) (list #t polars-null #f))
  (check-exn #rx"^is-in: contract violation;\n the list mixes integers and floats"
             (lambda () (membership (list 1.0 polars-null 3))))
  (for ([rhs (list (list 1 2.5) (list 2.5 1) (list 1 1/2) (list (expt 2 63) 2.5) (list 1 +nan.0))])
    (match-define (or (list (? exact-integer? integer) float) (list float integer)) rhs)
    (check-exn (lambda (e)
                 (and (exn:fail:contract? e)
                      (regexp-match?
                       (regexp (format (string-append "^is-in: contract violation;\n"
                                                      " the list mixes integers and floats, "
                                                      "which have no common dtype\n"
                                                      "  integer: ~a\n  float: ~a\n  given: ")
                                       integer
                                       (regexp-quote (format "~a" float))))
                       (exn-message e))))
               (lambda () (membership rhs))
               (format "~a" rhs)))
  (check-equal? (membership (list 1.0 2.5)) (list #t polars-null #f))
  (check-equal? (membership (list 1.0 polars-null 3.0)) (list #t polars-null #t))
  (check-equal? (~> (dataframe (list (series '(0.5 1.0) #:name "f")))
                    (select (is-in "f" (list 0.25 1/2)))
                    (ref "f")
                    series->list)
                '(#t #f))
  (check-exn exn:fail:contract?
             (lambda ()
               (~> (dataframe (list (series (list (add1 (expt 2 63))) #:name "u" #:dtype 'u64)))
                   (select (is-in "u" (list (expt 2 63) 2.5))))))
  (check-equal? (membership '()) (list #f polars-null #f))
  (check-equal? (membership (list (expt 2 63) 3)) (list #f polars-null #t))
  (check-exn #rx"^is-in: contract violation\n" (lambda () (membership (list -1 (expt 2 63)))))
  (check-exn #rx"^is-in: contract violation\n  expected: [(]or/c Expr-ptr[?] series[?] "
             (lambda () (is-in "x" 5)))
  (for ([column (list (series (list "a" polars-null) #:name "x")
                      (series (list #t polars-null) #:name "x")
                      (series (list polars-null polars-null) #:name "x"))]
        [expected (list (list #f polars-null) (list #f polars-null)
                        (list polars-null polars-null))])
    (check-equal? (~> (dataframe (list column)) (select (is-in "x" '())) (ref "x") series->list)
                  expected))
  (for ([lower (list polars-null 1 polars-null)]
        [upper (list 5 polars-null polars-null)])
    (check-equal? (~> gappy (select (is-between "x" lower upper)) (ref "x") series->list)
                  (list polars-null polars-null polars-null)))
  (check-equal? (~> gappy (select (is-between "x" 2 5)) (ref "x") series->list)
                (list #f polars-null #t))
  (check-equal? (~> carriers (select (is-in "carrier" (list polars-null 'UA))) (ref "carrier")
                    series->list)
                '(#t #f #t #f))
  (define wide
    (dataframe (list (series (list (expt 2 63) 1 2) #:name "u" #:dtype 'u64)
                     (series '(1 2 3) #:name "i"))))
  (for ([row (list (list "u" (list (expt 2 63) 1) '(#t #t #f))
                   (list "u" (list (sub1 (expt 2 64)) polars-null 2) '(#f #f #t))
                   (list "i" (list (expt 2 63)) '(#f #f #f))
                   (list "i" (list (sub1 (expt 2 64)) 3) '(#f #f #t)))])
    (match-define (list name rhs expected) row)
    (check-equal? (~> wide (select (is-in name rhs)) (ref name) series->list) expected
                  (format "~a ~a" name rhs)))
  (for ([rhs (list (list -1 (expt 2 63)) (list (expt 2 64)) (list (sub1 (- (expt 2 63)))))])
    (check-exn (regexp (string-append "^is-in: contract violation\n  expected: [(]or/c [(]listof "
                                      "[(]integer-in -9223372036854775808 9223372036854775807[)][)] "
                                      "[(]listof [(]integer-in 0 18446744073709551615[)][)][)]\n"))
               (lambda () (is-in "i" rhs))
               (format "~a" rhs))))
