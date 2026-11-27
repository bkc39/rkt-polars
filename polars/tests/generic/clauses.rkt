#lang racket/base

(module+ test
  (require rackunit
           (for-syntax racket/base)
           (only-in gregor date datetime moment)
           (only-in gregor/period days hours)
           (only-in gregor/time time)
           (only-in racket/contract
                    blame-positive blame-source exn:fail:contract:blame-object
                    exn:fail:contract:blame?)
           (only-in racket/match match-define)
           (only-in racket/runtime-path define-runtime-path)
           (only-in racket/sequence sequence->list)
           (only-in racket/stream stream)
           (only-in syntax/location quote-module-name)
           syntax/parse/define
           (only-in polars/private/bulk series->list)
           (only-in polars/private/foreign
                    dataframe-column dataframe-column-names dataframe-new polars-null series-cast
                    series-drop-count series-name series-new-i32 series-new-str)
           (only-in polars/private/generic/clauses dataframe)
           (only-in (submod polars/private/generic/clauses internal)
                    column-option-keywords columns->dataframe)
           (only-in polars/private/generic/core column-names dataframe? dtype len ref series shape)
           (only-in polars/private/generic/convert dataframe->rows in-dataframe-columns)
           (only-in polars/private/generic/parquet read-parquet)
           (only-in polars/private/generic/reshape cast pivot rename rename!)
           (only-in polars/tests/generic/test-fixtures named-frame nul-frame)
           (only-in polars/tests/test-helpers settle!))

  (define (frame-columns d) (sequence->list (in-dataframe-columns d)))
  (define (frame-datum d)
    (list (column-names d) (map dtype (frame-columns d)) (dataframe->rows d)))
  (define (series-frame . columns) (columns->dataframe columns))

  (define-namespace-anchor anchor)
  (define (fresh-namespace)
    (parameterize ([current-namespace (namespace-anchor->empty-namespace anchor)])
      (namespace-require 'racket/base)
      (namespace-require 'polars)
      (current-namespace)))
  (define clause-namespace (fresh-namespace))
  (define (run form [namespace clause-namespace])
    (parameterize ([current-namespace namespace])
      (eval form)))
  (define (source text)
    (read-syntax 'clauses (open-input-string text)))
  (define (run-text text [namespace clause-namespace])
    (parameterize ([error-print-source-location #f])
      (run (source text) namespace)))

  (define frame
    (dataframe [user '("alice" "bob" "carol")]
               [score '(10 25 18) #:dtype 'i32]
               [cost '(1.2 3.5 2.0)]))
  (define collided
    (pivot (dataframe [id '(0 0)]
                      [k '("a" "a\u0000b")]
                      [v '(1 2)])
           #:on '("k") #:index '("id") #:values '("v")))

  (test-case "the reference's bridge from polars/ffi: dataframe takes raw series"
    (define raw (series-new-i32 "n" '(1 2)))
    (check-equal? (series->list (ref (dataframe raw) "n")) '(1 2))
    (check-exn #rx"^len: contract violation:\n  expected: sized[?]" (lambda () (len raw)))
    (define raw-frame (dataframe-new (list raw (series-new-str "s" '("a" "b")))))
    (define rebuilt
      (dataframe (for/list ([name (in-list (dataframe-column-names raw-frame))])
                   (dataframe-column raw-frame name))))
    (check-pred dataframe? rebuilt)
    (check-equal? (shape rebuilt) '(2 2))
    (check-equal? (series->list (ref rebuilt "s")) '("a" "b")))

  (test-case "a clause builds the column series builds"
    (define built-dtypes
      (list (list '(1 2 3) '(#f i32 u8 f64))
            (list '(1.5 2.5) '(#f f64))
            (list '("a" "b") '(#f (enum a b)))
            (list (list 1 polars-null 3) '(#f i32 u8 f64))
            (list (list (date 2024 1 1) (date 2024 6 1)) '(#f (datetime microseconds "UTC")))
            (list (list (time 1 2 3)) '(#f))
            (list (list (datetime 2024 1 1 12)) '(#f (datetime microseconds "UTC")))
            (list (list (moment 2024 1 1 #:tz "Europe/Brussels"))
                  '(#f (datetime microseconds "UTC")))
            (list (list (hours 1) (days 2)) '(#f))
            (list '(a b a) '(#f (enum a b)))
            (list '() '(#f i32 u8 f64 (enum a b) (datetime microseconds "UTC") null))
            (list (vector 1 2 3) '(#f i32 u8 f64))
            (list (list polars-null) '(#f i32 u8 f64 (enum a b) (datetime microseconds "UTC") null))))
    (define clause-dtypes
      (list #f 'i32 'u8 'f64 '(enum a b) '(datetime microseconds "UTC") 'null))
    (define (outcome thunk)
      (with-handlers ([exn:fail? (lambda (_) 'failed)])
        (frame-datum (thunk))))
    (for ([row (in-list built-dtypes)])
      (match-define (list v expected-built) row)
      (define built
        (for/list ([d (in-list clause-dtypes)]
                   #:unless (eq? (outcome (lambda () (series-frame (series v #:name "k" #:dtype d))))
                                 'failed))
          d))
      (check-equal? built expected-built (format "~s" v))
      (for ([d (in-list clause-dtypes)])
        (define expected (outcome (lambda () (series-frame (series v #:name "k" #:dtype d)))))
        (define label (format "~s #:dtype ~s" v d))
        (check-equal? (outcome (lambda () (dataframe [v #:name "k" #:dtype d]))) expected label)
        (check-equal? (outcome (lambda () (dataframe ["k" v #:dtype d]))) expected label)
        (check-equal? (outcome (lambda () (dataframe [k v #:dtype d]))) expected label))))

  (test-case "a sequence of values is read into a list"
    (for* ([vals (in-list (list (in-range 3) (in-vector (vector 0 1 2)) (stream 0 1 2)
                                (in-list '(0 1 2))))]
           [d (in-list '(#f f64))])
      (check-equal? (frame-datum (dataframe [k vals #:dtype d]))
                    (frame-datum (dataframe [k '(0 1 2) #:dtype d])))))

  (test-case "a clause's name"
    (define name-values '(1))
    (check-equal? (column-names (dataframe [x name-values]
                                           [|dep time| name-values]
                                           ["a\u0000b" name-values]
                                           [name-values #:name 'date]
                                           [name-values #:name #"b"]
                                           [name-values #:name (string->path "p")]))
                  '("x" "dep time" "a\u0000b" "date" "b" "p")))

  (define-runtime-path produce-path "../../scribblings/data/produce.parquet")

  (test-case "a series value is renamed, and cast with #:dtype"
    (define held (series '(1 2) #:name "held" #:dtype 'i32))
    (define renamed-frame (dataframe [x held]))
    (check-equal? (frame-datum renamed-frame) '(("x") (int32) (#(1) #(2))))
    (check-equal? (series-name held) "held")
    (rename! held "z")
    (check-equal? (column-names renamed-frame) '("x"))
    (check-equal? (frame-datum (dataframe [x held #:dtype 'f64]))
                  (frame-datum (series-frame (rename (cast held 'f64) "x"))))
    (check-equal? (frame-datum (dataframe [x (series-new-i32 "raw" '(1 2))]))
                  '(("x") (int32) (#(1) #(2))))
    (define binary (series-cast (series '("a") #:name "b") 'binary))
    (check-equal? (map dtype (frame-columns (dataframe [x binary]))) '(binary))
    (define price (ref (read-parquet produce-path) "price"))
    (check-equal? (map dtype (frame-columns (dataframe [x price]))) '((decimal 10 2))))

  (define s1 (series '(1 2) #:name "s1"))
  (define s2 (series '(3 4) #:name "s2"))
  (define s3 (series '(5 6) #:name "s3"))
  (parameterize ([current-namespace clause-namespace])
    (for ([(name v) (in-hash (hash 's1 s1 's2 s2 's3 s3 'cols (list s1 s2)))])
      (namespace-set-variable-value! name v)))

  (test-case "an expression clause is a series or a list of series, spliced in"
    (define pair-datum (frame-datum (series-frame s1 s2)))
    (check-equal? (frame-datum (run '(dataframe (list s1 s2)))) pair-datum)
    (check-equal? (frame-datum (run '(dataframe s1 s2))) pair-datum)
    (check-equal? (frame-datum (run '(dataframe cols))) pair-datum)
    (check-equal? (shape (run '(dataframe '()))) '(0 0))
    (check-equal? (shape (run '(dataframe))) '(0 0))
    (check-equal? (column-names (run-text "(dataframe s1 [b '(3 4)] (list s3) (list))"))
                  '("s1" "b" "s3")))

  (test-case "a frame's series rebuild it"
    (for ([d (in-list (list frame (named-frame "x") (nul-frame "a\u0000b") collided))])
      (check-equal? (frame-datum (apply dataframe (frame-columns d))) (frame-datum d))
      (check-equal? (frame-datum (dataframe (frame-columns d))) (frame-datum d))))

  (test-case "dataframe as a value is the procedure over series"
    (check-equal? (object-name dataframe) 'dataframe)
    (check-equal? (map frame-datum (map dataframe (list (list s1) (list s2))))
                  (list (frame-datum (series-frame s1)) (frame-datum (series-frame s2))))
    (check-exn exn:fail:syntax? (lambda () (run '(set! dataframe 1)))))

  (define-syntax-parser blame-row
    [(_ form:expr expected:expr (~optional (~seq #:line? line?:expr) #:defaults ([line? #'#t])))
     #:with line (datum->syntax this-syntax (syntax-line #'form))
     (syntax/loc this-syntax (list (and line? line) (lambda () form) expected))])

  (define (values-refusal given)
    (regexp (string-append
             "^dataframe: contract violation\n  expected: a list, vector, series or sequence, "
             "not a string, byte string, hash or number\n  given: " (regexp-quote given) "\n")))
  (define (element-refusal expected)
    (regexp (string-append "^dataframe: contract violation\n  expected: " (regexp-quote expected)
                           "\n  given: 1\n")))
  (define part-refusal
    #rx"^dataframe: contract violation\n  expected: \\(or/c Series-ptr\\? \\(listof Series-ptr\\?\\)\\)\n  given: 5\n")

  (test-case "a clause's arguments are checked by contract, blaming the clause"
    (define blame-rows
      (list
       (blame-row (dataframe 5) part-refusal)
       (blame-row (dataframe [a "abc"]) (values-refusal "\"abc\""))
       (blame-row (dataframe [a #"x"]) (values-refusal "#\"x\""))
       (blame-row (dataframe [a (hash)]) (values-refusal "'#hash()"))
       (blame-row (dataframe [a 3]) (values-refusal "3"))
       (blame-row (dataframe [a (in-indexed '(a))])
                  #rx"^dataframe: contract violation\n  expected: a sequence of single values\n")
       (blame-row (dataframe ['(1) #:name 5])
                  #rx"^dataframe: contract violation\n  expected: \\(or/c symbol\\? \\(or/c string\\? ")
       (blame-row (dataframe [x '(1) #:dtype 'bogus])
                  #rx"^dataframe: contract violation\n  expected: \\(or/c #f \\(and/c datetime-zone/c")
       (blame-row (dataframe [x '(300) #:dtype 'u8])
                  #rx"^dataframe: contract violation\n  expected: uint8/c\n  given: 300\n")
       (blame-row (dataframe [a (list 1) #:dtype 'string]) (element-refusal "(or/c string? polars-null?)"))
       (blame-row (dataframe [a '(1) #:dtype 'categorical])
                  (element-refusal "(or/c string? symbol? polars-null?)"))
       (blame-row (dataframe [a (vector 1) #:dtype '(enum a)])
                  (element-refusal "(or/c string? symbol? polars-null?)"))
       (blame-row (apply dataframe '(5))
                  #rx"^dataframe: contract violation\n  expected: \\(or/c Series-ptr\\? \\(listof Series-ptr\\?\\)\\)\n  given: 5\n  in: an element of\n      the rest argument of"
                  #:line? #f)))
    (for ([row (in-list blame-rows)])
      (match-define (list line thunk expected) row)
      (define e (with-handlers ([exn:fail:contract:blame? values]) (thunk) #f))
      (check-pred exn:fail:contract:blame? e (object-name expected))
      (when e
        (check-regexp-match expected (exn-message e))
        (define blame (exn:fail:contract:blame-object e))
        (check-equal? (blame-positive blame) (quote-module-name))
        (when line
          (check-equal? (srcloc-line (blame-source blame)) line (exn-message e))))))

  (test-case "a category clause takes what series takes"
    (check-equal? (frame-datum (dataframe [a (list "x" 'y polars-null) #:dtype 'categorical]
                                          [b (vector 'x "y" polars-null) #:dtype '(enum x y)]
                                          [c (list "x" polars-null "z") #:dtype 'string]))
                  (list '("a" "b" "c") '(categorical (enum x y) string)
                        (list (vector 'x 'x "x") (vector 'y 'y polars-null)
                              (vector polars-null polars-null "z"))))
    (check-exn #rx"^dataframe: contract violation\n  expected: \\(or/c string\\? polars-null\\?\\)\n  given: 'y\n"
               (lambda () (dataframe [c (list "x" 'y) #:dtype 'str]))))

  (define evaluated (box '()))
  (define (noted tag v)
    (set-box! evaluated (cons tag (unbox evaluated)))
    v)

  (test-case "every clause is evaluated, in order, before any series is built"
    (set-box! evaluated '())
    (settle!)
    (define drops-before (series-drop-count))
    (check-exn exn:fail:contract:blame?
               (lambda ()
                 (dataframe [a (noted 1 '(1))]
                            [b (noted 2 '(2))]
                            [c (noted 3 "abc")]
                            [d (noted 4 '(4))])))
    (check-equal? (series-drop-count) drops-before)
    (check-equal? (reverse (unbox evaluated)) '(1 2 3))
    (set-box! evaluated '())
    (dataframe [(noted 'v1 '(1 2)) #:name (noted 'n1 "a") #:dtype (noted 'd1 'i64)]
               [b (noted 'v2 '(3 4)) #:dtype (noted 'd2 #f)]
               (noted 'p3 (list s3)))
    (check-equal? (reverse (unbox evaluated)) '(v1 n1 d1 v2 d2 p3)))

  (define dup-a (series '(1) #:name "a"))

  (test-case "a frame's own failures name dataframe"
    (define duplicate
      #rx"^dataframe: could not create a new DataFrame: column with name 'a' has more than one occurrence$")
    (check-exn duplicate (lambda () (dataframe dup-a dup-a)))
    (check-exn duplicate (lambda () (let ([n "a"]) (dataframe ['(1) #:name n] ['(2) #:name n]))))
    (check-exn #rx"^dataframe: could not create a new DataFrame: height of column 'b' \\(1\\) does not match height of column 'a' \\(2\\)$"
               (lambda () (dataframe [a '(1 2)] [b '(3)])))
    (check-exn #rx"^dataframe: unsupported dtype 'binary$"
               (lambda () (dataframe [x '(1) #:dtype 'binary])))
    (check-exn #rx"^dataframe: cannot infer a dtype from elements; pass #:dtype explicitly$"
               (lambda () (dataframe [x '(1 "x")])))
    (check-exn #rx"^dataframe: 1 of 2 "
               (lambda () (dataframe [x (series '("a" "zz")) #:dtype '(enum a b)]))))

  (define (in-module text)
    (format "(module m racket/base (require polars) ~a)" text))

  (define (syntax-failure text [namespace clause-namespace])
    (with-handlers ([exn:fail:syntax? values])
      (run-text text namespace)
      #f))

  (define (check-syntax-error text expected highlighted [namespace clause-namespace])
    (define e (syntax-failure text namespace))
    (check-pred exn:fail:syntax? e text)
    (when e
      (check-regexp-match expected (exn-message e) text)
      (check-equal? (syntax->datum (car (exn:fail:syntax-exprs e))) highlighted text)))

  (define (message-rx text)
    (regexp (string-append "^dataframe: " (regexp-quote text))))
  (define (bound-here name)
    (message-rx (format (string-append "~a is bound here, so this bracketed clause is not a "
                                       "column; name a column with #:name, as in [vals "
                                       "#:name '~a], or with a string, as in [~s vals], or "
                                       "drop the brackets for an expression")
                        name name (symbol->string name))))
  (define not-a-column
    (message-rx (string-append "a bracketed clause is a column, [vals #:name name option ...] "
                               "or [name vals option ...], where name is a string or an "
                               "identifier with no binding")))
  (define (named-twice name)
    (message-rx (format "~a has no binding here, so it names the column, and #:name cannot name it again"
                        name)))
  (define unknown-option
    (message-rx "#:foo is not a column option; the options are #:name and #:dtype"))
  (define string-head
    (message-rx "a clause headed by a string is a column, [\"a\" vals option ...]"))

  (test-case "a clause that is not a column is a syntax error under dataframe"
    (define syntax-errors
      `(["(dataframe [date '(1)])" ,(bound-here 'date) date]
        ["(let ([xs '()]) (dataframe [xs '(1)]))" ,(bound-here 'xs) xs]
        ["(define (f) (dataframe [zz '(1)]) (define zz 5) zz)" ,(bound-here 'zz) zz]
        ["(dataframe [])" ,not-a-column ()]
        ["(dataframe [(list 1) #:dtype 'i32])" ,not-a-column ((list 1) #:dtype 'i32)]
        ["(dataframe [k '(1) '(2)])" ,not-a-column (k '(1) '(2))]
        ["(dataframe (\"a\"))" ,string-head ("a")]
        ["(dataframe [\"a\" '(1) '(2)])" ,string-head ("a" '(1) '(2))]
        ["(dataframe [k '(1) #:name \"n\"])" ,(named-twice 'k) #:name]
        ["(dataframe (serie '(1) #:name \"n\"))" ,(named-twice 'serie) #:name]
        ["(dataframe [\"k\" '(1) #:name \"n\"])"
         ,(message-rx "\"k\" names the column, so #:name cannot name it again") #:name]
        ["(dataframe [k '(1) #:foo 1])" ,unknown-option #:foo]
        ["(dataframe ['(1) #:name \"a\" #:foo 1])" ,unknown-option #:foo]
        ["(dataframe [k '(1) #:dtype 'i32 #:dtype 'i64])"
         ,(message-rx "#:dtype appears twice in one column") #:dtype]
        ["(dataframe ['(1) #:name \"a\" #:name \"b\"])"
         ,(message-rx "#:name appears twice in one column") #:name]
        ["(dataframe #:x 1)" ,(message-rx "expected a column clause") #:x]
        ["(dataframe . 1)" #rx"^dataframe: bad syntax" (dataframe . 1)]))
    (for* ([row (in-list syntax-errors)]
           [wrap (in-list (list values in-module))])
      (match-define (list text expected highlighted) row)
      (check-syntax-error (wrap text) expected highlighted)))

  (test-case "two clauses of one literal name are a syntax error in a module"
    (define duplicate-name (message-rx "duplicate column name \"a\""))
    (for ([row (in-list '(["(dataframe [a '(1)] [\"a\" '(2)])" "a"]
                          ["(dataframe [a '(1)] ['(2) #:name 'a])" 'a]))])
      (match-define (list text highlighted) row)
      (check-syntax-error (in-module text) duplicate-name highlighted)
      (check-exn #rx"^dataframe: could not create a new DataFrame: column with name 'a' has more"
                 (lambda () (run-text text)))))

  (test-case "a column clause means the same in brackets and in parentheses"
    (for ([clause (in-list '("'(1 2) #:name \"a\"" "\"a\" '(1 2)" "kk '(1 2) #:dtype 'f64"))])
      (check-equal? (frame-datum (run-text (format "(dataframe [~a])" clause)))
                    (frame-datum (run-text (format "(dataframe (~a))" clause))))))

  (define (printed thunk)
    (define values-printed '())
    (parameterize ([current-print (lambda (v) (set! values-printed (cons v values-printed)))])
      (thunk))
    (reverse values-printed))

  (test-case "a module-level or body clause is expanded once every binding is known"
    (define helper
      "(module helper racket/base (require polars) (provide mk) (define (mk xs) (series xs #:name \"from-mk\")))")
    (define before-require
      (format "(module before-require racket/base (require polars) ~a (dataframe (mk '(1 2))) (require (submod \".\" helper)))"
              helper))
    (define module-namespace (fresh-namespace))
    (run-text before-require module-namespace)
    (check-equal? (map column-names (printed (lambda () (run '(require 'before-require) module-namespace))))
                  '(("from-mk")))
    (check-syntax-error "(module before-define racket/base (require polars) (dataframe [zz '(1)]) (define zz 5))"
                        (bound-here 'zz) 'zz module-namespace)
    (check-syntax-error "(module before-local racket/base (require polars) (define (f) (dataframe [zz '(1)]) (define zz 5) zz))"
                        (bound-here 'zz) 'zz module-namespace)
    (define top (fresh-namespace))
    (run-text helper top)
    (check-equal? (column-names (run-text "(dataframe (mk '(1 2)))" top)) '("mk"))
    (run '(require 'helper) top)
    (check-equal? (column-names (run-text "(dataframe (mk '(1 2)))" top)) '("from-mk"))
    (check-equal? (column-names (run-text "(dataframe [zz '(1)])" top)) '("zz"))
    (run '(define zz 5) top)
    (check-syntax-error "(dataframe [zz '(1)])" (bound-here 'zz) 'zz top)
    (check-syntax-error "(define (f) (dataframe [yy '(1)]) (define yy 5) yy)" (bound-here 'yy) 'yy top))

  (test-case "at the top level a head with no binding is looked up each time it runs"
    (define top (fresh-namespace))
    (define (top-run text) (run-text text top))
    (top-run "(define (mk xs) (series xs #:name \"m\"))")
    (check-equal? (column-names (top-run "(dataframe (mk '(1 2)))")) '("m"))
    (check-exn #rx"^dataframe: mk is bound here" (lambda () (top-run "(dataframe [mk '(1)])")))
    (top-run "(define (b1) (dataframe (later '(1 2))))")
    (top-run "(define (later xs) (series xs #:name \"l\"))")
    (check-equal? (column-names (top-run "(b1)")) '("l"))
    (top-run "(define (b2) (dataframe (never '(1))))")
    (check-equal? (column-names (top-run "(b2)")) '("never"))
    (top-run "(define (never xs) (series xs #:name \"n\"))")
    (check-equal? (column-names (top-run "(b2)")) '("n"))
    (top-run "(define (b3) (dataframe [later2 '(1)]))")
    (top-run "(define later2 1)")
    (define ((syntax-error? rx) e)
      (and (exn:fail:syntax? e) (regexp-match? rx (exn-message e))))
    (check-exn (syntax-error? #rx"^dataframe: later2 is bound here") (lambda () (top-run "(b3)")))
    (check-exn (syntax-error? #rx"^dataframe: k2 has no binding here")
               (lambda () (top-run "(dataframe (k2 '(1) #:name \"n\"))")))
    (top-run "(define zz 1)")
    (top-run (string-append "(module forward racket/base (require polars) (provide forward named)"
                            " (define (forward) (dataframe (later '(1))))"
                            " (define (later xs) (series xs #:name \"l\"))"
                            " (define named (dataframe [zz '(1)])))"))
    (top-run "(require 'forward)")
    (check-equal? (column-names (top-run "(forward)")) '("l"))
    (check-equal? (column-names (top-run "named")) '("zz")))

  (define (drops thunk)
    (settle!)
    (define before (series-drop-count))
    (with-handlers ([exn:fail? void])
      (thunk))
    (- (series-drop-count) before))

  (test-case "a clause's series is released once the frame is built"
    (check-equal? (drops (lambda () (dataframe [a '(1 2)] [b '(3 4)]))) 2)
    (check-equal? (drops (lambda () (dataframe [a '(1)] [b (list 1 "x")]))) 1)
    (check-equal? (drops (lambda () (dataframe [a '(1)] [b '(2 3)]))) 2)
    (check-equal? (drops (lambda () (dataframe s1 s2))) 0)
    (check-equal? (series->list s1) '(1 2))
    (check-equal? (drops (lambda () (dataframe [x s1]))) 1)
    (check-equal? (drops (lambda () (dataframe [x s1 #:dtype 'f64]))) 1))

  (test-case "a clause takes series' keywords but #:name"
    (define-values (_required series-keywords) (procedure-keywords series))
    (check-equal? (remove '#:name series-keywords) column-option-keywords)
    (define samples (hash '#:dtype "'i64"))
    (for ([kw (in-list column-option-keywords)])
      (check-equal? (shape (run-text (format "(dataframe ['(1) #:name \"a\" ~a ~a])"
                                             kw (hash-ref samples kw))))
                    '(1 1))))

  (test-case "the reference's dataframe examples"
    (check-equal? (frame-datum (dataframe [carrier '("UA" "AA" "UA")]
                                          [dep (in-range 3) #:dtype 'i32]))
                  '(("carrier" "dep") (string int32) (#("UA" 0) #("AA" 1) #("UA" 2))))
    (check-equal? (frame-datum (dataframe [(list (date 2026 1 1) (date 2026 6 1)) #:name 'date]
                                          ["height" '(1.56 1.77)]
                                          [|dep time| (vector 5 7)]))
                  (list '("date" "height" "dep time") '(date float64 int64)
                        (list (vector (date 2026 1 1) 1.56 5) (vector (date 2026 6 1) 1.77 7))))
    (define carriers (series '("UA" "AA") #:name "c"))
    (check-equal? (frame-datum (dataframe [carrier carriers #:dtype 'categorical] carriers))
                  '(("carrier" "c") (categorical string) (#(UA "UA") #(AA "AA"))))
    (parameterize ([current-namespace clause-namespace])
      (namespace-set-variable-value! 'carriers carriers))
    (check-equal? (frame-datum (run '(dataframe (list carriers) (series '(1 2) #:name "n"))))
                  '(("c" "n") (string int64) (#("UA" 1) #("AA" 2))))
    (check-equal? (frame-datum (apply dataframe (frame-columns (dataframe [a '(1 2)] [b '(3 4)]))))
                  '(("a" "b") (int64 int64) (#(1 3) #(2 4))))
    (check-syntax-error "(dataframe [date (list (date 2026 1 1))])" (bound-here 'date) 'date)
    (check-syntax-error "(dataframe [k '(1 2) #:name \"n\"])" (named-twice 'k) '#:name)
    (check-exn #rx"^dataframe: could not create a new DataFrame: height"
               (lambda () (run-text "(dataframe [a '(1 2)] [b '(3)])")))
    (check-exn (lambda (e) (and (exn:fail:contract:blame? e)
                                (regexp-match? #rx"^dataframe: contract violation" (exn-message e))))
               (lambda () (run-text "(dataframe [a \"abc\"])")))))
