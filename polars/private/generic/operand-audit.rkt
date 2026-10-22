#lang racket/base

(module+ test
  (require rackunit
           racket/match
           (only-in gregor date)
           (only-in gregor/period hours microseconds)
           (only-in gregor/time time)
           (only-in polars/private/bulk series->list)
           (only-in polars/private/expr dataframe-select-exprs expr-alias lit)
           (only-in polars/private/foreign
                    dataframe-column series-add series-add/who series-cast series-name
                    series-not series-rename series-slice)
           polars/private/generic/core
           polars/private/generic/operand-audit-table
           polars/private/generic/operators
           polars/private/generic/test-fixtures
           (only-in threading ~>))

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

  (define (cause message)
    (match-define (list _ text)
      (regexp-match #rx"^[^:]*: (?:failed to collect the query: )?(.*?)(?:\n\nResolved plan.*)?$"
                    message))
    text)

  (define (outcome thunk)
    (with-handlers ([exn:fail? (lambda (e) (list 'raised (cause (exn-message e))))])
      (series-shape (thunk))))

  (define nulls
    (wrap-series (series-cast (series (list polars-null polars-null) #:name "n") 'null)))

  (define (selected e [s nulls])
    (wrap-series (dataframe-column (dataframe-select-exprs (dataframe (list s))
                                                           (list (expr-alias e "n")))
                                   "n")))


  (define (check-expression-form s op a b e)
    (check-equal? (outcome (lambda () (op a b)))
                  (outcome (lambda () (selected e s)))
                  (format "~a ~a ~v ~v" (dtype s) (object-name op) a b)))

  (define and-op (hash-ref audit-operators 'and))
  (define or-op (hash-ref audit-operators 'or))

  (for ([result (list (p+ nulls 1) (p- 1 nulls) (p/ nulls 2) (p* 2.5 nulls) (p+ nulls 2.5)
                      (p+ nulls "a") (p+ nulls 'a) (= nulls 'a) (= nulls "a") (= nulls 1)
                      (> 1 nulls) (p+ nulls polars-null))]
        [expected '(int32 int32 int32 float64 float64 string string boolean boolean boolean
                    boolean null)])
    (check-equal? (list (dtype result) (series-name result) (series->list result))
                  (list expected "n" (list polars-null polars-null))))

  (for* ([op (list p+ p- p* p/ mod = != > < >= <=)]
         [value (list 1 2.5 "a" 'a #t (datetime 2024 1 1) (date 2024 1 1))])
    (check-expression-form nulls op nulls value (op (col "n") value))
    (check-expression-form nulls op value nulls (op value (col "n"))))

  (define typed-series
    (cons nulls (for/list ([value (list 1 1.5 "a" #t (date 2024 1 1))])
                  (series (list value polars-null) #:name "n"))))
  (for* ([s (in-list typed-series)]
         [op (list p+ p- p* p/ mod = != > < >= <=)]
         #:unless (or (and (eq? op p/) (eq? s nulls)) (and (eq? op mod) (eq? (dtype s) 'date))))
    (check-expression-form s op s polars-null (op (col "n") polars-null))
    (check-expression-form s op polars-null s (op polars-null (col "n"))))
  (check-equal? (series-shape (p/ polars-null nulls)) (list 'float64 (list polars-null polars-null)))
  (check-raises 'contract #rx"^mod: cannot take the modulo of a temporal dtype\n"
                (lambda () (mod polars-null (series (list (date 2024 1 1))))))
  (define booleans (series (list #t #f polars-null) #:name "n"))
  (for ([op (list and-op or-op p-xor)])
    (check-expression-form booleans op booleans polars-null (op (col "n") polars-null))
    (check-expression-form booleans op polars-null booleans (op polars-null (col "n"))))

  (for ([result (list (= (series '(1 2)) polars-null) (p+ (series '(1.5 2.5)) polars-null)
                      (p-and (series (list #t #f)) polars-null)
                      (p-or (series (list #t #f)) polars-null)
                      (p-and polars-null (series (list #t #f)))
                      (p-or polars-null (series (list #t #f)))
                      (p-xor polars-null (series (list #t #f))))]
        [expected (list (list 'boolean (list polars-null polars-null))
                        (list 'float64 (list polars-null polars-null))
                        (list 'boolean (list polars-null #f))
                        (list 'boolean (list #t polars-null))
                        (list 'boolean (list polars-null #f))
                        (list 'boolean (list #t polars-null))
                        (list 'boolean (list polars-null polars-null)))])
    (check-equal? (series-shape result) expected))

  (define gappy (series (list 1 polars-null 3) #:name "n"))
  (check-equal? (series-shape (selected (lit polars-null) gappy)) (list 'null (list polars-null)))
  (for ([e (list (~> (p-when (> (col "n") 1)) (then polars-null) (otherwise (col "n")))
                 (~> (p-when (> (col "n") 1)) (then (col "n")) (otherwise polars-null))
                 (~> (p-when (> (col "n") 1)) (then polars-null) (otherwise polars-null))
                 (p-and polars-null (> (col "n") 1))
                 (p-or polars-null (> (col "n") 1))
                 (p-xor polars-null (> (col "n") 1)))]
        [expected (list (list 'int64 (list 1 polars-null polars-null))
                        (list 'int64 (list polars-null polars-null 3))
                        (list 'null (list polars-null polars-null polars-null))
                        (list 'boolean (list #f polars-null polars-null))
                        (list 'boolean (list polars-null polars-null #t))
                        (list 'boolean (list polars-null polars-null polars-null)))])
    (check-equal? (series-shape (selected e gappy)) expected))
  (check-equal? (p-and polars-null #t) #t)
  (check-equal? (p-or polars-null #f) polars-null)
  (check-equal? (p-and #f polars-null) #f)

  (define u8 (series '(1 2) #:dtype 'u8 #:name "n"))
  (define i8 (series '(1 2) #:dtype 'i8 #:name "n"))
  (define i32 (series '(1 2) #:dtype 'i32 #:name "n"))
  (define u64 (series (list (sub1 (expt 2 64)) (add1 (expt 2 60))) #:dtype 'u64 #:name "n"))
  (define decimals (wrap-series (series-slice prices 0 2)))
  (series-rename decimals "n")
  (define grades (series (list "low" "mid" polars-null "high") #:name "n"
                         #:dtype '(enum low mid high)))

  (for ([s (list u8 u8 i8 i32 decimals decimals decimals)]
        [v (list 300 (expt 2 40) 300 (expt 2 40) 1 1/3 2.5)]
        [expected '(uint16 uint64 int16 int64 (decimal 38 2) float64 float64)])
    (for ([op (list p+ p- >)])
      (check-expression-form s op s v (op (col "n") v))
      (check-expression-form s op v s (op v (col "n"))))
    (check-equal? (dtype (p+ s v)) expected (format "~a + ~v" (dtype s) v)))
  (check-equal? (series->list (p+ u64 0)) (series->list u64))

  (for* ([s (list u8 u64)]
         [thunk (list (lambda () (p+ s -1)) (lambda () (> s -1)) (lambda () (p- -1 s)))])
    (check-raises 'contract
                  (regexp (string-append "^[-+>]: the value cannot be an element of a series of "
                                         "this dtype\n  value: -1\n  series dtype: '"
                                         (symbol->string (dtype s)) "$"))
                  thunk))

  (for ([op (list = != = !=)]
        [v (list "bogus" "bogus" 'mid 'mid)]
        [expected (list (list #f #f polars-null #f) (list #t #t polars-null #t)
                        (list #f #t polars-null #f) (list #t #f polars-null #t))])
    (check-equal? (series->list (op grades v)) expected)
    (check-equal? (series->list (op v grades)) expected))
  (check-equal? (series->list (< grades 'mid)) (list #t #f polars-null #f))
  (for ([thunk (list (lambda () (< grades "bogus")) (lambda () (>= "bogus" grades)))])
    (check-raises 'polars #rx"^(<|>=): conversion from `str` to `enum` failed for value \"bogus\"$"
                  thunk))
  (check-raises 'contract #rx"^<: the value cannot be an element of a series of this dtype"
                (lambda () (< grades 1)))

  (define far-date (date 300000 1 1))
  (for ([thunk (list (lambda () (> (series (list (date 2024 1 1))) far-date))
                     (lambda () (> far-date (series (list (date 2024 1 1)))))
                     (lambda () (> (series (list (datetime 2024 1 1))) (datetime 300000 1 1)))
                     (lambda () (> nulls far-date)))])
    (check-raises 'contract #rx"^>: value out of range for this dtype\n" thunk))

  (check-exn #rx"application: procedure does not accept keyword arguments"
             (lambda () (keyword-apply series-add '(#:who) '(p) (list ints ints))))
  (check-raises 'polars #rx"^series-add: cannot do arithmetic operation on series of different"
                (lambda () (series-add ints (series '(1 2)))))
  (check-raises 'polars #rx"^custom: cannot do arithmetic operation on series of different"
                (lambda () (series-add/who 'custom ints (series '(1 2)))))
  (check-raises 'polars #rx"^series-not: invalid series dtype: expected `Boolean`, got `i32`"
                (lambda () (series-not ints)))

  (define (refusal value dtype)
    (string-append "the value cannot be an element of a series of this dtype"
                   (regexp-quote (format "\n  value: ~v" value))
                   (regexp-quote (format "\n  series dtype: ~v" dtype)) "$"))
  (define (not-boolean who got [named? #f])
    (string-append "^" who ": invalid series dtype: expected `Boolean`, got `" got "`"
                   (if named? " for series with name `n`$" "")))
  (define (not-logical who given)
    (format "^~a: contract violation\n  expected: ~a\n  given: ~v$"
            who (regexp-quote "(or/c series? boolean? polars-null?)") given))
  (for ([refused
         (list
          (list (lambda () (p+ nulls (date 2024 1 1))) 'polars "^[+]: [^\n]*date$")
          (list (lambda () (p- nulls "a")) 'polars "^-: [^\n]*str`$")
          (list (lambda () (p- "a" nulls)) 'polars "^-: [^\n]*str`$")
          (list (lambda () (p+ nulls #\a)) 'contract (string-append "^[+]: " (refusal #\a 'null)))
          (list (lambda () (= nulls #\a)) 'contract (string-append "^=: " (refusal #\a 'null)))
          (list (lambda () (p+ nulls (expt 2 63))) 'contract
                (string-append "^[+]: " (refusal (expt 2 63) 'null)))
          (list (lambda () (> (expt 2 63) nulls)) 'contract
                (string-append "^>: " (refusal (expt 2 63) 'null)))
          (list (lambda () (p+ (series '(1 2)) (date 2024 1 1))) 'polars "^[+]: [^\n]*date")
          (list (lambda () (p- #\a (series '(1 2)))) 'contract
                (string-append "^-: " (refusal #\a 'int64)))
          (list (lambda () (> (series '(1 2)) (expt 2 63))) 'contract
                (string-append "^>: " (refusal (expt 2 63) 'int64)))
          (list (lambda () (> i32 (expt 2 63))) 'contract
                (string-append "^>: " (refusal (expt 2 63) 'int32)))
          (list (lambda () (p+ u8 (expt 2 63))) 'contract
                (string-append "^[+]: " (refusal (expt 2 63) 'uint8)))
          (list (lambda () (> (series '(1 2)) "a")) 'contract
                (string-append "^>: " (refusal "a" 'int64)))
          (list (lambda () (p+ (series '(1 2)) (series '(1 2 3)))) 'polars
                "^[+]: cannot do arithmetic operation on series of different lengths")
          (list (lambda () (p-and nulls (series '(#t #f)))) 'polars
                (not-boolean "and" "null" #t))
          (list (lambda () (p-and nulls #t)) 'polars
                (not-boolean "and" "null" #t))
          (list (lambda () (p-or nulls #f)) 'polars
                (not-boolean "or" "null" #t))
          (list (lambda () (p-xor nulls #t)) 'polars
                (not-boolean "xor" "null" #t))
          (list (lambda () (p-xor nulls polars-null)) 'polars
                (not-boolean "xor" "null"))
          (list (lambda () (p-xor (series '(1 2)) polars-null)) 'polars
                (not-boolean "xor" "i64"))
          (list (lambda () (p-xor (series '(1 2)) #t)) 'polars
                (not-boolean "xor" "i64"))
          (list (lambda () (p-not (series '(1 2)))) 'polars
                (not-boolean "not" "i64"))
          (list (lambda () (p-not nulls)) 'polars
                (not-boolean "not" "null"))
          (list (lambda () (p-xor (series '(#t #f)) 1)) 'contract (not-logical "xor" 1))
          (list (lambda () (p-and (series '(#t #f)) 5)) 'contract (not-logical "and" 5))
          (list (lambda () (p-or (series '(#t #f)) 5)) 'contract (not-logical "or" 5)))])
    (match-define (list thunk kind rx) refused)
    (check-raises kind (regexp rx) thunk))

  (for ([operand (list (date 2024 1 1) (hours 1) (datetime 2024 1 1) (time 1))]
        [rx (list #rx"^-: [^\n]*date and null$" #rx"^-: [^\n]*duration[[]μs[]] and null$"
                  #rx"^-: [^\n]*datetime[[]μs[]] and null$" #rx"^-: [^\n]*time and null$")])
    (check-raises 'polars rx (lambda () (p- (series (list operand)) polars-null))))

  (check-equal? (series-shape (p+ (series '(1 2)) "x")) '(string ("1x" "2x")))
  (check-equal? (series-shape (p+ (series '(1 2)) #t)) '(int64 (2 3)))
  (check-equal? (series-shape (= (series '("x" "y")) 1)) '(boolean (#f #f)))
  (check-equal? (series-shape (p* (series (list (hours 1))) 2)) (list '(duration microseconds) (list (microseconds 7200000000))))
  (check-raises 'contract (regexp (string-append "^=: " (refusal (date 2024 1 1) 'int64)))
                (lambda () (= (series '(1 2)) (date 2024 1 1))))
  (check-raises 'contract (regexp (string-append "^=: " (refusal (time 1) 'uint64)))
                (lambda () (= (series '(1 2) #:dtype 'u64) (time 1))))
  (check-raises 'contract #rx"^mod: cannot take the modulo of a temporal dtype\n"
                (lambda () (mod (series (list (date 2024 1 1))) (series '(1)))))
  (define two-dates (series (list (date 2024 1 1) (date 2024 1 2))))
  (check-equal? (series-shape (mod (series '(1 2)) two-dates)) '(int64 (1 2)))
  (check-equal? (series-shape (mod (date 2024 1 1) (series '(1 2)))) '(int64 (0 1)))
  (for ([thunk (list (lambda () (mod two-dates (series '(1 2)))) (lambda () (mod two-dates 2))
                     (lambda () (mod 2 two-dates)) (lambda () (mod two-dates polars-null)))])
    (check-raises 'contract #rx"^mod: cannot take the modulo of a temporal dtype\n" thunk))
  (define f32 (series '(1.5 2.0) #:dtype 'f32))
  (for ([result (list (p/ 1 f32) (p/ 1/3 f32) (p/ u8 f32) (p/ (series '(1 2)) decimals)
                      (p/ (series '(1.5 2.0)) 2.5) (p/ (series '(#t #f)) 1) (p/ nulls nulls)
                      (p/ nulls polars-null) (p/ (series (list (hours 1))) (hours 1)))]
        [expected (list (list 'float64 (list (/ 1 1.5) 0.5))
                        (list 'float64 (list (/ (/ 1.0 3) 1.5) (/ (/ 1.0 3) 2.0)))
                        (list 'float64 (list (/ 1 1.5) 1.0))
                        (list 'float64 (list 0.8 2.5))
                        (list 'float64 (list 0.6000000000000001 0.8))
                        (list 'float64 (list 1.0 0.0))
                        (list 'float64 (list polars-null polars-null))
                        (list 'float64 (list polars-null polars-null))
                        (list 'float64 (list 1.0)))])
    (check-equal? (series-shape result) expected))
  (check-equal? (series->list (= (series '("1e-05" "x")) 1e-5)) '(#t #f))
  (check-equal? (series-shape (p/ (series '(1 2)) f32)) (list 'float64 (list (/ 1 1.5) 1.0)))
  (define number-texts (series '("1e-05" "inf" "-inf" "nan" "-0.0" "1e+16" "0.0001")))
  (for ([v (list 1e-5 +inf.0 -inf.0 +nan.0 -0.0 1e16 0.0001)]
        [i (in-naturals)])
    (check-equal? (series->list (= number-texts v))
                  (for/list ([j (in-range 7)]) (= i j))
                  (format "~v" v)))
  (check-equal? (series->list (p+ (series '(1 2)) 2.5)) '(3.5 4.5))
  (check-equal? (series->list (> (series '(1 2)) 1.5)) '(#f #t))
  (check-equal? (dtype (p+ (series '(1 2) #:dtype 'i32) 2)) 'int32)
  (check-equal? (series->list (p-and (series '(#t #f)) #t)) '(#t #f))
  (check-equal? (series->list (p-xor (series '(#t #f)) #t)) '(#f #t))
  (check-equal? (series->list (p-xor #t (series '(#t #f)))) '(#f #t))

  (define leaked #rx"operation failed|Resolved plan|/raw|->C|ptr")
  (define strays '())
  (define (run who thunk)
    (define prefix (regexp (string-append "^" (regexp-quote (symbol->string who)) ": ")))
    (with-handlers ([exn:fail?
                     (lambda (e)
                       (define message (exn-message e))
                       (unless (and (regexp-match? prefix message)
                                    (not (regexp-match? leaked message)))
                         (set! strays (cons (list who message) strays)))
                       (if (exn:fail:contract? e) 'contract 'polars))])
      (define result (thunk))
      (if (series? result) result (list 'value result))))

  (define expression-refused (list #\a (expt 2 63) far-date (datetime 300000 1 1) (vector 1)))
  (for* ([(who f) (in-hash audit-operators)] [v (in-list expression-refused)])
    (define first-operand (run who (lambda () (f (col "n") v))))
    (define second-operand (run who (lambda () (f v (col "n")))))
    (check-equal? (if (memq who '(and or)) (list first-operand) (list first-operand second-operand))
                  (if (memq who '(and or)) '(contract) '(contract contract))
                  (format "~a ~v" who v)))
  (for ([thunk (list (lambda () (> (col "v") #\a)) (lambda () (> #\a (col "v"))))])
    (check-raises 'contract #rx"^>: contract violation\n  expected: [(]or/c boolean?" thunk))
  (for ([thunk (list (lambda () (p+ (col "v") (expt 2 63))) (lambda () (p+ (expt 2 63) (col "v"))))])
    (check-raises 'contract
                  #rx"^[+]: contract violation\n  expected: [(]integer-in -9223372036854775808" thunk))
  (for ([thunk (list (lambda () (> (col "d") far-date)) (lambda () (> far-date (col "d"))))])
    (check-raises 'contract #rx"^>: value out of range for this dtype\n" thunk))
  (check-raises 'contract #rx"^and: contract violation\n" (lambda () (p-and (col "v") #\a)))
  (check-raises 'contract #rx"^xor: contract violation\n" (lambda () (p-xor #\a (col "v"))))

  (for* ([(who f) (in-hash audit-operators)]
         [(label s) (in-hash audit-fixtures)]
         [v (list #\a far-date)])
    (check-equal? (run who (lambda () (f s v))) 'contract (format "~a ~a ~v" who label v))
    (unless (memq who '(and or))
      (check-equal? (run who (lambda () (f v s))) 'contract (format "~a ~v ~a" who v label))))

  (check-equal? python-polars-version "1.42.1")
  (for ([entry (in-list audit-series-outcomes)])
    (match-define (list label want) entry)
    (check-equal? (fixture-outcome label) (python-outcome want) (format "fixture ~a" label)))

  (define rows-by-key (for/hash ([row (in-list audit-rows)]) (values (audit-row-key row) row)))
  (check-equal? (hash-count rows-by-key) (length audit-rows))
  (for ([row (in-list audit-rows)])
    (define-values (got stray) (run-row row))
    (check-equal? got (expected-outcome row) (format "~s" (audit-row-key row)))
    (when stray (set! strays (cons (list (audit-row-key row) stray) strays))))

  (define declared (map car deviation-classes))
  (for ([(key deviation) (in-hash deviations)])
    (match-define (list class got) deviation)
    (define row (hash-ref rows-by-key key #f))
    (check-not-false row (format "deviation ~s names no row" key))
    (check-not-false (memq class declared) (format "~s: undeclared class ~a" key class))
    (check-not-equal? got (and row (python-outcome (eager-outcome row)))
                      (format "~s: the recorded outcome is Python's" key)))
  (check-equal? strays '()))
