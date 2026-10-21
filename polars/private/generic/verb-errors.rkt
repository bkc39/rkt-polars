#lang racket/base

(module+ test
  (require rackunit
           racket/match
           (prefix-in rkt: (only-in racket/base max min))
           (only-in polars/private/bulk series->list)
           (only-in polars/private/foreign polars-null series-name)
           (only-in polars/private/expr
                    col dataframe-filter-expr dataframe-group-by-agg dataframe-select-exprs
                    dataframe-with-columns)
           polars/private/generic/core
           polars/private/generic/cumulative
           polars/private/generic/datetime
           polars/private/generic/math
           polars/private/generic/nullable
           polars/private/generic/operators
           (only-in polars/private/generic/ordering sort)
           polars/private/generic/predicates
           polars/private/generic/reductions
           polars/private/generic/reshape
           polars/private/generic/strings)

  (define (raised thunk)
    (with-handlers ([exn:fail? (lambda (e) (list (if (exn:fail:contract? e) 'contract 'polars)
                                                  (exn-message e)))])
      (thunk)
      #f))

  (define (check-raises kind rx thunk)
    (match (raised thunk)
      [(list got message)
       (check-equal? got kind message)
       (check-regexp-match rx message)]
      [#f (fail (format "expected ~a ~s, nothing raised" kind rx))]))

  (define frame (dataframe (list (series '(1 2 3) #:name "v") (series '("a" "b" "c") #:name "s"))))

  (check-raises 'polars #rx"^filter: [^\n]*filter's length: 2 differs from that of the series: 3$"
                (lambda () (filter frame (series '(#t #f)))))
  (check-raises 'polars #rx"^filter: filter predicate must be of type `Boolean`, got `Int64`$"
                (lambda () (filter frame (series '(1 2 3)))))
  (check-equal? (height (filter frame (series (list #t polars-null #t)))) 2)
  (check-equal? (height (filter frame (series '(#t)))) 3)

  (for ([names (list "nope" '("v" "nope"))])
    (check-raises 'contract #rx"^drop: \"nope\" not found$" (lambda () (drop frame names))))
  (check-raises 'contract #rx"^drop: \"v\" named more than once$"
                (lambda () (drop frame '("v" "v"))))
  (check-equal? (column-names (drop frame "v")) '("s"))
  (check-equal? (drop '(1 2 3) 1) '(2 3))

  (define count-range "[(]integer-in 0 18446744073709551615[)]")
  (define offset-range "[(]integer-in -9223372036854775808 9223372036854775807[)]")
  (for* ([x (list frame (series '(1 2)) (lazy frame) (col "v"))]
         [call (list (list 'head count-range (lambda () (head x -1)))
                     (list 'tail count-range (lambda () (tail x -1)))
                     (list 'slice count-range (lambda () (slice x 0 -1)))
                     (list 'head count-range (lambda () (head x (expt 2 64))))
                     (list 'tail count-range (lambda () (tail x (expt 2 64))))
                     (list 'slice count-range (lambda () (slice x 0 (expt 2 64))))
                     (list 'slice offset-range (lambda () (slice x (expt 2 63) 1)))
                     (list 'slice offset-range (lambda () (slice x (sub1 (- (expt 2 63))) 1))))])
    (match-define (list who range thunk) call)
    (check-raises 'contract (regexp (format "^~a: contract violation\n  expected: ~a\n" who range))
                  thunk))

  (define edge-counts
    (list 0 2 3 4 (sub1 (expt 2 32)) (expt 2 32) (sub1 (expt 2 63)) (expt 2 63)
          (sub1 (expt 2 64))))
  (define edge-offsets
    (list (- (expt 2 63)) (- 1 (expt 2 63)) (- (expt 2 32)) (- 1 (expt 2 32)) -4 -3 -1 0 2 3
          (sub1 (expt 2 32)) (sub1 (expt 2 63))))
  (define (rows-of v)
    (match v
      [(? series?) (series->list v)]
      [(? dataframe?) (series->list (ref v "v"))]
      [(? lazyframe?) (rows-of (collect v))]
      [_ (rows-of (select frame v))]))
  (define (same-rows-everywhere label pick)
    (define expected (rows-of (pick frame)))
    (for ([x (list (ref frame "v") (lazy frame) (col "v"))])
      (check-equal? (rows-of (pick x)) expected (format "~a on ~a" label x))))
  (for ([n (in-list edge-counts)])
    (same-rows-everywhere (list 'head n) (lambda (x) (head x n)))
    (same-rows-everywhere (list 'tail n) (lambda (x) (tail x n))))
  (for* ([offset (in-list edge-offsets)] [n (in-list edge-counts)])
    (same-rows-everywhere (list 'slice offset n) (lambda (x) (slice x offset n))))
  (check-equal? (series->list (slice (series '(1 2 3)) -2 2)) '(2 3))

  (define grouped
    (dataframe (list (series '(5 1 7 3 4 6 2) #:name "v")
                     (series '("a" "b" "a" "a" "b" "a" "b") #:name "g"))))
  (define group-values '(("a" 5 7 3 6) ("b" 1 4 2)))
  (define (slice-list xs offset n)
    (define l (length xs))
    (define (clamp k) (rkt:max 0 (rkt:min k l)))
    (define from (if (negative? offset) (+ l offset) offset))
    (define start (clamp from))
    (define stop (clamp (+ from n)))
    (for/list ([x (in-list xs)] [i (in-naturals)] #:when (and (<= start i) (< i stop))) x))
  (define (same-rows-per-group label pick pick-list)
    (define result
      (sort (agg (group-by grouped "g")
                 (alias (min (pick (col "v"))) "lo")
                 (alias (max (pick (col "v"))) "hi")
                 (alias (count (pick (col "v"))) "n"))
            "g"))
    (define expected
      (for/list ([group (in-list group-values)])
        (match-define (cons g xs) group)
        (define picked (pick-list xs))
        (if (null? picked)
            (list g polars-null polars-null 0)
            (list g (apply rkt:min picked) (apply rkt:max picked) (length picked)))))
    (check-equal? (apply map list (for/list ([name (in-list '("g" "lo" "hi" "n"))])
                                    (series->list (ref result name))))
                  expected
                  (format "~a per group" label)))
  (for ([n (in-list edge-counts)])
    (same-rows-per-group (list 'head n) (lambda (x) (head x n)) (lambda (xs) (slice-list xs 0 n)))
    (same-rows-per-group (list 'tail n)
                         (lambda (x) (tail x n))
                         (lambda (xs) (slice-list xs (- (length xs) (rkt:min n (length xs))) n))))
  (for* ([offset (in-list edge-offsets)] [n (in-list edge-counts)])
    (same-rows-per-group (list 'slice offset n)
                         (lambda (x) (slice x offset n))
                         (lambda (xs) (slice-list xs offset n))))

  (check-raises 'contract
                #rx"^with-column: unable to add a column of length 2 to a DataFrame of height 3$"
                (lambda () (with-column frame (series '(1 2) #:name "w"))))
  (check-raises 'contract
                #rx"^with-column: unable to add a column of length 2 to a DataFrame of height 0$"
                (lambda () (with-column (head frame 0) (series '(1 2) #:name "w"))))
  (check-equal? (shape (with-column (dataframe '()) (series '(1 2) #:name "w"))) '(2 1))
  (check-equal? (series->list (ref (with-column frame (series '(9) #:name "w")) "w")) '(9 9 9))

  (check-raises 'contract #rx"^rename: \"nope\" not found$" (lambda () (rename frame "nope" "x")))
  (check-raises 'contract #rx"^rename: column 's' is duplicate$" (lambda () (rename frame "v" "s")))
  (check-raises 'contract #rx"^rename: contract violation;\n renaming a dataframe column needs"
                (lambda () (rename frame "v")))
  (check-equal? (column-names (rename frame "v" "v")) '("v" "s"))

  (check-raises 'polars #rx"^ref: \"nope\" not found$" (lambda () (ref frame "nope")))
  (check-raises 'contract #rx"^ref: column index out of range\n  index: 9\n  width: 2$"
                (lambda () (ref frame 9)))
  (check-raises 'contract #rx"^ref: \"nope\" not found$" (lambda () (ref frame '("v" "nope"))))
  (check-raises 'contract #rx"^ref: \"v\" named more than once$" (lambda () (ref frame '("v" 0))))
  (check-equal? (column-names (ref frame '("s" 0))) '("s" "v"))
  (check-equal? (shape (ref frame '())) '(3 0))
  (define patterned
    (dataframe (list (series '(1) #:name "^a$") (series '(2) #:name "ab") (series '(3) #:name "*"))))
  (check-equal? (column-names (ref patterned '("^a$"))) '("^a$"))
  (check-equal? (column-names (ref patterned '("*" "ab"))) '("*" "ab"))
  (check-raises 'contract #rx"^ref: \"[\\^]a[.][*][$]\" not found$"
                (lambda () (ref patterned '("^a.*$"))))
  (check-raises 'polars #rx"^select: [^\n]*duplicate[^\n]*with `[(]alias expr \"new-name\"[)]` to"
                (lambda () (select frame "v" "v")))

  (check-raises 'contract
                (string-append "^dataframe: could not create a new DataFrame: height of column 'b' "
                               "[(]2[)] does not match height of column 'a' [(]3[)]$")
                (lambda () (dataframe (list (series '(1 2 3) #:name "a") (series '(1 2) #:name "b")))))
  (check-raises 'contract
                (string-append "^dataframe: could not create a new DataFrame: column with name 'a' "
                               "has more than one occurrence$")
                (lambda () (dataframe (list (series '(1) #:name "a") (series '(2) #:name "a")))))

  (define (columns-of d) (for/list ([name (column-names d)]) (cons name (series->list (ref d name)))))
  (define top (dataframe (list (series '(1 2) #:name "v"))))
  (check-equal? (columns-of (with-column top (series '(10 20) #:name "w"))) '(("v" 1 2) ("w" 10 20)))
  (check-equal? (columns-of (with-column top (series '(0) #:name "v"))) '(("v" 0 0)))
  (check-raises 'contract
                #rx"^with-column: unable to add a column of length 3 to a DataFrame of height 2$"
                (lambda () (with-column top (series '(1 2 3) #:name "w"))))
  (define nums (dataframe (list (series '(1 2 3 4 5) #:name "v"))))
  (check-equal? (columns-of (slice nums -2 (expt 2 40))) '(("v" 4 5)))
  (check-raises 'contract #rx"^head: contract violation\n" (lambda () (head nums -1)))
  (define pair (dataframe (list (series '(1) #:name "a") (series '(2) #:name "b"))))
  (check-equal? (column-names (drop pair "a")) '("b"))
  (check-raises 'contract #rx"^drop: \"nope\" not found$" (lambda () (drop pair '("a" "nope"))))
  (define sales
    (dataframe (list (series '("a" "a" "b") #:name "store")
                     (series '("q1" "q2" "q1") #:name "quarter")
                     (series '(10 20 30) #:name "sales"))))
  (define by-quarter
    (sort (pivot sales #:on '("quarter") #:index '("store") #:values '("sales") #:agg 'sum)
          "store"))
  (check-equal? (columns-of by-quarter) '(("store" "a" "b") ("q1" 10 30) ("q2" 20 0)))
  (check-raises 'polars #rx"^pivot: cannot pivot the dataframe: [^\n]*\"nope\" not found$"
                (lambda () (pivot sales #:on '("nope") #:index '("store") #:values '("sales"))))
  (check-equal? (columns-of (unpivot by-quarter #:on '("q1" "q2") #:index '("store")))
                '(("store" "a" "b" "a" "b") ("variable" "q1" "q1" "q2" "q2")
                  ("value" 10 30 20 0)))
  (check-raises 'polars #rx"^unpivot: cannot unpivot the dataframe: [^\n]*\"nope\" not found$"
                (lambda () (unpivot by-quarter #:on '("nope") #:index '("store"))))
  (check-equal? (series-name (rename (series '(1) #:name "a") "b")) "b")
  (define named (dataframe (list (series '(1) #:name "a") (series '(2) #:name "b"))))
  (check-equal? (column-names (rename named "a" "z")) '("z" "b"))
  (check-raises 'contract #rx"^rename: column 'b' is duplicate$" (lambda () (rename named "a" "b")))
  (check-raises 'contract #rx"^dataframe: [^\n]*column with name 'k' has more than one occurrence$"
                (lambda () (dataframe (list (series '(1) #:name "k") (series '(2) #:name "k")))))
  (define starred (dataframe (list (series '(1) #:name "*") (series '(2) #:name "b"))))
  (check-equal? (column-names (ref starred '("*"))) '("*"))
  (check-raises 'contract #rx"^ref: \"b\" named more than once$" (lambda () (ref starred '("b" 1))))

  (check-raises 'contract #rx"^group-by: contract violation\n" (lambda () (group-by frame 5)))
  (check-raises 'contract #rx"^agg: contract violation\n" (lambda () (agg (group-by frame "s") "v")))
  (check-raises 'contract #rx"^pivot: contract violation\n"
                (lambda () (pivot frame #:on "s" #:index '("v") #:values '("v"))))
  (check-raises 'contract #rx"^unpivot: contract violation\n"
                (lambda () (unpivot frame #:on "v" #:index '("s"))))

  (define not-a-literal "contract violation\n  expected: [(]or/c boolean[?] [(]integer-in ")
  (for ([call (list (cons 'fill-null (lambda () (fill-null (col "v") #\a)))
                    (cons 'fill-nan (lambda () (fill-nan (col "v") #\a)))
                    (cons 'is-between (lambda () (is-between (col "v") #\a 3)))
                    (cons 'is-between (lambda () (is-between (col "v") 1 #\a)))
                    (cons 'pow (lambda () (pow (col "v") #\a)))
                    (cons 'clip (lambda () (clip (col "v") #:lower #\a)))
                    (cons 'clip (lambda () (clip (col "v") #:upper #\a)))
                    (cons 'shift (lambda () (shift (col "v") #:fill-value #\a)))
                    (cons 'dt-truncate (lambda () (dt-truncate (col "v") #\a)))
                    (cons 'str-contains (lambda () (str-contains "s" #\a)))
                    (cons 'str-starts-with (lambda () (str-starts-with "s" #\a)))
                    (cons 'str-ends-with (lambda () (str-ends-with "s" #\a)))
                    (cons 'str-strip-chars (lambda () (str-strip-chars "s" #\a)))
                    (cons 'str-strip-prefix (lambda () (str-strip-prefix "s" #\a)))
                    (cons 'str-strip-suffix (lambda () (str-strip-suffix "s" #\a)))
                    (cons 'str-replace (lambda () (str-replace "s" #\a "b")))
                    (cons 'str-replace (lambda () (str-replace "s" "a" #\b)))
                    (cons 'str-replace-all (lambda () (str-replace-all "s" #\a "b")))
                    (cons 'str-extract (lambda () (str-extract "s" #\a)))
                    (cons 'str-head (lambda () (str-head "s" #\a)))
                    (cons 'str-tail (lambda () (str-tail "s" #\a)))
                    (cons 'str-find (lambda () (str-find "s" #\a)))
                    (cons 'str-find-literal (lambda () (str-find-literal "s" #\a)))
                    (cons 'str-count-matches (lambda () (str-count-matches "s" #\a)))
                    (cons 'then (lambda () (then (p-when (> (col "v") 1)) #\a)))
                    (cons 'otherwise (lambda () (otherwise (then (p-when (> (col "v") 1)) 1) #\a)))
                    (cons 'else-when
                          (lambda () (else-when (then (p-when (> (col "v") 1)) 1) #\a)))
                    (cons 'when (lambda () (p-when #\a))))])
    (match-define (cons who thunk) call)
    (check-raises 'contract (regexp (string-append "^" (regexp-quote (symbol->string who)) ": "
                                                   not-a-literal))
                  thunk))
  (check-raises 'contract #rx"^is-between: contract violation\n  expected: [(]or/c [(]quote both[)]"
                (lambda () (is-between (col "v") 1 2 #:closed 'bogus)))
  (check-raises 'contract #rx"^alias: contract violation\n  expected: col-expr/c\n  given: #\\\\a\n"
                (lambda () (alias #\a "z")))
  (check-equal? (column-names (select frame (alias "v" "z"))) '("z"))
  (check-equal? (series->list (ref (select frame (str-strip-chars "s")) "s")) '("a" "b" "c"))

  (for ([call (list (cons 'dataframe-select-exprs
                          (lambda () (dataframe-select-exprs frame (list (col "nope")))))
                    (cons 'dataframe-with-columns
                          (lambda () (dataframe-with-columns frame (list (col "nope")))))
                    (cons 'dataframe-filter-expr
                          (lambda () (dataframe-filter-expr frame (col "nope"))))
                    (cons 'dataframe-group-by-agg
                          (lambda () (dataframe-group-by-agg frame (list "nope") (list (sum "v"))))))])
    (match-define (cons who thunk) call)
    (check-raises 'polars (regexp (format "^~a: [^\n]*unable to find column \"nope\"" who)) thunk)))
