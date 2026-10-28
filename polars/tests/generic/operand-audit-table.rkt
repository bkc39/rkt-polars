#lang racket/base

(require racket/runtime-path
         (only-in racket/file file->value)
         (only-in racket/match match match-define match-lambda)
         (only-in gregor
                  ->day ->hours ->minutes ->month ->nanoseconds ->seconds ->timezone ->year date
                  date? datetime datetime? moment moment?)
         (only-in gregor/period microseconds nanoseconds period?)
         (only-in gregor/time time time?)
         (only-in polars/private/foreign series-cast series-name series-rename series-slice)
         (only-in polars/private/temporal period->nanoseconds)
         (only-in polars/private/generic/core dtype series series? wrap-series)
         (only-in polars/private/generic/operators
                  != < <= = > >= mod p* p+ p- p-and p-not p-or p-xor p/)
         (only-in polars/tests/generic/test-fixtures polars-null polars-null? prices
                  series-cells))

(provide audit-fixtures
         audit-operators
         audit-row-key
         audit-rows
         audit-series-outcomes
         deviation-classes
         deviations
         eager-outcome
         expected-outcome
         fixture-outcome
         python-alternatives
         python-outcome
         python-polars-version
         row-operand
         row-series
         run-row
         write-deviations)

(define-runtime-path table-path "operand-audit.rktd")
(define-runtime-path deviations-path "operand-deviations.rktd")

(match-define `((python-polars ,python-polars-version) (series ,audit-series-outcomes ...)
                (rows ,audit-rows ...))
  (file->value table-path))

(match-define `((classes ,deviation-classes ...) (deviations ,deviation-rows ...))
  (file->value deviations-path))

(define (audit-row-key row)
  (match-define (list op label side operand _ ...) row)
  (list op label side operand))

(define deviations
  (for/hash ([d (in-list deviation-rows)])
    (match-define (list op label side operand class got) d)
    (values (list op label side operand) (list class got))))

(define (write-deviations classes rows)
  (with-output-to-file deviations-path #:exists 'truncate
    (lambda ()
      (displayln "((classes")
      (for ([c (in-list classes)]) (printf "  ~s\n" c))
      (displayln " )")
      (displayln " (deviations")
      (for ([r (in-list rows)]) (printf "  ~s\n" r))
      (displayln " ))"))))

(define nulls (wrap-series (series-cast (series (list polars-null polars-null) #:name "n") 'null)))

(define number-text
  (match (assq 'number-text audit-series-outcomes)
    [(list _ (list 'series _ 'string cells)) (series cells #:name "n")]))

(define audit-fixtures
  (hash 'int64 (series '(1 2) #:name "n")
        'int32 (series '(1 2) #:dtype 'i32 #:name "n")
        'uint8 (series '(1 2) #:dtype 'u8 #:name "n")
        'uint64 (series '(1 2) #:dtype 'u64 #:name "n")
        'float32 (series '(1.5 2.0) #:dtype 'f32 #:name "n")
        'float64 (series '(1.5 2.0) #:name "n")
        'decimal (let ([s (wrap-series (series-slice prices 0 2))]) (series-rename s "n") s)
        'string (series '("x" "y") #:name "n")
        'boolean (series '(#t #f) #:name "n")
        'date (series (list (date 2024 1 1) (date 2024 1 2)) #:name "n")
        'time (series (list (time 1) (time 2)) #:name "n")
        'duration (series (list (microseconds 3600000000) (microseconds 7200000000)) #:name "n")
        'datetime (series (list (datetime 2024 1 1) (datetime 2024 1 2)) #:name "n")
        'zoned (wrap-series (series-cast (series (list (datetime 2024 1 1) (datetime 2024 1 2))
                                                 #:name "n")
                                         '(datetime microseconds "Europe/Paris")))
        'categorical (series '(x y) #:name "n")
        'enum (series '("x" "y") #:dtype '(enum x y) #:name "n")
        'null nulls
        'number-text number-text))

(define (and-op a b) (p-and a b))
(define (or-op a b) (p-or a b))
(define audit-operators
  (hash '+ p+ '- p- '* p* '/ p/ 'mod mod '= = '!= != '< < '> > '<= <= '>= >=
        'and and-op 'or or-op 'xor p-xor))

(define (decode v)
  (match v
    ['null polars-null]
    [(list 'date y m d) (date y m d)]
    [(list 'datetime y mo d h mi s ns) (datetime y mo d h mi s ns)]
    [(list 'moment y mo d h mi s ns zone) (moment y mo d h mi s ns #:tz zone)]
    [(list 'time h m s ns) (time h m s ns)]
    [(list 'duration-us n) (microseconds n)]
    [_ v]))

(define (encode v)
  (match v
    [(? polars-null?) 'null]
    [(? date?) (list 'date (->year v) (->month v) (->day v))]
    [(? moment?) (append (clock 'moment v) (list (->timezone v)))]
    [(? datetime?) (clock 'datetime v)]
    [(? time?) (list 'time (->hours v) (->minutes v) (->seconds v) (->nanoseconds v))]
    [(? period?)
     (define ns (period->nanoseconds v))
     (if (zero? (remainder ns 1000)) (list 'duration-us (quotient ns 1000)) (list 'duration-ns ns))]
    [_ v]))

(define (clock tag v)
  (list tag (->year v) (->month v) (->day v) (->hours v) (->minutes v) (->seconds v)
        (->nanoseconds v)))

(define (series-outcome s)
  (list 'series (series-name s) (dtype s) (map encode (series-cells s))))

(define leaked #rx"operation failed|Resolved plan|/raw|->C|ptr")

(define (run-row row)
  (match-define (list who label side operand _ ...) row)
  (define s (hash-ref audit-fixtures label))
  (define v (decode operand))
  (define thunk
    (match side
      ['unary (lambda () (p-not s))]
      ['series (lambda () ((hash-ref audit-operators who) s (hash-ref audit-fixtures operand)))]
      ['right (lambda () ((hash-ref audit-operators who) s v))]
      ['left (lambda () ((hash-ref audit-operators who) v s))]))
  (define prefix (regexp (string-append "^" (regexp-quote (symbol->string who)) ": ")))
  (with-handlers ([exn:fail?
                   (lambda (e)
                     (define message (exn-message e))
                     (values (list 'raises (if (exn:fail:contract? e) 'contract 'polars))
                             (and (not (and (regexp-match? prefix message)
                                            (not (regexp-match? leaked message))))
                                  message)))])
    (define result (thunk))
    (values (if (series? result) (series-outcome result) (list 'value (encode result))) #f)))

(define (row-series row)
  (match-define (list _ label _ ...) row)
  (hash-ref audit-fixtures label))

(define (row-operand row)
  (match-define (list _ _ _ operand _ ...) row)
  (decode operand))

(define (fixture-outcome label)
  (series-outcome (hash-ref audit-fixtures label)))

(define contract-classes '(TypeError ValueError OverflowError AttributeError))

(define python-outcome
  (match-lambda
    [(list 'raises class) (list 'raises (if (memq class contract-classes) 'contract 'polars))]
    [other other]))

(define (expected-outcome row)
  (match (hash-ref deviations (audit-row-key row) #f)
    [(list _ got) got]
    [#f (python-outcome (eager-outcome row))]))

(define (eager-outcome row)
  (match-define (list _ _ _ _ (list 'eager out) _ ...) row)
  out)

(define (python-alternatives row)
  (match-define (list _ _ _ _ _ alternatives ...) row)
  (for/list ([a (in-list alternatives)])
    (match-define (list name out) a)
    (list name (python-outcome out))))
