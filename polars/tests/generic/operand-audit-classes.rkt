#lang racket/base

(require racket/contract/base
         (only-in racket/list filter-map)
         (only-in racket/string string-append*)
         (only-in racket/match == match match* match-define match-lambda)
         (only-in polars/private/foreign polars-null? series-dtype series-name)
         (only-in polars/tests/generic/operand-audit-table
                  eager-outcome fixture-outcome python-alternatives python-outcome row-operand
                  row-series)
         (only-in polars/private/generic/operands operand-action))

(provide (contract-out
          [operand-deviation-classes (listof (list/c symbol? string?))]
          [classify-deviation (-> pair? pair? (or/c symbol? #f))]
          [recorder-verdict
           (-> (listof (list/c pair? (or/c symbol? #f) pair?)) (hash/c pair? (list/c symbol? pair?))
               boolean?
               (or/c (list/c 'unclassified (listof (list/c pair? #f pair?)))
                     (list/c 'unaccepted (listof unaccepted-row/c))
                     (list/c 'record (listof (list/c pair? symbol? pair?)))))]
          [unaccepted-report (-> (listof unaccepted-row/c) (hash/c pair? pair?) string?)]))

(define unaccepted-row/c
  (or/c (list/c pair? symbol? pair? (or/c #f pair?)) (list/c pair? #f #f (list/c symbol? pair?))))

(define (label-kind label)
  (match label
    [(or 'date 'time 'duration 'datetime 'zoned) 'temporal]
    [(or 'int64 'int32 'uint8 'uint64 'float32 'float64 'decimal 'boolean) 'number]
    [(or 'string 'number-text) 'string]
    [_ label]))

(define (value-kind v)
  (match v
    [(list (or 'date 'time 'datetime 'moment 'duration-us) _ ...) 'temporal]
    ['null 'null]
    [(or (? real?) (? boolean?)) 'number]
    [(or (? string?) (? symbol?)) 'string]
    [_ 'other]))

(define (kinds row)
  (match row
    [(list _ label 'series other _ ...) (list (label-kind label) (label-kind other))]
    [(list _ label 'unary _ _ ...) (list (label-kind label) 'none)]
    [(list _ label _ v _ ...) (list (label-kind label) (value-kind v))]))

(define (kinds-are? row a b)
  (match (kinds row)
    [(or (list (== a) (== b)) (list (== b) (== a))) #t]
    [_ #f]))

(define (result-kind outcome)
  (match outcome
    [(list 'series _ (or 'date 'time (list (or 'datetime 'duration) _ ...)) _) 'temporal]
    [(list 'series _ 'string _) 'string]
    [(list 'series _ (or 'null 'categorical (list 'enum _ ...)) _) 'other]
    [(list 'series _ _ _) 'number]
    [(list 'value (? string?)) 'text]
    [(list 'raises _) 'raised]
    [_ 'other]))

(define (raised? outcome)
  (eq? (result-kind outcome) 'raised))

(define (series-outcome? outcome)
  (match outcome
    [(list 'series _ _ _) #t]
    [_ #f]))

(define (alternative? row names got)
  (for/or ([a (in-list (python-alternatives row))])
    (match-define (list name outcome) a)
    (and (memq name names) (equal? outcome got))))

(define (rule-expression? row)
  (match row
    [(list (and op (not (or 'and 'or 'xor 'not))) _ (and side (or 'left 'right)) _ _ ...)
     (and (memq (operand-action op (series-dtype (row-series row)) (row-operand row) side)
                '(expression integer-expression checked-expression checked-quotient))
          #t)]
    [_ #f]))

(define (racket-logical row)
  (match row
    [(list (and op (or 'and 'or)) label 'left operand _ ...)
     (match* (op (row-operand row))
       [(_ (? polars-null?)) #f]
       [('and #f) '(value #f)]
       [('and _) (fixture-outcome label)]
       [('or #f) (fixture-outcome label)]
       [('or _) (list 'value operand)])]
    [_ #f]))

(define (past-int64? row)
  (match row
    [(list _ label (or 'left 'right) (? exact-integer? v) _ ...)
     (not (or (<= (- (expt 2 63)) v (sub1 (expt 2 63)))
              (and (eq? label 'uint64) (<= 0 v (sub1 (expt 2 64))))))]
    [_ #f]))

(define (null-by-null? row)
  (match row
    [(list _ 'null _ 'null _ ...) #t]
    [_ #f]))

(define (op-of row)
  (match-define (list op _ ...) row)
  op)

(define (renamed? row python got)
  (match* (python got)
    [((list 'series "literal" dtype cells)
      (list 'series (== (series-name (row-series row))) dtype cells))
     #t]
    [(_ _) #f]))

(define classes
  (list
   (list 'racket-short-circuit
         "and / or with a plain value on the left evaluate as Racket's and / or"
         (lambda (row python got) (equal? got (racket-logical row))))
   (list 'result-name
         (string-append
          "the result takes the series' name on either side; Python's eager operator instead names "
          "it \"literal\" for a plain value left of +, -, * or / on a Decimal series, left of * on "
          "a Duration series, and for a string left of +")
         renamed?)
   (list 'expression-form
         (string-append
          "the rule table sends the operand to the expression form, (op (col name) (lit v)), and "
          "ours gives that form's outcome where Python's eager operator gives another: a plain "
          "operand beside a Null, Enum or Decimal series, an integer past the dtype's range, a "
          "string on the left of + and polars-null")
         (lambda (row python got) (and (rule-expression? row) (alternative? row '(expression) got))))
   (list 'integer-division
         "/ of integer operands (integer, Boolean or Null) is floor division, and ours gives Python's // (#65)"
         (lambda (row python got)
           (and (eq? (op-of row) '/) (not (null-by-null? row))
                (alternative? row '(floor floor-expression) got))))
   (list 'eager-raises
         (string-append
          "Python's eager operator raises where its expression form gives a series, and ours gives "
          "that series: and, or and xor of a Boolean series with polars-null, + and the ordering "
          "comparisons of a Boolean series with a boolean, and a duration over a duration series")
         (lambda (row python got)
           (and (raised? python) (series-outcome? got) (alternative? row '(expression) got))))
   (list 'error-kind
         (string-append
          "both raise, but ours raises a polars error where Python raises a TypeError, ValueError, "
          "OverflowError or AttributeError, or the reverse")
         (lambda (row python got) (and (raised? python) (raised? got) (not (equal? python got)))))
   (list 'python-string-format
         "Python's str % x is printf-style formatting, so the series' __rmod__ never runs; ours raises"
         (lambda (row python got)
           (match row
             [(list 'mod _ 'left (or (? string?) (? symbol?)) _ ...)
              (and (eq? (result-kind python) 'text) (raised? got))]
             [_ #f])))
   (list 'bitwise
         "Python's & | ^ ~ are bitwise on an integer series; ours refuse one"
         (lambda (row python got)
           (match row
             [(list (or 'and 'or 'xor 'not) (or 'int64 'int32 'uint8 'uint64) _ ...)
              (and (series-outcome? python) (raised? got))]
             [_ #f])))
   (list 'past-int64
         (string-append
          "an integer past Int64 is a contract error beside a series other than UInt64 or "
          "Decimal, as Python's eager operator raises OverflowError beside most dtypes, but "
          "Python's gives a series for / of an integer, Boolean or Null series and for * and / of a "
          "Duration series")
         (lambda (row python got)
           (and (past-int64? row) (series-outcome? python) (equal? got '(raises contract)))))
   (list 'null-temporal-series
         (string-append
          "a temporal series and a Null series in arithmetic: Python 1.42.1 gives a null temporal "
          "or duration series, where polars 0.55's kernel, which ours call, raises")
         (lambda (row python got)
           (match row
             [(list (or '+ '- '* '/ 'mod) _ 'series _ _ ...)
              (and (kinds-are? row 'temporal 'null) (eq? (result-kind python) 'temporal)
                   (equal? got '(raises polars)))]
             [_ #f])))
   (list 'string-temporal-concat
         (string-append
          "Python's + of a string and a temporal value or series concatenates the temporal's "
          "text; ours raise")
         (lambda (row python got)
           (and (eq? (op-of row) '+) (kinds-are? row 'string 'temporal)
                (eq? (result-kind python) 'string) (raised? got))))
   (list 'temporal-physical
         (string-append
          "Python's eager operator reads a temporal operand beside a number or a Boolean by its "
          "physical integer and gives a number or a Boolean; ours raise")
         (lambda (row python got)
           (and (kinds-are? row 'temporal 'number) (eq? (result-kind python) 'number)
                (raised? got))))))

(define operand-deviation-classes
  (for/list ([c (in-list classes)])
    (match-define (list name reason _) c)
    (list name reason)))

(define (classify-deviation row got)
  (define python (python-outcome (eager-outcome row)))
  (for/or ([c (in-list classes)])
    (match-define (list name _ holds?) c)
    (and (holds? row python got) name)))

(define (recorder-verdict deviating recorded accept?)
  (define unclassified (filter (match-lambda [(list _ class _) (not class)]) deviating))
  (define (unrecorded d)
    (match d
      [(list _ #f _) #f]
      [(list key class got)
       (define was (hash-ref recorded key #f))
       (and (not (equal? was (list class got))) (append d (list was)))]))
  (define now-deviating
    (for/hash ([d (in-list deviating)])
      (match-define (list key _ _) d)
      (values key #t)))
  (define vanished
    (for/list ([(key was) (in-hash recorded)]
               #:unless (hash-ref now-deviating key #f))
      (list key #f #f was)))
  (define moved (append (filter-map unrecorded deviating) vanished))
  (cond
    [(pair? unclassified) (list 'unclassified unclassified)]
    [(and (pair? moved) (not accept?)) (list 'unaccepted moved)]
    [else (list 'record deviating)]))

(define (unaccepted-report rows python-by-key)
  (define (report r)
    (match r
      [(list key #f #f was)
       (match (hash-ref python-by-key key #f)
         [#f (format "no longer an audit row: ~s\n  was: ~s\n" key was)]
         [python
          (format "no longer deviates: ~s\n  now: Python's ~s\n  was: ~s\n" key python was)])]
      [(list key class got was)
       (format "not recorded: ~s\n  now: ~s ~s\n  was: ~s\n" key class got was)]))
  (string-append*
   (append (map report rows)
           (list (format "~a rows differ from the record; rerun with --accept to update the record\n"
                         (length rows))))))
