#lang racket/base

(module+ test
  (require rackunit
           racket/match
           racket/runtime-path
           (only-in racket/file file->value)
           (only-in gregor date moment)
           (only-in gregor/period hours)
           (only-in gregor/time time)
           (only-in polars/private/bulk series->list)
           (only-in polars/private/expr dataframe-select-exprs expr-alias lit)
           (only-in polars/private/foreign
                    dataframe-column series-add series-add/who series-cast series-name
                    series-not series-rename series-slice)
           polars/private/generic/core
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

  (define (and-op a b) (p-and a b))
  (define (or-op a b) (p-or a b))

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
         [op (list p+ p- p* p/ mod = != > < >= <=)])
    (check-expression-form s op s polars-null (op (col "n") polars-null))
    (check-expression-form s op polars-null s (op polars-null (col "n"))))
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
          (list (lambda () (p+ (series '(1 2)) "a")) 'contract
                (string-append "^[+]: " (refusal "a" 'int64)))
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
          (list (lambda () (= (series '("x")) 1)) 'contract
                (string-append "^=: " (refusal 1 'string)))
          (list (lambda () (p+ (series '(1 2)) #t)) 'contract
                (string-append "^[+]: " (refusal #t 'int64)))
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

  (check-equal? (series->list (p+ (series '(1 2)) 2.5)) '(3.5 4.5))
  (check-equal? (series->list (> (series '(1 2)) 1.5)) '(#f #t))
  (check-equal? (dtype (p+ (series '(1 2) #:dtype 'i32) 2)) 'int32)
  (check-equal? (series->list (p-and (series '(#t #f)) #t)) '(#t #f))
  (check-equal? (series->list (p-xor (series '(#t #f)) #t)) '(#f #t))
  (check-equal? (series->list (p-xor #t (series '(#t #f)))) '(#f #t))

  (define audit-series
    `((int64 ,(series '(1 2)))
      (int32 ,(series '(1 2) #:dtype 'i32))
      (uint8 ,(series '(1 2) #:dtype 'u8))
      (uint64 ,(series '(1 2) #:dtype 'u64))
      (float32 ,(series '(1.5 2.0) #:dtype 'f32))
      (float64 ,(series '(1.5 2.0)))
      (decimal ,(wrap-series (series-slice prices 0 2)))
      (string ,(series '("x" "y")))
      (boolean ,(series '(#t #f)))
      (date ,(series (list (date 2024 1 1) (date 2024 1 2))))
      (time ,(series (list (time 1) (time 2))))
      (duration ,(series (list (hours 1) (hours 2))))
      (datetime ,(series (list (datetime 2024 1 1) (datetime 2024 1 2))))
      (zoned ,(wrap-series (series-cast (series (list (datetime 2024 1 1) (datetime 2024 1 2)))
                                        '(datetime microseconds "Europe/Paris"))))
      (categorical ,(series '(x y)))
      (enum ,(series '("x" "y") #:dtype '(enum x y)))
      (null ,nulls)))
  (define audit-plain
    (list 1 -1 300 (expt 2 40) (expt 2 63) 1/3 2.5 "x" 'x #t polars-null (date 2024 1 1)
          far-date (time 1) (hours 1) (datetime 2024 1 1) (moment 2024 1 1 #:tz "Europe/Paris")
          #\a))
  (define audit-ops
    (for/list ([name (in-list '(+ - * / mod = != < > <= >= and or xor))])
      (list name
            (match name
              ['+ p+] ['- p-] ['* p*] ['/ p/] ['mod mod] ['= =] ['!= !=] ['< <] ['> >]
              ['<= <=] ['>= >=] ['and and-op] ['or or-op] ['xor p-xor]))))

  (define leaked #rx"operation failed|Resolved plan|/raw|->C|ptr")
  (define strays '())
  (define (audit who thunk)
    (define prefix (regexp (string-append "^" (regexp-quote (symbol->string who)) ": ")))
    (match (raised thunk)
      [#f "."]
      [(list kind message)
       #:when (and (regexp-match? prefix message) (not (regexp-match? leaked message)))
       (match kind ['contract "c"] ['polars "p"])]
      [(list _ message)
       (set! strays (cons (list who message) strays))
       "?"]))
  (define (cells who f operands)
    (apply string-append (for/list ([v (in-list operands)]) (audit who (lambda () (f v))))))
  (define (row who f l)
    (list (cells who (lambda (r) (f l r)) (map (match-lambda [(list _ s) s]) audit-series))
          (cells who (lambda (v) (f l v)) audit-plain)
          (cells who (lambda (v) (f v l)) audit-plain)))
  (define expression-refused (list #\a (expt 2 63) far-date (datetime 300000 1 1) (vector 1)))
  (for* ([op (in-list audit-ops)] [v (in-list expression-refused)])
    (match-define (list who f) op)
    (define first-operand (audit who (lambda () (f (col "n") v))))
    (define second-operand (audit who (lambda () (f v (col "n")))))
    (check-equal? (if (memq who '(and or)) first-operand (string-append first-operand second-operand))
                  (if (memq who '(and or)) "c" "cc")
                  (format "~a ~v" who v)))
  (for ([thunk (list (lambda () (> (col "v") #\a)) (lambda () (> #\a (col "v"))))])
    (check-raises 'contract #rx"^>: contract violation\n  expected: [(]or/c boolean?" thunk))
  (for ([thunk (list (lambda () (p+ (col "v") (expt 2 63))) (lambda () (p+ (expt 2 63) (col "v"))))])
    (check-raises 'contract
                  #rx"^[+]: contract violation\n  expected: int64/c\n" thunk))
  (for ([thunk (list (lambda () (> (col "d") far-date)) (lambda () (> far-date (col "d"))))])
    (check-raises 'contract #rx"^>: value out of range for this dtype\n" thunk))
  (check-raises 'contract #rx"^and: contract violation\n" (lambda () (p-and (col "v") #\a)))
  (check-raises 'contract #rx"^xor: contract violation\n" (lambda () (p-xor #\a (col "v"))))

  (define audit-table
    (append
     (for*/list ([op (in-list audit-ops)] [l (in-list audit-series)])
       (match* (op l)
         [((list who f) (list label s)) (list* who label (row who f s))]))
     (for/list ([l (in-list audit-series)])
       (match-define (list label s) l)
       (list 'not label (audit 'not (lambda () (p-not s)))))))
  (define-runtime-path expected-path "operand-audit.rktd")
  (define expected (file->value expected-path))
  (define (case-key r)
    (match-define (list* who label _) r)
    (list who label))
  (check-equal? (map case-key audit-table) (map case-key expected))
  (for ([actual (in-list audit-table)] [want (in-list expected)])
    (check-equal? actual want (format "~a" (case-key actual))))
  (check-equal? strays '()))
