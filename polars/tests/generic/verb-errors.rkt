#lang racket/base

(module+ test
  (require rackunit
           racket/match
           (only-in gregor datetime)
           (only-in gregor/private/moment-base make-moment)
           (prefix-in rkt: (only-in racket/base max min))
           (only-in racket/contract/base contract-name has-contract? or/c)
           (only-in racket/list remove-duplicates)
           (only-in racket/path file-name-from-path)
           (only-in racket/string string-contains? string-prefix?)
           (only-in polars/private/bulk series->list)
           (only-in polars/private/c-integer int64/c size/c uint32/c)
           (only-in polars/private/expr-core expr->string lit-integer/c)
           (only-in polars/private/foreign
                    last-error-message polars-null series-add/who series-cast
                    series-cast-datetime-tz/raw series-dt-convert-time-zone/raw
                    series-dt-replace-time-zone/raw series-name time-unit-symbol->code
                    time-zone-name/c)
           (only-in (submod polars/private/foreign internal)
                    series-mean-f64/who series-sum-i32/who)
           (only-in polars/private/expr
                    col dataframe-filter-expr dataframe-group-by-agg dataframe-select-exprs
                    dataframe-sort-exprs dataframe-with-columns expr-cast expr-clip
                    expr-dtype-col expr-fill-nan expr-fill-null expr-filter expr-gather
                    expr-is-between expr-pow expr-shift expr-when Expr-ptr? null-behavior/c)
           (only-in polars/private/expr-dt expr-dt-truncate)
           (only-in polars/private/expr-str
                    expr-str-contains expr-str-count-matches expr-str-ends-with expr-str-extract
                    expr-str-find expr-str-find-literal expr-str-head expr-str-replace
                    expr-str-replace-all expr-str-slice expr-str-starts-with expr-str-strip-chars
                    expr-str-strip-chars-end expr-str-strip-chars-start expr-str-strip-prefix
                    expr-str-strip-suffix expr-str-tail)
           (only-in (submod polars/private/expr internal) expr-cast-datetime-tz/raw)
           (only-in (submod polars/private/expr-core internal)
                    expr-dtype-col-datetime-tz/raw expr-lit-datetime-tz/raw)
           (only-in (submod polars/private/expr-dt internal)
                    expr-dt-convert-time-zone/raw expr-dt-replace-time-zone/raw)
           (only-in (submod polars/private/expr-str internal) expr-str->datetime-tz/raw)
           (only-in polars/private/generic/core
                    column-names dataframe dataframe? dtype height lazyframe? len ref series series?
                    shape)
           (only-in polars/private/generic/cumulative diff shift)
           (only-in polars/private/generic/datetime
                    dt-convert-time-zone dt-replace-time-zone dt-strftime dt-timestamp
                    dt-truncate)
           (only-in polars/private/generic/logical p-not p-xor)
           (only-in polars/private/generic/math
                    clip [log p-log] p-abs p-exp p-floor p-sqrt pow round)
           (only-in polars/private/generic/nullable
                    backward-fill fill-nan fill-null forward-fill is-null)
           (only-in polars/private/generic/operators
                    < <= > else-when otherwise p* p+ p- p/ p-when then)
           (only-in polars/private/generic/ordering gather sort)
           (only-in polars/private/generic/predicates is-between)
           (only-in polars/private/generic/reductions alias count first last max min sum)
           (only-in polars/private/generic/reshape
                    agg cast collect drop explain filter group-by head lazy pivot rename select
                    slice tail unpivot with-column with-columns)
           (only-in polars/private/generic/strings
                    str->date str->datetime str->time str-contains str-count-matches
                    str-ends-with str-extract str-find str-find-literal str-head str-replace
                    str-replace-all str-starts-with str-strip-chars str-strip-prefix
                    str-strip-suffix str-tail)
           (only-in polars/tests/generic/test-fixtures nul-expected)
           (only-in polars/tests/test-helpers
                    not-utf-8-expected not-utf-8-names polars-sources read-source refusal
                    refusal-misses refused))

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

  (check-equal?
   (refusal-misses
    (append
     (for*/list ([x (list frame (series '(1 2)) (lazy frame) (col "v"))]
                 [row (list (refusal 'head size/c -1 (head x -1))
                            (refusal 'tail size/c -1 (tail x -1))
                            (refusal 'slice size/c -1 (slice x 0 -1))
                            (refusal 'head size/c (expt 2 64) (head x (expt 2 64)))
                            (refusal 'tail size/c (expt 2 64) (tail x (expt 2 64)))
                            (refusal 'slice size/c (expt 2 64) (slice x 0 (expt 2 64)))
                            (refusal 'slice int64/c (expt 2 63) (slice x (expt 2 63) 1))
                            (refusal 'slice int64/c (sub1 (- (expt 2 63)))
                                     (slice x (sub1 (- (expt 2 63))) 1)))])
       row)
     (list (refusal 'shift int64/c (expt 2 63) (shift "v" #:n (expt 2 63)))
           (refusal 'diff int64/c (sub1 (- (expt 2 63))) (diff "v" #:n (sub1 (- (expt 2 63)))))
           (refusal 'diff null-behavior/c 'keep (diff "v" #:null-behavior 'keep))
           (refusal 'forward-fill (or/c #f uint32/c) (expt 2 32)
                    (forward-fill "v" #:limit (expt 2 32)))
           (refusal 'backward-fill (or/c #f uint32/c) -1 (backward-fill "v" #:limit -1))
           (refusal 'str-extract size/c (expt 2 64)
                    (str-extract "s" "(a)" #:group-index (expt 2 64)))
           (refusal 'round uint32/c -1 (round "v" #:decimals -1) #:unblamed)
           (refusal 'round uint32/c 1.5 (round "v" #:decimals 1.5) #:unblamed)
           (refusal 'round uint32/c (expt 2 32) (round (col "v") #:decimals (expt 2 32))
                    #:unblamed)
           (refusal 'round number? 'x (round 2.5 #:decimals 'x) #:unblamed)
           (refusal 'round (or/c Expr-ptr? string? number?) #\a (round #\a #:decimals -1)
                    #:unblamed)
           (refusal 'round (or/c Expr-ptr? string? number?) #\a (round #\a) #:unblamed))))
   '())
  (check-raises 'contract
                (regexp (string-append "^round: contract violation\n"
                                       "  expected: \\(or/c Expr-ptr\\? string\\? number\\?\\)\n"
                                       "  given: \n   shape: \\(1,\\)"))
                (lambda () (round (series '(1.0)))))
  (check-false (has-contract? round))
  (check-equal? (list (round 1234 #:decimals -2) (round 2.5) (round 2.345 #:decimals 1))
                (list 1200 2.0 2.3))
  (check-equal? (series->list (ref (select (dataframe (list (series '(1.25 2.5) #:name "v")))
                                           (round "v" #:decimals 1))
                                   "v"))
                '(1.2 2.5))

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

  (check-raises 'contract #rx"^ref: \"nope\" not found$" (lambda () (ref frame "nope")))
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
  (for ([name (list string->bytes/utf-8 string->path)])
    (check-equal? (column-names (drop pair (name "a"))) '("b"))
    (check-equal? (column-names (drop pair (list (name "a")))) '("b"))
    (check-raises 'contract #rx"^drop: \"nope\" not found$" (lambda () (drop pair (name "nope"))))
    (check-raises 'contract #rx"^drop: \"a\" named more than once$"
                  (lambda () (drop pair (list "a" (name "a")))))
    (check-equal? (columns-of (sort (pivot sales #:on (list (name "quarter"))
                                           #:index (list (name "store"))
                                           #:values (list (name "sales"))
                                           #:agg 'sum)
                                    "store"))
                  (columns-of by-quarter))
    (check-equal? (columns-of (unpivot by-quarter #:on (list (name "q1") (name "q2"))
                                       #:index (list (name "store"))))
                  (columns-of (unpivot by-quarter #:on '("q1" "q2") #:index '("store")))))
  (define named (dataframe (list (series '(1) #:name "a") (series '(2) #:name "b"))))
  (for ([name (list string->bytes/utf-8 string->path)])
    (check-equal? (series-name (rename (series '(1) #:name "a") (name "b"))) "b")
    (check-equal? (column-names (rename named (name "a") (name "z"))) '("z" "b"))
    (check-raises 'contract #rx"^rename: \"nope\" not found$"
                  (lambda () (rename named (name "nope") "z")))
    (check-raises 'contract #rx"^rename: column 'b' is duplicate$"
                  (lambda () (rename named "a" (name "b")))))
  (for* ([bad (in-list not-utf-8-names)]
         [entry (in-list
                (list (list 'drop bad (lambda () (drop pair bad)))
                      (list 'drop (list "a" bad) (lambda () (drop pair (list "a" bad))))
                      (list 'pivot bad (lambda () (pivot sales #:on (list bad) #:index '("store")
                                                         #:values '("sales"))))
                      (list 'unpivot bad
                            (lambda () (unpivot by-quarter #:on '("q1") #:index (list bad))))
                      (list 'rename bad (lambda () (rename named bad "z")))
                      (list 'rename bad (lambda () (rename (series '(1) #:name "a") bad)))))])
    (match-define (list who given thunk) entry)
    (check-raises 'contract (refused who given #:expected not-utf-8-expected) thunk))
  (check-raises 'contract #rx"^drop: contract violation\n" (lambda () (drop pair '(a))))
  (check-raises 'contract #rx"^pivot: contract violation\n"
                (lambda () (pivot sales #:on '(quarter) #:index '("store") #:values '("sales"))))
  (check-raises 'contract #rx"^unpivot: contract violation\n"
                (lambda () (unpivot by-quarter #:on '("q1") #:index '(store))))
  (check-equal? (series-name (rename (series '(1) #:name "a") "b")) "b")
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

  (define not-a-literal
    (string-append "contract violation\n  expected: "
                   (regexp-quote (format "(or/c boolean? ~s " (contract-name lit-integer/c)))))
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
                          (lambda () (dataframe-group-by-agg frame (list "nope") (list (sum "v")))))
                    (cons 'dataframe-sort-exprs
                          (lambda () (dataframe-sort-exprs frame (list "nope")))))])
    (match-define (cons who thunk) call)
    (check-raises 'polars (regexp (format "^~a: [^\n]*unable to find column \"nope\"" who)) thunk))

  (define nul-zone "UTC\u0000x")
  (define nul-zoned `(datetime microseconds ,nul-zone))
  (define wall (series (list (datetime 2020 1 2 3)) #:name "t"))
  (define optional-zone/c (or/c #f time-zone-name/c))
  (check-equal?
   (refusal-misses
    (list (refusal 'dt-convert-time-zone time-zone-name/c nul-zone
                   (dt-convert-time-zone wall nul-zone))
          (refusal 'dt-convert-time-zone time-zone-name/c nul-zone
                   (dt-convert-time-zone "t" nul-zone))
          (refusal 'dt-replace-time-zone optional-zone/c nul-zone
                   (dt-replace-time-zone wall nul-zone))
          (refusal 'dt-replace-time-zone optional-zone/c nul-zone
                   (dt-replace-time-zone "t" nul-zone))
          (refusal 'str->datetime optional-zone/c nul-zone
                   (str->datetime "t" #:time-zone nul-zone))
          (refusal 'cast time-zone-name/c nul-zone (cast wall nul-zoned))
          (refusal 'cast time-zone-name/c nul-zone (cast (col "t") nul-zoned))
          (refusal 'cast time-zone-name/c nul-zone (cast "t" nul-zoned))
          (refusal 'series time-zone-name/c nul-zone
                   (series (list (datetime 2020 1 2 3)) #:dtype nul-zoned))
          (refusal 'col time-zone-name/c nul-zone (col nul-zoned))
          (refusal 'series-cast time-zone-name/c nul-zone (series-cast wall nul-zoned))
          (refusal 'expr-cast time-zone-name/c nul-zone (expr-cast (col "t") nul-zoned))
          (refusal 'expr-dtype-col time-zone-name/c nul-zone (expr-dtype-col nul-zoned))))
   '())
  (for ([row (in-list (nul-expected 'zones))])
    (match-define (list _ _ outcome) row)
    (check-equal? outcome '(raises ComputeError) (format "~s" row)))

  (define micro (time-unit-symbol->code 'microseconds))
  (define clock (col "t"))
  (define (failed-zone-reason)
    (series-dt-convert-time-zone/raw wall "Mars/Base")
    (last-error-message))
  (for ([raw (list (lambda () (series-cast-datetime-tz/raw wall micro nul-zone))
                   (lambda () (series-dt-convert-time-zone/raw wall nul-zone))
                   (lambda () (series-dt-replace-time-zone/raw wall nul-zone "raise" "raise"))
                   (lambda () (series-dt-replace-time-zone/raw wall "UTC" "ra\u0000ise" "raise"))
                   (lambda () (series-dt-replace-time-zone/raw wall "UTC" "raise" "ra\u0000ise"))
                   (lambda () (expr-cast-datetime-tz/raw clock micro nul-zone))
                   (lambda () (expr-dt-convert-time-zone/raw clock nul-zone))
                   (lambda () (expr-dt-replace-time-zone/raw clock nul-zone "raise" "raise"))
                   (lambda () (expr-dt-replace-time-zone/raw clock "UTC" "ra\u0000ise" "raise"))
                   (lambda () (expr-dt-replace-time-zone/raw clock "UTC" "raise" "ra\u0000ise"))
                   (lambda () (expr-dtype-col-datetime-tz/raw micro nul-zone))
                   (lambda () (expr-lit-datetime-tz/raw 0 micro nul-zone))
                   (lambda () (expr-str->datetime-tz/raw clock #f micro nul-zone "raise" 1 1 1))
                   (lambda ()
                     (expr-str->datetime-tz/raw clock #f micro "UTC" "ra\u0000ise" 1 1 1)))])
    (define before (failed-zone-reason))
    (check-regexp-match #rx"Mars/Base" before)
    (check-raises 'contract
                  #rx"^_c-string: contract violation\n  expected: a string without a NUL\n"
                  raw)
    (check-equal? (last-error-message) before))

  (define (message-after prefix message)
    (and (string-prefix? message prefix) (substring message (string-length prefix))))
  (define (present-strings elements)
    (remove-duplicates (for/list ([v (in-list elements)] #:when (string? v)) v)))
  (define (enum-sources elements)
    (list (series elements #:name "c")
          (series elements #:name "c" #:dtype 'categorical)
          (series elements #:name "c"
                  #:dtype (cons 'enum (map string->symbol (present-strings elements))))))
  (define (enum-verbs table target)
    (list (cons 'select (lambda () (select table (cast "c" target))))
          (cons 'with-columns (lambda () (with-columns table (cast "c" target))))
          (cons 'filter (lambda () (filter table (is-null (cast "c" target)))))
          (cons 'agg (lambda () (agg (group-by table "g") (cast "c" target))))
          (cons 'collect (lambda () (collect (with-columns (lazy table) (cast "c" target)))))))
  (define (with-groups source)
    (dataframe (list source
                     (series (for/list ([i (in-range (len source))]) (modulo i 2)) #:name "g"))))
  (define carrier-enum '(enum UA AA))
  (define enum-cases
    (list (list carrier-enum (list "UA" polars-null "B6" "B6" "AA" polars-null))
          (list carrier-enum (cons "UA" (for/list ([i (in-range 12)]) (format "m~a" i))))
          (list carrier-enum (list "UA" "a\u0000b" "c\nd"))
          (list carrier-enum (list "Very High" "UA" "Very High"))
          (list '(enum) (list "x" "y" polars-null))
          (list carrier-enum (for/list ([i (in-range 200000)])
                               (if (zero? (modulo i 49999)) "B6" "UA")))))
  (define lazy-enum-messages
    (for*/list ([row (in-list enum-cases)]
                [source (in-list (enum-sources (cadr row)))]
                [verb (in-list (enum-verbs (with-groups source) (car row)))])
      (match-define (list target elements) row)
      (match-define (cons who run) verb)
      (match-define (list 'polars eager) (raised (lambda () (cast source target))))
      (match-define (list 'polars message) (raised run))
      (check-equal? (message-after (format "~a: " who) message)
                    (message-after "cast: " eager)
                    (format "~s on ~s" who elements))
      message))
  (check-equal? (cadr (raised (lambda ()
                                (select (dataframe (list (series '("UA" "B6") #:name "c")))
                                        (cast "c" carrier-enum)))))
                (string-append "select: "
                               (message-after "cast: "
                                              (cadr (raised (lambda ()
                                                              (cast (series '("UA" "B6"))
                                                                    carrier-enum)))))))

  (define ranks '(enum c b a))
  (define ranked-sort (sort (cast "o" ranks)))
  (check-true (string-contains? (expr->string ranked-sort) "sort"))
  (check-false (string-contains? (expr->string ranked-sort) "sort_by"))
  (define ranked
    (dataframe (list (series '(1 1 1 2 2) #:name "g") (series '("a" "c" "b" "b" "a") #:name "o"))))
  (define ranked-ends
    (sort (agg (group-by ranked "g")
               (alias (first (sort (cast "o" ranks))) "lo")
               (alias (last (sort (cast "o" ranks))) "hi"))
          "g"))
  (for ([group (in-list '(("a" "c" "b") ("b" "a")))]
        [i (in-naturals)])
    (define sorted (series->list (sort (cast (series group) ranks))))
    (check-equal? (ref (ref ranked-ends "lo") i) (car sorted))
    (check-equal? (ref (ref ranked-ends "hi") i) (car (reverse sorted))))

  (define who-plain-names
    (for*/list ([phase+exports (in-list (let-values ([(variables syntaxes)
                                                      (module->exports
                                                       '(submod polars/private/foreign internal))])
                                          variables))]
                [export (in-list (cdr phase+exports))]
                #:when (regexp-match? #rx"/who$" (symbol->string (car export))))
      (string->symbol (regexp-replace #rx"/who$" (symbol->string (car export)) ""))))
  (define (plain-calls form)
    (match form
      [(cons (? symbol? head) rest)
       (append (if (memq head who-plain-names) (list head) '()) (plain-calls rest))]
      [(cons head rest) (append (plain-calls head) (plain-calls rest))]
      [_ '()]))
  (check-not-false (memq 'series-head who-plain-names))
  (check-equal? (for*/list ([file (in-list (polars-sources #:dirs '("private/generic")))]
                            [name (in-list (plain-calls (read-source file)))])
                  (list (path->string (file-name-from-path file)) name))
                '())

  (define floats (series '(1.5 2.5) #:name "f"))
  (define strings (series '("a" "b") #:name "s"))
  (for ([call (list (lambda () (series-sum-i32/who 'v floats))
                    (lambda () (series-mean-f64/who 'v strings))
                    (lambda () (series-add/who 'v floats (series '(1.0 2.0 3.0) #:name "g"))))])
    (check-raises 'polars #rx"^v: [^\n]" call))

  (for ([call (list (cons 'expr-fill-null (lambda () (expr-fill-null (col "v") #\a)))
                    (cons 'expr-fill-nan (lambda () (expr-fill-nan (col "v") #\a)))
                    (cons 'expr-pow (lambda () (expr-pow (col "v") #\a)))
                    (cons 'expr-clip (lambda () (expr-clip (col "v") #:lower #\a)))
                    (cons 'expr-clip (lambda () (expr-clip (col "v") #:upper #\a)))
                    (cons 'expr-is-between (lambda () (expr-is-between (col "v") #\a 3)))
                    (cons 'expr-is-between (lambda () (expr-is-between (col "v") 1 #\a)))
                    (cons 'expr-shift (lambda () (expr-shift (col "v") #:fill-value #\a)))
                    (cons 'expr-filter (lambda () (expr-filter (col "v") #\a)))
                    (cons 'expr-when (lambda () (expr-when (list (list #\a 1)) #:otherwise 2)))
                    (cons 'expr-when (lambda () (expr-when (list (list #t #\a)) #:otherwise 2)))
                    (cons 'expr-when (lambda () (expr-when (list (list #t 1)) #:otherwise #\a)))
                    (cons 'expr-dt-truncate (lambda () (expr-dt-truncate (col "v") #\a)))
                    (cons 'expr-str-contains (lambda () (expr-str-contains (col "s") #\a)))
                    (cons 'expr-str-starts-with (lambda () (expr-str-starts-with (col "s") #\a)))
                    (cons 'expr-str-ends-with (lambda () (expr-str-ends-with (col "s") #\a)))
                    (cons 'expr-str-replace (lambda () (expr-str-replace (col "s") #\a "b")))
                    (cons 'expr-str-replace (lambda () (expr-str-replace (col "s") "a" #\b)))
                    (cons 'expr-str-replace-all
                          (lambda () (expr-str-replace-all (col "s") #\a "b")))
                    (cons 'expr-str-replace-all
                          (lambda () (expr-str-replace-all (col "s") "a" #\b)))
                    (cons 'expr-str-extract (lambda () (expr-str-extract (col "s") #\a)))
                    (cons 'expr-str-strip-chars (lambda () (expr-str-strip-chars (col "s") #\a)))
                    (cons 'expr-str-strip-chars-start
                          (lambda () (expr-str-strip-chars-start (col "s") #\a)))
                    (cons 'expr-str-strip-chars-end
                          (lambda () (expr-str-strip-chars-end (col "s") #\a)))
                    (cons 'expr-str-strip-prefix (lambda () (expr-str-strip-prefix (col "s") #\a)))
                    (cons 'expr-str-strip-suffix (lambda () (expr-str-strip-suffix (col "s") #\a)))
                    (cons 'expr-str-slice (lambda () (expr-str-slice (col "s") #\a)))
                    (cons 'expr-str-slice (lambda () (expr-str-slice (col "s") 0 #\a)))
                    (cons 'expr-str-head (lambda () (expr-str-head (col "s") #\a)))
                    (cons 'expr-str-tail (lambda () (expr-str-tail (col "s") #\a)))
                    (cons 'expr-str-find (lambda () (expr-str-find (col "s") #\a)))
                    (cons 'expr-str-find-literal (lambda () (expr-str-find-literal (col "s") #\a)))
                    (cons 'expr-str-count-matches
                          (lambda () (expr-str-count-matches (col "s") #\a))))])
    (match-define (cons who thunk) call)
    (check-raises 'contract (regexp (string-append "^" (regexp-quote (symbol->string who)) ": "
                                                   not-a-literal))
                  thunk))
  (define mars (make-moment (datetime 2021 3 27) 0 "Mars/Base"))
  (for ([call (list (cons 'expr-is-between (lambda () (expr-is-between (col "t") mars mars)))
                    (cons 'expr-fill-null (lambda () (expr-fill-null (col "t") mars)))
                    (cons 'expr-clip (lambda () (expr-clip (col "t") #:lower mars)))
                    (cons 'expr-str-contains (lambda () (expr-str-contains (col "t") mars))))])
    (match-define (cons who thunk) call)
    (check-regexp-match
     (regexp (string-append "^" (regexp-quote (symbol->string who))
                            ": no literal of '\\(datetime microseconds \"Mars/Base\"\\)"))
     (cadr (raised thunk))))
  (check-raises 'contract #rx"^expr-fill-null: contract violation\n  expected: [(]integer-in"
                (lambda () (expr-fill-null (col "v") (expt 2 64))))

  (define (parse-failure target column value)
    (string-append
     "^select: conversion from `str` to `" target "` failed in column '" column "' for 1 out of 2 "
     "values: \\[\"" value "\"\\]\n\nYou might want to try:\n"
     "- passing #:strict #f to set values that cannot be converted to null\n"
     "- passing str->date or str->datetime a #:format string$"))
  (define unparsed (dataframe (list (series '("2021-03-27" "nope") #:name "s"))))
  (define ab-frame (dataframe (list (series '(1 2) #:name "a") (series '(3 4) #:name "b"))))
  (define hint-cases
    (list (cons (parse-failure "date" "s" "nope") (lambda () (select unparsed (str->date "s"))))
          (cons (parse-failure "datetime[[]μs[]]" "s" "nope")
                (lambda () (select unparsed (str->datetime "s"))))
          (cons (parse-failure "datetime[[]μs[]]" "s" "nope")
                (lambda () (select unparsed (str->datetime "s" #:format "%Y-%m-%d"))))
          (cons (parse-failure "date" "d" "soon")
                (lambda () (select (dataframe (list (series '("2021-03-27" "soon") #:name "d")))
                                   (str->date "d"))))
          (cons "^with-columns: the name 'x' is duplicate\n"
                (lambda () (with-columns frame (alias "v" "x") (alias "v" "x"))))
          (cons "^collect: the name 'x' is duplicate\n"
                (lambda () (collect (with-columns (lazy frame) (alias "v" "x") (alias "v" "x")))))
          (cons (string-append "^filter: The predicate expanded to multiple expressions: "
                               "(?s:.*)Combine them into one predicate with and or or[.]$")
                (lambda () (filter ab-frame (> (col #rx"^[ab]$") 1))))))
  (define hint-messages
    (for/list ([row (in-list hint-cases)])
      (match-define (list 'polars message) (raised (cdr row)))
      (check-regexp-match (regexp (car row)) message)
      message))
  (for ([message (in-list (append hint-messages lazy-enum-messages))])
    (check-false (regexp-match? (string-append "pl[.]|LazyFrame[.]|strict=|=True|=False"
                                               "|cast_options|_horizontal|`str[.]")
                                message)
                 message))

  (define select-unknown (select (lazy (dataframe (list (series '(1) #:name "o")))) "nope"))
  (for ([explained (list (lambda () (explain select-unknown))
                         (lambda () (explain select-unknown #:optimized #f))
                         (lambda () (explain select-unknown #:format 'tree)))])
    (check-equal? (cadr (raised explained))
                  "explain: not found: unable to find column \"nope\"; valid columns: [\"o\"]"))

  (check-equal? (series->list (series (list (expt 2 63)))) (list (expt 2 63)))
  (check-equal? (dtype (series (list (expt 2 63)))) 'uint64)
  (check-equal? (dtype (series (list 1 polars-null (expt 2 63)))) 'uint64)
  (check-equal? (dtype (series (list -1 (sub1 (expt 2 63))))) 'int64)
  (for ([elements (list (list -1 (expt 2 63))
                        (list (expt 2 64))
                        (vector (- (expt 2 63)) (expt 2 63))
                        (list (- -1 (expt 2 63))))])
    (check-raises 'contract #rx"^series: contract violation\n" (lambda () (series elements))))
  (for* ([width (in-list '(8 16 32 64))]
         [signed? (in-list '(#t #f))]
         [given (in-list (if signed?
                             (list (expt 2 (sub1 width)) (- -1 (expt 2 (sub1 width))))
                             (list (expt 2 width) -1)))]
         [spelling (in-list (list (format "~aint~a" (if signed? "" "u") width)
                                  (format "~a~a" (if signed? "i" "u") width)))])
    (define expected (format "~aint~a/c" (if signed? "" "u") width))
    (check-raises 'contract (regexp (format "^series: contract violation\n  expected: ~a\n" expected))
                  (lambda () (series (list 0 given) #:dtype (string->symbol spelling)))))
  (check-raises 'contract #rx"^gather: contract violation\n"
                (lambda () (gather (col "v") (list (expt 2 64)))))
  (check-raises 'contract #rx"^gather: contract violation\n" (lambda () (gather (col "v") "x")))
  (check-raises 'contract #rx"^expr-gather: " (lambda () (expr-gather (col "v") "x")))

  (for ([call (list (cons 'abs (lambda () (p-abs 1 2)))
                    (cons 'floor (lambda () (p-floor 1 2)))
                    (cons 'sqrt (lambda () (p-sqrt 1 2)))
                    (cons 'exp (lambda () (p-exp 1 2)))
                    (cons 'log (lambda () (p-log 1 2 3)))
                    (cons 'not (lambda () (p-not 1 2)))
                    (cons 'xor (lambda () (p-xor 1))))])
    (match-define (cons who thunk) call)
    (check-raises 'contract (regexp (format "^~a: arity mismatch;" who)) thunk))
  (check-equal? (map object-name (list p+ p- p* p/)) '(+ - * /))
  (for ([call (list (cons 'log (lambda () (p-log "v" #:base "e")))
                    (cons 'dt-strftime (lambda () (dt-strftime "t" 5)))
                    (cons 'dt-timestamp (lambda () (dt-timestamp "t" #:unit 'bogus)))
                    (cons 'str->date (lambda () (str->date "s" #:format 5)))
                    (cons 'str->date (lambda () (str->date "s" #:strict 'x)))
                    (cons 'str->time (lambda () (str->time "s" #:format 5)))
                    (cons 'str->time (lambda () (str->time "s" #:strict 'x))))])
    (match-define (cons who thunk) call)
    (check-raises 'contract
                  (regexp (format "^~a: contract violation\n" (regexp-quote (symbol->string who))))
                  thunk))
  (check-equal? (p-log 8 #:base 2) 3.0)

  (define (phase-0-variables mod)
    (check-true (module-declared? mod #t))
    (define-values (variables syntaxes) (module->exports mod))
    (for*/list ([phase+names (in-list variables)]
                #:when (eqv? (car phase+names) 0)
                [name (in-list (cdr phase+names))])
      (car name)))
  (define fluent-names (phase-0-variables 'polars/private/generic))
  (define (alias-of name)
    (match (regexp-match #rx"^polars:(.+)$" (symbol->string name))
      [(list _ public) (string->symbol public)]
      [#f #f]))
  (define misnamed
    (for*/list ([name (in-list (phase-0-variables 'polars))]
                #:when (memq name fluent-names)
                [value (in-value (dynamic-require 'polars name))]
                #:when (procedure? value)
                #:unless (eq? (object-name value) name)
                #:unless (and (alias-of name)
                              (eq? value (dynamic-require 'polars (alias-of name)))))
      (list name (object-name value))))
  (check-equal? misnamed '())
  (check-equal? (object-name (dynamic-require 'polars 'log)) 'log))
