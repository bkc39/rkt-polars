#lang racket/base

(module+ test
  (require rackunit
           racket/match
           (only-in racket/contract/base contract-name)
           (only-in polars/private/expr-core lit-integer/c)
           (only-in gregor date)
           (only-in gregor/period hours microseconds)
           (only-in gregor/time time)
           (only-in polars/private/bulk series->list)
           (only-in polars/private/expr dataframe-select-exprs expr-alias lit)
           (only-in polars/private/foreign
                    dataframe-column series-add series-add/who series-cast series-name
                    series-not series-rename series-slice)
           polars/private/generic/core
           polars/private/generic/operand-audit-classes
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
  (define past-i64 (expt 2 63))
  (define u64-max (sub1 (expt 2 64)))
  (define past-u64 (expt 2 64))
  (define u64 (series (list u64-max (add1 (expt 2 60))) #:dtype 'u64 #:name "n"))
  (define decimals (wrap-series (series-slice prices 0 2)))
  (series-rename decimals "n")
  (define grades (series (list "low" "mid" polars-null "high") #:name "n"
                         #:dtype '(enum low mid high)))

  (define i64 (series '(1 2) #:name "n"))
  (for ([row (list (list u8 300 'uint16)
                   (list u8 (expt 2 40) 'uint64)
                   (list i8 300 'int16)
                   (list i32 (expt 2 40) 'int64)
                   (list decimals 1 '(decimal 38 2))
                   (list decimals 1/3 'float64)
                   (list decimals 2.5 'float64)
                   (list u8 past-i64 'uint64)
                   (list u8 u64-max 'uint64)
                   (list i32 u64-max 'float64)
                   (list i64 past-i64 'float64))])
    (match-define (list s v expected) row)
    (for ([op (list p+ p- >)])
      (check-expression-form s op s v (op (col "n") v))
      (check-expression-form s op v s (op v (col "n"))))
    (check-equal? (dtype (p+ s v)) expected (format "~a + ~v" (dtype s) v)))
  (check-equal? (series->list (p+ u64 0)) (series->list u64))
  (for ([row (list (list (= (col "n") (lit u64-max)) (list 'boolean (list #t #f)))
                   (list (>= (col "n") past-i64) (list 'boolean (list #t #f)))
                   (list (lit u64-max) (list 'uint64 (list u64-max))))])
    (match-define (list e expected) row)
    (check-equal? (series-shape (selected e u64)) expected (format "~a" e)))

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
          (list (lambda () (p+ nulls past-u64)) 'contract
                (string-append "^[+]: " (refusal past-u64 'null)))
          (list (lambda () (> past-u64 nulls)) 'contract
                (string-append "^>: " (refusal past-u64 'null)))
          (list (lambda () (p+ (series '(1 2)) (date 2024 1 1))) 'polars "^[+]: [^\n]*date")
          (list (lambda () (p- #\a (series '(1 2)))) 'contract
                (string-append "^-: " (refusal #\a 'int64)))
          (list (lambda () (> (series '(1 2)) past-u64)) 'contract
                (string-append "^>: " (refusal past-u64 'int64)))
          (list (lambda () (> i32 past-u64)) 'contract
                (string-append "^>: " (refusal past-u64 'int32)))
          (list (lambda () (p+ u8 past-u64)) 'contract
                (string-append "^[+]: " (refusal past-u64 'uint8)))
          (list (lambda () (p+ u64 past-u64)) 'contract
                (string-append "^[+]: " (refusal past-u64 'uint64)))
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
  (define words (series '("x" "True")))
  (for ([row
         (list
          (list (lambda () (p/ (series (list (hours 1) (hours 2))) 2.5))
                (list '(duration microseconds)
                      (list (microseconds 1440000000) (microseconds 2880000000))))
          (list (lambda () (p/ (hours 1) decimals))
                (list '(duration microseconds)
                      (list (microseconds 2880000000) (microseconds 4500000000))))
          (list (lambda () (p/ #t decimals)) (list 'float64 (list 0.8 1.25)))
          (list (lambda () (< decimals #t)) (list 'boolean (list #f #t)))
          (list (lambda () (= decimals #f)) (list 'boolean (list #f #f)))
          (list (lambda () (= words #t)) (list 'boolean (list #f #t)))
          (list (lambda () (> words #f)) (list 'boolean (list #t #t)))
          (list (lambda () (< #t words)) (list 'boolean (list #t #f)))
          (list (lambda () (p/ u8 -1)) (list 'int16 (list -1 -2)))
          (list (lambda () (mod f32 (datetime 2024 1 1))) (list 'float32 (list 1.5 2.0)))
          (list (lambda () (mod (datetime 2024 1 1) f32)) (list 'float32 (list 0.0 0.0)))
          (list (lambda () (mod (datetime 2024 1 1 0 0 0 123457001) (series '(1.5 2.0))))
                (list 'float64 (list 1.0 1.0))))])
    (match-define (list thunk expected) row)
    (check-equal? (outcome thunk) expected))
  (for ([thunk (list (lambda () (mod (series '(1.5 2.0)) (date 2024 1 1)))
                     (lambda () (mod (date 2024 1 1) f32))
                     (lambda () (p/ 2.5 (series (list (hours 1))))))])
    (check-raises 'contract #rx"^(mod|/): the value cannot be an element of a series" thunk))
  (check-equal? (series-shape (p/ (series '(1 2)) f32)) (list 'float64 (list (/ 1 1.5) 1.0)))
  (define cats (series '(x y) #:name "c"))
  (define flags (series '(#t #f) #:name "f"))
  (define singles (series '(1.5 2.0) #:dtype 'f32 #:name "s"))
  (for ([named (list (p- 10 (series '(1 2) #:name "n")) (p/ (hours 1) decimals)
                     (mod (datetime 2024 1 1) singles) (p+ "x" (series '("a" "b") #:name "n"))
                     (p+ (series '(1 2) #:name "n") 1) (< 1 (series '(1 2) #:name "n"))
                     (= cats "x") (!= "x" cats) (= cats cats) (p-xor #t flags) (p-xor flags #t)
                     (p-and flags polars-null) (p-or polars-null flags))]
        [expected (list "n" "n" "s" "n" "n" "n" "c" "c" "" "f" "f" "f" "f")])
    (check-equal? (series-name named) expected))
  (check-equal? (series-shape (p- 10 (series '(1 2) #:name "n"))) '(int64 (9 8)))
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

  (define expression-refused (list #\a past-u64 far-date (datetime 300000 1 1) (vector 1)))
  (for* ([(who f) (in-hash audit-operators)] [v (in-list expression-refused)])
    (define first-operand (run who (lambda () (f (col "n") v))))
    (define second-operand (run who (lambda () (f v (col "n")))))
    (check-equal? (if (memq who '(and or)) (list first-operand) (list first-operand second-operand))
                  (if (memq who '(and or)) '(contract) '(contract contract))
                  (format "~a ~v" who v)))
  (for ([thunk (list (lambda () (> (col "v") #\a)) (lambda () (> #\a (col "v"))))])
    (check-raises 'contract #rx"^>: contract violation\n  expected: [(]or/c boolean?" thunk))
  (for ([thunk (list (lambda () (p+ (col "v") past-u64)) (lambda () (p+ past-u64 (col "v"))))])
    (check-raises 'contract
                  (regexp (format "^[+]: contract violation\n  expected: ~a\n"
                                  (regexp-quote (format "~s" (contract-name lit-integer/c)))))
                  thunk))
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

  (check-equal? deviation-classes operand-deviation-classes)
  (for ([(key deviation) (in-hash deviations)])
    (match-define (list class got) deviation)
    (match (hash-ref rows-by-key key #f)
      [#f (fail (format "deviation ~s names no row" key))]
      [row
       (check-not-equal? got (python-outcome (eager-outcome row))
                         (format "~s: the recorded outcome is Python's" key))
       (check-equal? (classify-deviation row got) class (format "~s: recorded as ~a" key class))]))

  (for ([forged
         (list
          (list '(+ int64 right #t) '(series "n" int64 (1 2)) #f)
          (list '(+ boolean right #t) '(series "n" int64 (2 1)) #f)
          (list '(= date right (date 2024 1 1)) '(raises contract) #f)
          (list '(+ int64 right (time 1 0 0 0)) '(raises contract) #f)
          (list '(mod float64 right (date 2024 1 1)) '(series "n" float64 (1.5 2.0)) #f)
          (list '(and boolean right null) '(series "n" boolean (#f #f)) #f)
          (list '(and int64 right 1) '(series "n" int64 (0 0)) #f)
          (list '(and int64 left 1) '(value 1) #f)
          (list '(and boolean left null) '(series "n" boolean (#t #f)) #f)
          (list '(or boolean left null) '(value null) #f)
          (list '(/ duration right 2.5) '(raises contract) #f)
          (list '(/ uint8 right -1) '(raises contract) #f)
          (list '(/ null series null) '(raises polars) #f)
          (list '(/ null right null) '(raises polars) #f)
          (list '(+ uint64 right 9223372036854775808) '(raises contract) #f)
          (list '(mod int64 left "x") '(series "n" string ("x" "x")) #f)
          (list '(+ decimal right 9223372036854775808) '(raises polars) #f)
          (list '(= string right (date 2024 1 1)) '(raises contract) #f)
          (list '(+ int64 series date) '(series "n" int64 (0 0)) #f)
          (list '(+ int32 right 1099511627776) '(series "n" int32 (1 2)) #f)
          (list '(+ decimal left 1) '(series "" (decimal 38 2) (9/4 9/5)) #f)
          (list '(- int64 left 1) '(series "" int64 (0 -1)) #f)
          (list '(= categorical series categorical) '(series "n" boolean (#t #t)) #f)
          (list '(+ decimal left 1) '(series "n" (decimal 38 2) (9/4 9/5)) 'result-name)
          (list '(+ int32 right 1099511627776) '(series "n" int64 (1099511627777 1099511627778))
                'expression-form)
          (list '(+ boolean right #t) '(series "n" uint32 (2 1)) 'eager-raises)
          (list '(and boolean right null) '(series "n" boolean (null #f)) 'eager-raises)
          (list '(and int64 left 1) '(series "n" int64 (1 2)) 'racket-short-circuit)
          (list '(or int64 left 1) '(value 1) 'racket-short-circuit)
          (list '(and int64 right 1) '(raises contract) 'bitwise)
          (list '(+ decimal right 9223372036854775808) '(raises contract) 'past-int64)
          (list '(+ int64 series date) '(raises polars) 'temporal-physical)
          (list '(- date series null) '(raises polars) 'null-temporal-series)
          (list '(+ string right (date 2024 1 1)) '(raises polars) 'string-temporal-concat)
          (list '(mod int64 left "x") '(raises polars) 'python-string-format))])
    (match-define (list key got class) forged)
    (check-equal? (classify-deviation (hash-ref rows-by-key key) got) class
                  (format "~s gives ~s" key got)))
  (define recorded (hash '(+ int64 right 1) '(bitwise (raises polars))))
  (define kept '((+ int64 right 1) bitwise (raises polars)))
  (define fresh '((- int64 right 1) bitwise (raises polars)))
  (define changed '((+ int64 right 1) bitwise (raises contract)))
  (define moved '((+ int64 right 1) error-kind (raises polars)))
  (define stray '((- int64 right 1) #f (raises polars)))
  (for ([verdict
         (list
          (list (list kept) #f (list 'record (list kept)))
          (list '() #f (list 'unaccepted (list '((+ int64 right 1) #f #f (bitwise (raises polars))))))
          (list '() #t '(record ()))
          (list (list fresh) #f
                (list 'unaccepted
                      (list (append fresh '(#f)) '((+ int64 right 1) #f #f (bitwise (raises polars))))))
          (list (list kept fresh) #f (list 'unaccepted (list (append fresh '(#f)))))
          (list (list changed) #f
                (list 'unaccepted (list (append changed '((bitwise (raises polars)))))))
          (list (list moved) #f (list 'unaccepted (list (append moved '((bitwise (raises polars)))))))
          (list (list kept fresh) #t (list 'record (list kept fresh)))
          (list (list changed) #t (list 'record (list changed)))
          (list (list moved fresh) #t (list 'record (list moved fresh)))
          (list (list kept stray) #t (list 'unclassified (list stray)))
          (list (list fresh stray) #f (list 'unclassified (list stray))))])
    (match-define (list deviating accept? expected) verdict)
    (check-equal? (recorder-verdict deviating recorded accept?) expected
                  (format "~s ~a" deviating accept?)))
  (check-equal? (unaccepted-report
                 (list '((+ int64 right 1) #f #f (bitwise (raises polars)))
                       '((* int64 right 7) #f #f (bitwise (raises polars)))
                       (append fresh '(#f)))
                 (hash '(+ int64 right 1) '(raises contract)))
                (string-append
                 "no longer deviates: (+ int64 right 1)\n"
                 "  now: Python's (raises contract)\n"
                 "  was: (bitwise (raises polars))\n"
                 "no longer an audit row: (* int64 right 7)\n"
                 "  was: (bitwise (raises polars))\n"
                 "not recorded: (- int64 right 1)\n"
                 "  now: bitwise (raises polars)\n"
                 "  was: #f\n"
                 "3 rows differ from the record; rerun with --accept to update the record\n"))
  (check-equal? strays '()))
