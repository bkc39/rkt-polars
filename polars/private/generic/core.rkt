#lang racket/base

(require racket/generic
         (only-in racket/contract/base -> contract-out listof)
         (only-in racket/list check-duplicates)
         (only-in racket/match match*)
         syntax/parse/define
         (for-syntax racket/base)
         (only-in ffi/unsafe prop:cpointer)
         (only-in polars/private/bulk in-series)
         (only-in polars/private/expr-core lazyframe-dropped)
         polars/private/foreign
         polars/private/generic/dtype
         polars/private/generic/printing)

(provide (except-out (all-defined-out) dataframe)
         (contract-out
          [dataframe (-> (listof Series-ptr?) dataframe?)]))

(define unset (gensym 'unset))

(define-generics has-ref
  (ref has-ref [key] #:columns [columns] #:rows [rows]))

(define-generics sized
  (len sized))

(define-generics has-shape
  (shape has-shape))

(define-generics has-dtype
  (dtype has-dtype))

(define-generics has-null-count
  (null-count has-null-count))

;; ---------------------------------------------------------------------------
;; the series wrapper

(struct series-rec (ptr)
  #:reflection-name 'series
  #:property prop:cpointer 0                ; marshals as a _Series-ptr
  #:property prop:owned-pointer 0
  #:property prop:custom-write (write-owned 'series series-dropped series->printed)
  #:property prop:sequence in-series
  #:methods gen:has-ref
  [(define (ref s [key unset] #:columns [columns unset] #:rows [rows unset])
     (series-ref* s key columns rows))]
  #:methods gen:sized
  [(define (len s) (series-len s))]
  #:methods gen:has-shape
  [(define (shape s) (list (series-len s)))]
  #:methods gen:has-dtype
  [(define (dtype s) (series-dtype s))]
  #:methods gen:has-null-count
  [(define (null-count s) (series-null-count s))])

(define series? series-rec?)
(define (wrap-series ptr) (series-rec ptr))
(define (null-series? v) (and (series? v) (eq? (series-dtype v) 'null)))

;; ---------------------------------------------------------------------------
;; the dataframe wrapper

(struct dataframe-rec (ptr)
  #:reflection-name 'dataframe
  #:property prop:cpointer 0
  #:property prop:owned-pointer 0
  #:property prop:custom-write
  (write-owned 'dataframe dataframe-dropped
               (lambda (d) (printed-or-placeholder 'dataframe (lambda () (dataframe->string/raw d)))))
  #:methods gen:has-ref
  [(define (ref d [key unset] #:columns [columns unset] #:rows [rows unset])
     (dataframe-ref* d key columns rows))]
  #:methods gen:sized
  [(define (len d) (dataframe-height d))]
  #:methods gen:has-shape
  [(define (shape d)
     (define-values (rows cols) (dataframe-shape d))
     (list rows cols))])

(define (dataframe? v) (dataframe-rec? v))
(define (wrap-dataframe ptr) (dataframe-rec ptr))

(define (frame-columns-problem columns)
  (define heights (map series-len columns))
  (define names (map series-name columns))
  (match* ((for/first ([h (in-list heights)] [n (in-list names)] #:unless (= h (car heights)))
             (list n h))
           (check-duplicates names))
    [((list name height) _)
     (format "could not create a new DataFrame: height of column '~a' (~a) does not match ~a"
             name height (format "height of column '~a' (~a)" (car names) (car heights)))]
    [(#f (? string? name))
     (format "could not create a new DataFrame: column with name '~a' has more than one occurrence"
             name)]
    [(#f #f) #f]))

(define (column-problem present names)
  (cond
    [(for/first ([name (in-list names)] #:unless (member name present)) name)
     => (lambda (name) (format "~s not found" name))]
    [(check-duplicates names) => (lambda (name) (format "~s named more than once" name))]
    [else #f]))

(define (refuse who problem fallback)
  (raise-arguments-error who (or problem fallback)))

(define (dataframe series-list)
  (wrap-dataframe
   (or (dataframe-new/raw series-list)
       (refuse 'dataframe (frame-columns-problem series-list) "could not create a new DataFrame"))))

;; ---------------------------------------------------------------------------
;; the lazyframe wrapper

(struct lazyframe-rec (ptr)
  #:reflection-name 'lazyframe
  #:property prop:cpointer 0
  #:property prop:owned-pointer 0
  #:property prop:custom-write
  (write-owned 'lazyframe lazyframe-dropped (lambda (lf) "#<lazyframe>")))

(define (lazyframe? v) (lazyframe-rec? v))
(define (wrap-lazyframe ptr) (lazyframe-rec ptr))

(define-syntax-parse-rule (define-wrapped name:id wrap:expr reader:expr)
  (define name (procedure-rename (compose1 wrap reader) 'name)))

;; ---------------------------------------------------------------------------
;; dataframe-only accessors (plain functions guarded on dataframe?).

(define (guard-dataframe who d)
  (unless (dataframe? d)
    (error who "expected a dataframe, got ~v" d)))

(define (width d)  (guard-dataframe 'width d)  (dataframe-width d))
(define (height d) (guard-dataframe 'height d) (dataframe-height d))
(define (column-name d i)
  (guard-dataframe 'column-name d)
  (dataframe-column-name d i))
(define (column-names d)
  (guard-dataframe 'column-names d)
  (dataframe-column-names d))

(define (shape/values x) (apply values (shape x)))

;; ---------------------------------------------------------------------------
;; series: keyword constructor with dtype inference (see dtype.rkt)

(define (series elements #:name [name ""] #:dtype [dtype #f])
  (define canonical (if dtype (normalize-dtype dtype) (infer-dtype elements)))
  (check-categorical-values 'series canonical elements)
  (define ctor (dtype->constructor canonical (vector? elements)))
  (wrap-series (ctor name (coerce-elements canonical elements))))

;; ---------------------------------------------------------------------------
;; ref dispatch helpers (referenced by the struct methods above)

(define (series-ref* s key columns rows)
  (unless (eq? columns unset)
    (error 'ref "a series has no columns to select"))
  (unless (eq? rows unset)
    (error 'ref "series row slicing not supported"))
  (when (eq? key unset)
    (error 'ref "ref on a series requires an index"))
  (series-value 'ref s key))

(define (column->name d c)
  (cond
    [(string? c) c]
    [(and (exact-nonnegative-integer? c) (< c (dataframe-width d))) (dataframe-column-name d c)]
    [(exact-nonnegative-integer? c)
     (raise-arguments-error 'ref "column index out of range" "index" c "width" (dataframe-width d))]
    [else (error 'ref "dataframe column selector must be a string or index, got ~v" c)]))

(define (dataframe-ref* d key columns rows)
  (unless (eq? rows unset)
    (error 'ref "dataframe row slicing not yet implemented"))
  (define sel
    (cond
      [(not (eq? columns unset)) columns]
      [(not (eq? key unset)) key]
      [else (error 'ref "ref on a dataframe requires a column key or #:columns")]))
  (cond
    [(list? sel)
     (define names (map (lambda (c) (column->name d c)) sel))
     (wrap-dataframe
      (or (dataframe-select/c d names)
          (refuse 'ref (column-problem (dataframe-column-names d) names)
                  "cannot select the columns")))]
    [else
     (define name (column->name d sel))
     (wrap-series (or (dataframe-column/raw d name) (error 'ref "~s not found" name)))]))

(module+ test
  ;; fixtures are inline here: core can't require test-fixtures (which requires
  ;; core) without a compile-time cycle.
  (require rackunit (only-in gregor datetime) (only-in racket/sequence sequence->list)
           (only-in threading ~>))
  (define ints (series '(1 2 3 4) #:name "ints" #:dtype 'i32))
  (define floats (series '(1.5 2.0 4.25 8.0) #:name "floats"))
  (define withnull (series (list 10 polars-null 30) #:dtype 'i32))
  (define frame
    (dataframe (list (series '("alice" "bob" "carol") #:name "user")
                     (series '(10 25 18) #:name "score" #:dtype 'i32)
                     (series '(1.2 3.5 2.0) #:name "cost"))))

  (check-equal? (format "~a" ints) (series->string ints))
  (define printed-binary
    (~> (series '("a" "z q" "") #:name "blob") (series-cast 'binary) wrap-series))
  (for ([form (in-list '("~a" "~s"))])
    (check-equal? (format form printed-binary)
                  "shape: (3,)\nSeries: 'blob' [binary]\n[\n\tb\"a\"\n\tb\"z\\x20q\"\n\tb\"\"\n]"))
  (define past-chrono-zoned
    (wrap-series (series-cast (series-new-i64 "k" '(9000000000000000000))
                              '(datetime microseconds "Europe/Brussels"))))
  (check-regexp-match #rx"\n\t#<cannot print: polars panicked: [^>]+>\n]$"
                      (format "~a" past-chrono-zoned))
  (check-exn #rx"^ref: cannot read a datetime in \"Europe/Brussels\": polars panicked: "
             (lambda () (ref past-chrono-zoned 0)))

  (check-pred series? (series '(1 2 3)))
  (check-false (series? 5))
  (check-false (series? '(1 2 3)))

  (check-equal? (series-dtype (series '(1 2 3) #:dtype 'i32)) 'int32)
  (check-equal? (series-dtype (series '(1 2 3) #:dtype 'int32)) 'int32)
  (check-equal? (series-dtype (series '(1 2 3))) 'int64)   ; Polars default
  (check-equal? (series-dtype (series '(1.0 2.0))) 'float64)
  (check-equal? (series-dtype (series '("a" "b"))) 'string)
  (check-equal? (series-dtype (series '(#t #f))) 'boolean)
  (check-equal? (series-dtype (series (list (datetime 2024 1 1)))) '(datetime microseconds #f))
  (check-equal? (series-dtype (series (vector 1 2 3) #:dtype 'f64)) 'float64)
  (check-exn #rx"series: unsupported dtype '\\(datetime weeks\\)"
             (lambda () (series '(1) #:dtype '(datetime weeks))))
  (check-exn #rx"series: expected a gregor datetime or moment for this dtype"
             (lambda () (series '(1) #:dtype '(datetime microseconds "UTC"))))
  (check-exn #rx"series: unsupported dtype '\\(datetime microseconds \"\"\\)"
             (lambda () (series '(1) #:dtype '(datetime microseconds ""))))
  (check-exn #rx"series: unsupported dtype '\\(datetime #f \"UTC\"\\)"
             (lambda () (series '(1) #:dtype '(datetime #f "UTC"))))
  (check-equal? (series-name (series '(1 2 3) #:name "xs")) "xs")
  (check-equal? (series-dtype (series (list (expt 2 40)))) 'int64)

  ;; symbols infer a categorical and read back as symbols; strings need #:dtype
  (define dests (series (list 'IAH polars-null 'ATL 'IAH) #:name "dest"))
  (check-equal? (series-dtype dests) 'categorical)
  (check-equal? (for/list ([x dests]) x) (list 'IAH polars-null 'ATL 'IAH))
  (check-equal? (series-dtype (series (vector "a" 'b) #:dtype 'categorical)) 'categorical)
  (check-exn #rx"cannot infer a dtype" (lambda () (series (list 'a "b"))))
  (define levels (series '("info" debug) #:dtype '(enum debug info)))
  (check-equal? (dtype levels) '(enum debug info))
  (check-equal? (ref levels 0) 'info)
  (check-exn #rx"^series: 1 of 2 "
             (lambda () (series '(info error) #:dtype '(enum debug info))))
  (check-exn #rx"unsupported dtype '\\(enum debug debug\\)"
             (lambda () (series '(debug) #:dtype '(enum debug debug))))
  (define held-nul (string->symbol "a\u0000b"))
  (define nul-value #rx"^series: contract violation\n  expected: a categorical or enum value without")
  (for ([elements (list (list 'a held-nul) (vector 'a held-nul))])
    (check-exn nul-value (lambda () (series elements)))
    (check-exn nul-value (lambda () (series elements #:dtype '(enum a b)))))
  (check-exn nul-value (lambda () (series (list "api" "d\u0000b") #:dtype 'categorical)))
  (check-exn #rx"^series: contract violation\n  expected: an enum category without a NUL"
             (lambda () (series '(a) #:dtype (list 'enum 'a held-nul))))
  (check-equal? (ref (series (list "a\u0000b")) 0) "a\u0000b")

  ;; ref on series and dataframe; df ref returns a wrapped series
  (check-equal? (ref withnull 0) 10)
  (check-equal? (ref withnull 1) polars-null)
  (define df (dataframe (list ints floats)))
  (check-pred series? (ref df "floats"))
  (check-pred series? (ref df 0))
  (check-equal? (series-name (ref df "floats")) "floats")
  (check-equal? (series-name (ref df 0)) "ints")

  ;; series capability generics
  (check-equal? (len floats) 4)
  (check-equal? (shape floats) '(4))
  (check-equal? (call-with-values (lambda () (shape/values floats)) list) '(4))
  (check-equal? (dtype ints) 'int32)
  (check-equal? (null-count withnull) 1)

  (check-true (sequence? withnull))
  (check-equal? (for/list ([x withnull]) x) (list 10 polars-null 30))
  (for ([_ (in-range 2)])
    (check-equal? (sequence->list withnull) (list 10 polars-null 30)))
  (check-false (sequence? frame))

  ;; dataframe wrapper + shape / len / width / height / column metadata
  (check-pred dataframe? frame)
  (check-false (dataframe? ints))
  (check-equal? (shape frame) '(3 3))
  (check-equal? (call-with-values (lambda () (shape/values frame)) list) '(3 3))
  (check-equal? (len frame) 3)
  (check-equal? (height frame) 3)
  (check-equal? (width frame) 3)
  (check-equal? (column-name frame 0) "user")
  (check-equal? (column-names frame) '("user" "score" "cost"))

  ;; ref: single column (positional or #:columns) -> series; list -> dataframe
  (check-pred series? (ref frame "score"))
  (check-pred series? (ref frame #:columns "score"))
  (check-pred series? (ref frame #:columns 1))
  (check-equal? (dtype (ref frame #:columns "score")) 'int32)
  (define projected (ref frame #:columns '("user" "cost")))
  (check-pred dataframe? projected)
  (check-equal? (width projected) 2)
  (check-equal? (column-names projected) '("user" "cost"))

  ;; row slicing is reserved, not yet implemented
  (check-exn exn:fail? (lambda () (ref frame #:rows 0)))

  ;; custom-write prints the Polars table
  (check-true (regexp-match? #rx"shape: \\(3, 3\\)" (format "~a" frame))))

(module+ test
  (require (only-in polars/tests/test-helpers settle!))
  (define (drops-while-raising thunk)
    (settle!)
    (define before (series-drop-count))
    (check-exn exn:fail? thunk)
    (- (series-drop-count) before))
  (define held (series-new-str "levels" '("info" "error")))
  (check-equal? (- (drops-while-raising
                    (lambda () (series '(info error) #:dtype '(enum debug info))))
                   (drops-while-raising
                    (lambda () (series-cast held '(enum debug info)))))
                1))

(module+ test
  (require (only-in gregor date moment now)
           (only-in gregor/period days hours microseconds milliseconds months nanoseconds weeks)
           (only-in gregor/time time))
  (define (round-trip elements [dtype #f])
    (define s (if dtype (series elements #:dtype dtype) (series elements)))
    (list (series-dtype s) (for/list ([x s]) x)))

  (define ymds (list (date 2013 1 1) polars-null (date -1300 5 23) (date 1969 12 31)))
  (check-equal? (round-trip ymds) (list 'date ymds))
  (check-equal? (round-trip (list->vector ymds)) (list 'date ymds))
  (check-equal? (round-trip ymds 'date) (list 'date ymds))
  (define clocks (list (time 5 6 7 123456789) polars-null (time 0)))
  (check-equal? (round-trip clocks) (list 'time clocks))
  (define stamps (list (datetime 2013 1 1 5 6 7 123456000) polars-null (datetime 1969 12 31 23 59 59)))
  (check-equal? (round-trip stamps) (list '(datetime microseconds #f) stamps))
  (check-equal? (round-trip (list (datetime 2024 1 1 0 0 0 1) (datetime 2024)))
                (list '(datetime nanoseconds #f) (list (datetime 2024 1 1 0 0 0 1) (datetime 2024))))
  (define ns-edges (list (datetime 1677 9 21 0 12 43 145224192)
                        (datetime 2262 4 11 23 47 16 854775807)))
  (check-equal? (round-trip ns-edges) (list '(datetime nanoseconds #f) ns-edges))
  (check-equal? (round-trip (list (datetime 2024 1 1 0 0 0 1500) (datetime 1600 1 1 0 0 0 999)))
                (list '(datetime microseconds #f)
                      (list (datetime 2024 1 1 0 0 0 1000) (datetime 1600 1 1))))
  (check-equal? (series-dtype (series (list (now) (datetime 1600 1 1))))
                '(datetime microseconds #f))
  (check-equal? (round-trip (list (datetime 2013 1 1 5 6 7 123456789) (datetime 1600 1 1)))
                (list '(datetime microseconds #f)
                      (list (datetime 2013 1 1 5 6 7 123456000) (datetime 1600 1 1))))
  (check-equal? (round-trip (list (datetime 1995 10 16 9 30 0 123456789) (datetime 1995 11 1)))
                (list '(datetime nanoseconds #f)
                      (list (datetime 1995 10 16 9 30 0 123456789) (datetime 1995 11 1))))
  (check-equal? (round-trip (list (datetime 1995 10 16 9 30 0 123456789) (datetime 1600 1 1)))
                (list '(datetime microseconds #f)
                      (list (datetime 1995 10 16 9 30 0 123456000) (datetime 1600 1 1))))
  (check-equal? (round-trip stamps 'datetime) (list '(datetime microseconds #f) stamps))
  (check-equal? (round-trip (list (datetime 1969 12 31 23 59 59 999500000))
                            '(datetime milliseconds))
                (list '(datetime milliseconds #f) (list (datetime 1969 12 31 23 59 59 999000000))))
  (check-equal? (round-trip (list (hours 1) polars-null (milliseconds -1500)))
                (list '(duration microseconds)
                      (list (microseconds 3600000000) polars-null (microseconds -1500000))))
  (check-equal? (round-trip (list (nanoseconds 1500) (days 1)))
                (list '(duration nanoseconds)
                      (list (nanoseconds 1500) (nanoseconds 86400000000000))))
  (check-equal? (round-trip (list (nanoseconds -1500) (weeks -20000)))
                (list '(duration microseconds)
                      (list (microseconds -1) (microseconds (* -20000 7 86400 1000000)))))
  (check-equal? (round-trip (list (milliseconds 1500)) '(duration milliseconds))
                (list '(duration milliseconds) (list (milliseconds 1500))))
  (check-equal? (round-trip (list polars-null) 'date) (list 'date (list polars-null)))

  (check-exn #rx"cannot infer a dtype" (lambda () (series (list (date 2024 1 2) (datetime 2024)))))
  (check-exn #rx"cannot infer a dtype" (lambda () (series (list (months 1)))))
  (check-equal? (round-trip (list (moment 2024 1 2 #:tz "Europe/Paris") polars-null))
                (list '(datetime microseconds "Europe/Paris")
                      (list (moment 2024 1 2 #:tz "Europe/Paris") polars-null)))
  (check-equal? (round-trip (list (moment 2024 1 2 #:tz "Europe/Paris")) 'datetime)
                (list '(datetime microseconds #f) (list (datetime 2024 1 1 23))))
  (check-exn #rx"^series: cannot infer a dtype"
             (lambda () (series (list (moment 2024 1 2 #:tz "UTC") (date 2024 1 2)))))
  (check-exn #rx"^series: expected a gregor date for this dtype\n  dtype: 'date\n  value: \"2024-01-02\""
             (lambda () (series '("2024-01-02") #:dtype 'date)))
  (check-exn #rx"^series: expected a gregor period without years or months"
             (lambda () (series (list (months 1)) #:dtype '(duration microseconds))))
  (check-exn #rx"^series: value out of range for this dtype"
             (lambda () (series (list (datetime 1500)) #:dtype '(datetime nanoseconds #f)))))

(module+ test
  (require (only-in polars/private/bulk series->list)
           (only-in racket/match match match-define))
  (define (empty-series-summary s)
    (list (series-name s) (series-dtype s) (series-len s) (series->list s)))

  (check-equal? (empty-series-summary (series '())) '("" null 0 ()))
  (check-equal? (empty-series-summary (series (vector) #:name "v")) '("v" null 0 ()))
  (check-equal? (empty-series-summary (series '() #:name "empty" #:dtype 'f64))
                '("empty" float64 0 ()))
  (check-equal? (empty-series-summary (series (list polars-null) #:name "n"))
                (list "n" 'null 1 (list polars-null)))
  (check-equal? (empty-series-summary (series (vector polars-null polars-null)))
                (list "" 'null 2 (list polars-null polars-null)))
  (for ([case (list (list (list polars-null 1) 'int64) (list (vector 2.5 polars-null) 'float64)
                    (list (list polars-null "a") 'string) (list (list polars-null 'a) 'categorical))])
    (match-define (list elements expected) case)
    (check-equal? (series-dtype (series elements)) expected))
  (check-equal? (series-dtype (series '() #:dtype (series-dtype (series '())))) 'null)
  (check-equal? (empty-series-summary (series (list polars-null polars-null) #:dtype 'null))
                (list "" 'null 2 (list polars-null polars-null)))
  (check-equal? (series-len (series (vector polars-null) #:dtype 'null)) 1)
  (check-exn #rx"^series: a 'null series holds only polars-null"
             (lambda () (series '(1) #:dtype 'null)))
  (check-exn #rx"^series: a 'null series holds only polars-null"
             (lambda () (series (vector polars-null 2) #:dtype 'null)))
  (for* ([row (in-list '((i8 int8) (i16 int16) (i32 int32) (i64 int64)
                         (u8 uint8) (u16 uint16) (u32 uint32) (u64 uint64)
                         (f32 float32) (f64 float64) (bool boolean) (str string)
                         (date) (time) (datetime (datetime microseconds #f))
                         ((datetime milliseconds) (datetime milliseconds #f))
                         ((datetime nanoseconds #f))
                         ((datetime microseconds "Europe/Paris"))
                         ((duration microseconds)) ((duration nanoseconds))
                         (categorical) ((enum a b)) ((enum)) (null)))]
         [elements (in-list (list '() (vector)))])
    (define-values (spec expected)
      (match row
        [(list spec) (values spec spec)]
        [(list spec expected) (values spec expected)]))
    (check-equal? (empty-series-summary (series elements #:name "e" #:dtype spec))
                  (list "e" expected 0 '())
                  (format "~s ~s" spec elements))))

(module+ test
  (require (only-in compiler/find-exe find-exe)
           (only-in racket/match match-define)
           (only-in racket/port port->string))
  (define (placeholder what)
    (format "^#<~a: cannot print: polars panicked: [^>]+>$" what))
  (define past-chrono-probes
    `([(format "~a" (dataframe (list past-chrono-date))) ,(placeholder "dataframe")]
      [(format "~s" (dataframe (list past-chrono-datetime))) ,(placeholder "dataframe")]
      [(format "~v" (dataframe (list past-chrono-date))) ,(placeholder "dataframe")]
      [(format "~a" (collect (lazy (dataframe (list past-chrono-datetime)))))
       ,(placeholder "dataframe")]
      [(format "~a" (is-in "x" past-chrono-date)) ,(placeholder "expr")]
      [(format "~s" (is-in "x" past-chrono-date)) ,(placeholder "expr")]
      [(display-dataframe (dataframe (list past-chrono-date)) (open-output-string))
       "^display-dataframe: cannot print the dataframe: polars panicked: "]
      [(dataframe->string (dataframe (list past-chrono-date)))
       "^dataframe->string: cannot print the dataframe: polars panicked: "]
      [(expr->string (is-in "x" past-chrono-date))
       "^expr->string: cannot print the expression: polars panicked: "]
      [(cast past-chrono-date 'string) "^cast: cannot cast to string: polars panicked: "]
      [(cast past-chrono-datetime 'string) "^cast: cannot cast to string: polars panicked: "]
      [(pivot (dataframe (list past-chrono-date (series '(1) #:name "k") (series '(2) #:name "x")))
              #:on '("d") #:index '("k") #:values '("x"))
       "^pivot: cannot pivot the dataframe: polars panicked: "]
      [(unpivot (dataframe (list past-chrono-date (series '("a") #:name "k") (series '(1) #:name "i")))
                #:on '("d" "k") #:index '("i"))
       "^unpivot: cannot unpivot the dataframe: polars panicked: "]
      [(let ([path (make-temporary-file "rkt-polars-~a.ndjson")])
         (dynamic-wind void
                       (lambda () (write-ndjson (dataframe (list past-chrono-date)) path))
                       (lambda () (delete-file path))))
       "^write-ndjson: .*polars panicked: "]
      [(series-new-ymdhms "a" (list (make-YMDHMS 2021 2 30 0 0 0)))
       "^series-new-ymdhms: operation failed"]))
  (define past-chrono-program
    `(write (for/list ([probe (list ,@(for/list ([p (in-list past-chrono-probes)])
                                        (match-define (list probe _) p)
                                        `(lambda () ,probe)))])
              (with-handlers ([exn:fail? exn-message]) (format "~a" (probe))))))
  (define-values (past-chrono-child child-out child-in child-err)
    (subprocess #f #f #f (find-exe) "-l" "racket/base" "-l" "racket/file" "-l" "polars"
                "-l" "polars/tests/generic/test-fixtures"
                "-e" (format "~s" past-chrono-program)))
  (close-output-port child-in)
  (define (drained port)
    (define text (make-channel))
    (thread (lambda () (channel-put text (port->string port #:close? #t))))
    text)
  (define child-stdout (drained child-out))
  (define child-stderr (drained child-err))
  (define past-chrono-finished (sync/timeout 300 past-chrono-child))
  (unless past-chrono-finished
    (subprocess-kill past-chrono-child #t))
  (check-not-false past-chrono-finished "the child finished within 300 s")
  (check-equal? (subprocess-status past-chrono-child) 0)
  (check-equal? (channel-get child-stderr) "")
  (define past-chrono-results (read (open-input-string (channel-get child-stdout))))
  (check-equal? (length past-chrono-results) (length past-chrono-probes))
  (for ([probe (in-list past-chrono-probes)]
        [result (in-list past-chrono-results)])
    (match-define (list form expected) probe)
    (check-regexp-match expected result (format "~s gave ~s" form result))))
