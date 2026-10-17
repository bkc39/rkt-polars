#lang racket/base

(module+ test
  (require rackunit
           racket/match
           (only-in polars/private/bulk series->list)
           (only-in polars/private/foreign polars-null)
           (only-in polars/private/expr
                    col dataframe-filter-expr dataframe-group-by-agg dataframe-select-exprs
                    dataframe-with-columns)
           polars/private/generic/core
           polars/private/generic/cumulative
           polars/private/generic/datetime
           polars/private/generic/math
           polars/private/generic/nullable
           polars/private/generic/operators
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
    (check-raises 'contract #rx"^drop: contract violation;\n \"nope\" not found\n"
                  (lambda () (drop frame names))))
  (check-equal? (column-names (drop frame "v")) '("s"))
  (check-equal? (drop '(1 2 3) 1) '(2 3))

  (for* ([x (list frame (series '(1 2)) (lazy frame) (col "v"))]
         [call (list (cons 'head (lambda () (head x -1)))
                     (cons 'tail (lambda () (tail x -1)))
                     (cons 'slice (lambda () (slice x 0 -1))))])
    (match-define (cons who thunk) call)
    (check-raises 'contract (regexp (format "^~a: contract violation\n  expected: natural[?]\n" who))
                  thunk))
  (check-equal? (series->list (slice (series '(1 2 3)) -2 2)) '(2 3))

  (check-raises 'contract
                (string-append "^with-column: contract violation;\n unable to add a column of "
                               "length 2 to a DataFrame of height 3\n")
                (lambda () (with-column frame (series '(1 2) #:name "w"))))
  (check-equal? (series->list (ref (with-column frame (series '(9) #:name "w")) "w")) '(9 9 9))

  (check-raises 'contract #rx"^rename: contract violation;\n \"nope\" not found\n"
                (lambda () (rename frame "nope" "x")))
  (check-raises 'contract #rx"^rename: contract violation;\n column 's' is duplicate\n"
                (lambda () (rename frame "v" "s")))
  (check-equal? (column-names (rename frame "v" "v")) '("v" "s"))

  (check-raises 'polars #rx"^ref: \"nope\" not found$" (lambda () (ref frame "nope")))
  (check-raises 'contract #rx"^ref: column index out of range\n  index: 9\n  width: 2$"
                (lambda () (ref frame 9)))
  (check-raises 'polars #rx"^ref: [^\n]*unable to find column \"nope\""
                (lambda () (ref frame '("v" "nope"))))
  (check-equal? (column-names (ref frame '("s" 0))) '("s" "v"))

  (check-raises 'contract
                (string-append "^dataframe: contract violation\n  could not create a new DataFrame: "
                               "height of column 'b' [(]2[)] does not match height of column 'a' "
                               "[(]3[)]\n")
                (lambda () (dataframe (list (series '(1 2 3) #:name "a") (series '(1 2) #:name "b")))))
  (check-raises 'contract
                (string-append "^dataframe: contract violation\n  could not create a new DataFrame: "
                               "column with name 'a' has more than one occurrence\n")
                (lambda () (dataframe (list (series '(1) #:name "a") (series '(2) #:name "a")))))

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
                    (cons 'str-slice (lambda () (str-slice "s" #\a 2)))
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
