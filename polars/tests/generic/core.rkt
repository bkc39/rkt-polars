#lang racket/base

(module+ test
  (require rackunit
           (for-syntax racket/base)
           (only-in gregor ->datetime/local ->posix date datetime moment now)
           (only-in gregor/period days hours microseconds milliseconds months nanoseconds weeks)
           (only-in gregor/time time)
           (only-in racket/contract
                    blame-positive blame-source exn:fail:contract:blame-object
                    exn:fail:contract:blame?)
           (only-in racket/match match match-define)
           (only-in racket/runtime-path define-runtime-path)
           (only-in racket/sequence sequence->list)
           (only-in racket/stream stream)
           (only-in racket/string string-contains?)
           (only-in syntax/location quote-module-name)
           syntax/parse/define
           (only-in threading ~>)
           (only-in polars/private/bulk series->list)
           (only-in polars/private/foreign
                    dataframe->string dataframe-column dataframe-column-names dataframe-new
                    polars-null series-cast series-drop-count series-dtype series-len series-name
                    series-new-i32 series-new-i64 series-new-str)
           (prefix-in contracted: polars/private/generic/core)
           (only-in polars/private/generic/core
                    column-name column-names dataframe dataframe? dtype height len null-count
                    ref series series? shape shape/values width wrap-series)
           (only-in (submod polars/private/generic/core internal)
                    column-option-keywords columns->dataframe)
           (only-in polars/private/generic/convert
                    dataframe->rows in-dataframe-columns in-dataframe-rows)
           (only-in polars/private/generic/operators [= p=])
           (only-in polars/private/generic/parquet read-parquet)
           (only-in polars/private/generic/reshape cast filter pivot rename rename! select)
           (only-in polars/private/generic/printing series->string)
           (only-in polars/tests/generic/test-fixtures
                    check-cells col named-frame nul-frame nul-names series-cells)
           (only-in (submod polars/tests/generic/test-fixtures test) call-each-in-child)
           (only-in polars/tests/test-helpers settle! with-environment-variable))
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
  (check-exn #rx"series: expected a gregor date, datetime or moment for this dtype"
             (lambda () (series '(1) #:dtype '(datetime microseconds "UTC"))))
  (check-exn #rx"^series: contract violation\n  expected: time-zone-name/c\n  given: \"\"\n"
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
  (for ([elements (in-list (list (list 'a held-nul) (vector 'a held-nul)))])
    (check-cells (series elements) (list 'a held-nul))
    (check-cells (series elements #:dtype (list 'enum held-nul 'a)) (list 'a held-nul)))
  (check-equal? (map symbol->string
                     (series->list (series (list "api" "d\u0000b") #:dtype 'categorical)))
                '("api" "d\u0000b"))
  (for ([n (in-list nul-names)])
    (define held (string->symbol n))
    (check-cells (series (list n "c" polars-null) #:dtype 'categorical) (list held 'c polars-null))
    (define levels (series (list n "c") #:dtype (list 'enum 'c held)))
    (check-equal? (dtype levels) (list 'enum 'c held))
    (check-cells levels (list held 'c)))
  (define nul-codes
    (dataframe (list (series (list "a" "a\u0000b" "c") #:name "c" #:dtype 'categorical))))
  (check-equal? (series-cells (ref (filter nul-codes (p= (col "c") held-nul)) "c")) (list held-nul))
  (check-equal? (series->list (p= (series (list 'a held-nul 'c) #:dtype (list 'enum 'a held-nul 'c))
                                  held-nul))
                '(#f #t #f))
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
  (check-true (regexp-match? #rx"shape: \\(3, 3\\)" (format "~a" frame)))

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
                1)

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

  (for ([bad (list #f 'x #"\377")])
    (check-exn #rx"^series: contract violation\n  expected: [^\n]*utf-8\\?[^\n]*"
               (lambda () (series '(1) #:name bad))))
  (check-equal? (series-name (series '(1) #:name #"q")) "q")
  (check-exn #rx"cannot infer a dtype" (lambda () (series (list (date 2024 1 2) (datetime 2024)))))
  (define datetime-dtype-dates (list (date 2013 1 1) polars-null (date 1500 5 23)))
  (define datetime-dtype-midnights (list (datetime 2013 1 1) polars-null (datetime 1500 5 23)))
  (for ([unit '(milliseconds microseconds)])
    (check-equal? (round-trip datetime-dtype-dates (list 'datetime unit))
                  (list (list 'datetime unit #f) datetime-dtype-midnights)))
  (check-equal? (round-trip datetime-dtype-dates 'datetime)
                (list '(datetime microseconds #f) datetime-dtype-midnights))
  (check-equal? (round-trip (list->vector datetime-dtype-dates) 'datetime)
                (list '(datetime microseconds #f) datetime-dtype-midnights))
  (check-equal? (round-trip (list (date 2013 1 1) polars-null) '(datetime nanoseconds))
                (list '(datetime nanoseconds #f) (list (datetime 2013 1 1) polars-null)))
  (for ([unit '(milliseconds nanoseconds)])
    (check-equal? (round-trip (list (date 2013 1 1) polars-null (date 2013 7 1))
                              (list 'datetime unit "Europe/Paris"))
                  (list (list 'datetime unit "Europe/Paris")
                        (list (moment 2013 1 1 1 #:tz "Europe/Paris") polars-null
                              (moment 2013 7 1 2 #:tz "Europe/Paris")))))
  (check-equal? (round-trip (list (date 2013 1 1)) '(datetime microseconds "Asia/Kathmandu"))
                (list '(datetime microseconds "Asia/Kathmandu")
                      (list (moment 2013 1 1 5 45 #:tz "Asia/Kathmandu"))))
  (check-exn (regexp (string-append "^series: value out of range for this dtype\n"
                                    "  dtype: '\\(datetime nanoseconds\\)\n  value: #<date 1500-05-23>$"))
             (lambda () (series datetime-dtype-dates #:dtype '(datetime nanoseconds))))
  (for ([vals (list (list (datetime 2013 1 1 5)) (vector polars-null (moment 2013 1 1 #:tz "UTC")))])
    (check-exn #rx"^series: expected a gregor date for this dtype\n  dtype: 'date\n  value: #<"
               (lambda () (series vals #:dtype 'date))))
  (for ([mixed (list (list (date 2013 1 1) (datetime 2013 1 1 5))
                     (list (date 2013 1 1) polars-null (datetime 2013 1 1 5))
                     (list polars-null (datetime 2013 1 1 5) (date 2013 1 1))
                     (vector (moment 2013 1 1 #:tz "UTC") (date 2013 1 1)))])
    (check-exn #rx"^series: cannot mix gregor dates with datetimes or moments\n  dtype: 'datetime\n"
               (lambda () (series mixed #:dtype 'datetime))))
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
             (lambda () (series (list (datetime 1500)) #:dtype '(datetime nanoseconds #f))))

  (define (local-clocks elements [dtype #f])
    (match-define (list dt instants) (round-trip elements dtype))
    (list dt (map ->datetime/local instants)))
  (define new-york '(datetime milliseconds "America/New_York"))
  (define kathmandu '(datetime milliseconds "Asia/Kathmandu"))
  (for ([value (list (date -262143 1 1) (datetime -262143 1 1 4 56 1 999000000))])
    (check-exn (regexp (string-append "^series: value out of range for this dtype\n"
                                      "  dtype: '\\(datetime milliseconds \"America/New_York\"\\)\n"
                                      "  value: " (regexp-quote (format "~v" value)) "$"))
               (lambda () (series (list value) #:dtype new-york))))
  (check-exn (regexp (string-append "^series: value out of range for this dtype\n"
                                    "  dtype: '\\(datetime milliseconds \"Asia/Kathmandu\"\\)\n"
                                    "  value: #<datetime 262142-12-31T18:15:00>$"))
             (lambda () (series (list (datetime 262142 12 31 18 15)) #:dtype kathmandu)))
  (for ([m (list (moment -262144 12 31 20 #:tz "America/New_York")
                 (moment 262143 1 1 1 #:tz "Asia/Kathmandu"))])
    (check-exn (regexp (string-append "^series: value out of range for this dtype\n"
                                      "  dtype: '\\(datetime microseconds \""))
               (lambda () (series (list polars-null m)))))
  (define gmt-14 '(datetime microseconds "Etc/GMT-14"))
  (check-exn #rx"^series: value out of range for this dtype\n"
             (lambda () (series (vector (datetime 262142 12 31 23)) #:dtype gmt-14)))
  (check-equal? (local-clocks (list (datetime -262143 1 1 4 56 2)) new-york)
                (list new-york (list (datetime -262143 1 1))))
  (check-equal? (local-clocks (list (date -262143 1 2) (date 262142 12 31)) new-york)
                (list new-york (list (datetime -262143 1 1 19 3 58) (datetime 262142 12 30 19))))
  (check-equal? (local-clocks (list (datetime 262142 12 31 18 14 59 999000000)) kathmandu)
                (list kathmandu (list (datetime 262142 12 31 23 59 59 999000000))))
  (check-equal? (local-clocks (list (date -262143 1 1)) kathmandu)
                (list kathmandu (list (datetime -262143 1 1 5 41 16))))
  (check-equal? (local-clocks (list (datetime 262142 12 31 23 59 59 999000000)) new-york)
                (list new-york (list (datetime 262142 12 31 18 59 59 999000000))))
  (for ([edges (list (list (date -262143 1 1) (date 262142 12 31))
                     (list (datetime -262143 1 1) (datetime 262142 12 31 23 59 59)))]
        [clocks (list (list (datetime -262143 1 1) (datetime 262142 12 31))
                      (list (datetime -262143 1 1) (datetime 262142 12 31 23 59 59)))])
    (check-equal? (local-clocks edges '(datetime microseconds "UTC"))
                  (list '(datetime microseconds "UTC") clocks)))
  (check-equal? (~> (moment -262143 1 1 1 #:tz "America/New_York") list series (ref 0) ->posix)
                (->posix (moment -262143 1 1 1 #:tz "America/New_York")))

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
                  (format "~s ~s" spec elements)))

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
      [(with-release ([path (make-temporary-file "rkt-polars-~a.ndjson") delete-file])
         (write-ndjson (dataframe (list past-chrono-date)) path))
       "^write-ndjson: .*polars panicked: "]
      [(series-new-ymdhms "a" (list (make-YMDHMS 2021 2 30 0 0 0)))
       "^series-new-ymdhms: invalid date and time: 2021-02-30 00:00:00$"]))
  (define-values (past-chrono-status past-chrono-runs past-chrono-completed past-chrono-stderr)
    (call-each-in-child
     '((only-in polars/ffi dataframe->string display-dataframe)
       (only-in polars/private/foreign make-YMDHMS series-new-ymdhms))
     (for/list ([probe (in-list past-chrono-probes)])
       (match-define (list form _) probe)
       `(with-handlers ([exn:fail? exn-message]) (format "~a" ,form)))
     #:timeout 300
     #:libraries '("racket/file" "polars" "polars/private/resource"
                   "polars/tests/generic/test-fixtures")))
  (check-equal? past-chrono-status 0 past-chrono-stderr)
  (check-equal? past-chrono-completed (length past-chrono-probes) past-chrono-stderr)
  (check-not-false past-chrono-runs past-chrono-stderr)
  (for ([probe (in-list past-chrono-probes)]
        [run (in-list (or past-chrono-runs '()))])
    (match-define (list form expected) probe)
    (match-define (list result stderr) run)
    (check-regexp-match expected result (format "~s gave ~s" form result))
    (check-equal? stderr "" (format "~s wrote to stderr" form)))

  (define (shown-unwrapped nul n)
    (with-environment-variable #"POLARS_TABLE_WIDTH" #"200"
      (list (format "~a" nul) (dataframe->string nul)
            (format "~a" (dataframe (list (series (list n) #:name "v")))))))
  (for ([n (in-list nul-names)])
    (define nul (nul-frame n))
    (check-equal? (column-names nul) (list "id" n))
    (check-equal? (column-name nul 0) "id")
    (check-equal? (column-name nul 1) n)
    (for ([shown (in-list (shown-unwrapped nul n))])
      (check-true (string-contains? shown n) shown)
      (check-false (string-contains? shown "cannot print") shown)))

  (for ([n (in-list nul-names)])
    (for ([xs (in-list (list '(1 2) '(1.5 2.5) '(#t #f) (list polars-null) '("x" "y")
                             (list (date 2020 1 2)) (list (datetime 2020 1 2 3))))])
      (check-equal? (series-name (series xs #:name n)) n))
    (define named (named-frame n))
    (check-equal? (column-names named) (list n "a"))
    (check-equal? (series->list (ref named n)) '(1 2))
    (check-equal? (series->list (ref named "a")) '(3 4))
    (check-equal? (series-name (ref named 0)) n)
    (check-equal? (for/list ([c (in-dataframe-columns named)]) (series->list c)) '((1 2) (3 4)))
    (check-equal? (sequence->list (in-dataframe-rows named)) '(#(1 3) #(2 4)))
    (check-equal? (column-names (select named (column-names named))) (list n "a"))
    (check-exn (regexp (regexp-quote n))
               (lambda () (dataframe (list (series '(1) #:name n) (series '(2) #:name n))))))
  (define collided
    (pivot (dataframe (list (series '(0 0) #:name "id") (series '("a" "a\u0000b") #:name "k")
                            (series '(1 2) #:name "v")))
           #:on '("k") #:index '("id") #:values '("v")))
  (check-equal? (column-names collided) '("id" "a" "a\u0000b"))
  (check-equal? (series->list (ref collided 2)) '(2))
  (check-equal? (series->list (ref collided "a\u0000b")) '(2))
  (check-equal? (for/list ([c (in-dataframe-columns collided)]) (series->list c)) '((0) (1) (2)))
  (check-equal? (sequence->list (in-dataframe-rows collided)) '(#(0 1 2)))
  (check-equal? (column-names (select collided (column-names collided))) '("id" "a" "a\u0000b"))
  (check-equal? (column-names (dataframe (list (series '(1) #:name "a")
                                              (series '(2) #:name "a\u0000b"))))
                '("a" "a\u0000b"))
  (check-equal? (width (dataframe (list (series '(1) #:name "a\u0000x")
                                        (series '(1) #:name "a\u0000y"))))
                2)

  (test-case "the reference's bridge from polars/ffi: dataframe takes raw series"
    (define raw (series-new-i32 "n" '(1 2)))
    (check-equal? (series->list (ref (contracted:dataframe (list raw)) "n")) '(1 2))
    (check-exn #rx"^len: contract violation:\n  expected: sized[?]" (lambda () (len raw)))
    (check-exn #rx"^dataframe: contract violation\n  expected: \\(or/c Series-ptr\\? \\(listof Series-ptr\\?\\)\\)\n  given: 1\n"
               (lambda () (contracted:dataframe 1)))
    (define raw-frame (dataframe-new (list raw (series-new-str "s" '("a" "b")))))
    (define rebuilt
      (contracted:dataframe (for/list ([name (in-list (dataframe-column-names raw-frame))])
                              (dataframe-column raw-frame name))))
    (check-pred dataframe? rebuilt)
    (check-equal? (shape rebuilt) '(2 2))
    (check-equal? (series->list (ref rebuilt "s")) '("a" "b")))

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
  (define (define-in-namespace! name v [namespace clause-namespace])
    (parameterize ([current-namespace namespace])
      (namespace-set-variable-value! name v)))
  (define (bracketed . elems)
    (syntax-property (datum->syntax #f elems) 'paren-shape #\[))
  (define (frame-of . clauses)
    (datum->syntax #f (cons 'dataframe clauses)))
  (define (in-module form)
    `(module m racket/base (require polars) ,form))

  (test-case "a clause builds the column series builds"
    (define clause-values
      (list '(1 2 3) '(1.5 2.5) '("a" "b") (list 1 polars-null 3)
            (list (date 2024 1 1) (date 2024 6 1)) (list (time 1 2 3))
            (list (datetime 2024 1 1 12)) (list (moment 2024 1 1 #:tz "Europe/Brussels"))
            (list (hours 1) (days 2)) '(a b a) '() (vector 1 2 3) (list polars-null)))
    (define clause-dtypes
      (list #f 'i32 'u8 'f64 '(enum a b) '(datetime microseconds "UTC") 'null))
    (define (outcome thunk)
      (with-handlers ([exn:fail? (lambda (_) 'failed)])
        (frame-datum (thunk))))
    (define built
      (for*/list ([v (in-list clause-values)]
                  [d (in-list clause-dtypes)])
        (define expected (outcome (lambda () (series-frame (series v #:name "k" #:dtype d)))))
        (define label (format "~s #:dtype ~s" v d))
        (check-equal? (outcome (lambda () (dataframe [v #:name "k" #:dtype d]))) expected label)
        (check-equal? (outcome (lambda () (dataframe ["k" v #:dtype d]))) expected label)
        (check-equal? (outcome (lambda () (dataframe [k v #:dtype d]))) expected label)
        expected))
    (check-true (> (length (remove* '(failed) built)) 20)))

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
  (for ([name (in-list '(s1 s2 s3))]
        [v (in-list (list s1 s2 s3))])
    (define-in-namespace! name v))
  (define-in-namespace! 'cols (list s1 s2))

  (test-case "an expression clause is a series or a list of series, spliced in"
    (define pair-datum (frame-datum (series-frame s1 s2)))
    (check-equal? (frame-datum (run '(dataframe (list s1 s2)))) pair-datum)
    (check-equal? (frame-datum (run '(dataframe s1 s2))) pair-datum)
    (check-equal? (frame-datum (run '(dataframe cols))) pair-datum)
    (check-equal? (shape (run '(dataframe '()))) '(0 0))
    (check-equal? (shape (run '(dataframe))) '(0 0))
    (check-equal? (column-names (run '(dataframe s1 [b '(3 4)] (list s3) (list))))
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

  (define-syntax-parser blame-case
    [(_ form:expr) #`(list #,(syntax-line #'form) (lambda () form))])

  (define (check-blamed case expected #:line? [line? #t])
    (match-define (list line thunk) case)
    (define e (with-handlers ([exn:fail:contract:blame? values]) (thunk) #f))
    (check-pred exn:fail:contract:blame? e)
    (when e
      (check-regexp-match expected (exn-message e))
      (define blame (exn:fail:contract:blame-object e))
      (check-equal? (blame-positive blame) (quote-module-name))
      (when line?
        (check-equal? (srcloc-line (blame-source blame)) line))))

  (define (values-refusal given)
    (regexp (string-append
             "^dataframe: contract violation\n  expected: a list, vector, series or sequence, "
             "not a string, byte string, hash or number\n  given: " (regexp-quote given) "\n")))

  (test-case "a clause's arguments are checked by contract, blaming the clause"
    (check-blamed (blame-case (dataframe 5))
                  #rx"^dataframe: contract violation\n  expected: \\(or/c Series-ptr\\? \\(listof Series-ptr\\?\\)\\)\n  given: 5\n")
    (check-blamed (blame-case (dataframe [a "abc"])) (values-refusal "\"abc\""))
    (check-blamed (blame-case (dataframe [a #"x"])) (values-refusal "#\"x\""))
    (check-blamed (blame-case (dataframe [a (hash)])) (values-refusal "'#hash()"))
    (check-blamed (blame-case (dataframe [a 3])) (values-refusal "3"))
    (check-blamed (blame-case (dataframe [a (in-indexed '(a))]))
                  #rx"^dataframe: contract violation\n  expected: a sequence of single values\n")
    (check-blamed (blame-case (dataframe ['(1) #:name 5]))
                  #rx"^dataframe: contract violation\n  expected: \\(or/c symbol\\? \\(or/c string\\? ")
    (check-blamed (blame-case (dataframe [x '(1) #:dtype 'bogus]))
                  #rx"^dataframe: contract violation\n  expected: \\(or/c #f \\(and/c datetime-zone/c")
    (check-blamed (blame-case (dataframe [x '(300) #:dtype 'u8]))
                  #rx"^dataframe: contract violation\n  expected: uint8/c\n  given: 300\n")
    (check-blamed (blame-case (apply dataframe '(5)))
                  #rx"^dataframe: contract violation\n  expected: \\(or/c Series-ptr\\? \\(listof Series-ptr\\?\\)\\)\n  given: 5\n  in: an element of\n      the rest argument of"
                  #:line? #f))

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
                 (dataframe [a (noted 1 '(1))] [b (noted 2 '(2))] [c (noted 3 "abc")]
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

  (define (syntax-failure program)
    (with-handlers ([exn:fail:syntax? values])
      (run program)
      #f))

  (define (check-syntax-error form expected highlighted #:contexts [contexts '(top module)])
    (for ([context (in-list contexts)])
      (define e (syntax-failure (if (eq? context 'module) (in-module form) form)))
      (define label (format "~a: ~s" context (syntax->datum form)))
      (check-pred exn:fail:syntax? e label)
      (when e
        (check-regexp-match expected (exn-message e) label)
        (check-equal? (syntax->datum (car (exn:fail:syntax-exprs e))) highlighted label))))

  (define (message-rx text)
    (regexp (string-append "^dataframe: " (regexp-quote text))))

  (test-case "a clause that is not a column is a syntax error under dataframe"
    (define (bound-here name)
      (message-rx (format (string-append "~a is bound here, so this bracketed clause is not a "
                                         "column; name a column with #:name, as in [vals "
                                         "#:name '~a], or with a string, as in [~s vals], or "
                                         "drop the brackets for an expression")
                          name name (symbol->string name))))
    (check-syntax-error (frame-of (bracketed 'date ''(1))) (bound-here 'date) 'date)
    (check-syntax-error (datum->syntax #f (list 'let '([xs '()]) (frame-of (bracketed 'xs ''(1)))))
                        (bound-here 'xs) 'xs)
    (define not-a-column
      (message-rx (string-append "a bracketed clause is a column, [vals #:name name option ...] "
                                 "or [name vals option ...], where name is a string or an "
                                 "identifier with no binding")))
    (check-syntax-error (frame-of (bracketed)) not-a-column '())
    (check-syntax-error (frame-of (bracketed '(list 1) '#:dtype ''i32)) not-a-column
                        '((list 1) #:dtype 'i32))
    (check-syntax-error (frame-of (bracketed 'k ''(1) ''(2))) not-a-column '(k '(1) '(2)))
    (define string-head (message-rx "a clause headed by a string is a column, [\"a\" vals option ...]"))
    (check-syntax-error (frame-of '("a")) string-head '("a"))
    (check-syntax-error (frame-of (bracketed "a" ''(1) ''(2))) string-head '("a" '(1) '(2)))
    (define (named-twice name)
      (message-rx (format "~a has no binding here, so it names the column, and #:name cannot name it again"
                          name)))
    (check-syntax-error (frame-of (bracketed 'k ''(1) '#:name "n")) (named-twice 'k) '#:name)
    (check-syntax-error (frame-of '(serie '(1) #:name "n")) (named-twice 'serie) '#:name)
    (check-syntax-error (frame-of (bracketed "k" ''(1) '#:name "n"))
                        (message-rx "\"k\" names the column, so #:name cannot name it again")
                        '#:name)
    (define unknown-option
      (message-rx "#:foo is not a column option; the options are #:name and #:dtype"))
    (check-syntax-error (frame-of (bracketed 'k ''(1) '#:foo 1)) unknown-option '#:foo)
    (check-syntax-error (frame-of (bracketed ''(1) '#:name "a" '#:foo 1)) unknown-option '#:foo)
    (check-syntax-error (frame-of (bracketed 'k ''(1) '#:dtype ''i32 '#:dtype ''i64))
                        (message-rx "#:dtype appears twice in one column") '#:dtype)
    (check-syntax-error (frame-of (bracketed ''(1) '#:name "a" '#:name "b"))
                        (message-rx "#:name appears twice in one column") '#:name)
    (define duplicate-name (message-rx "duplicate column name \"a\""))
    (check-syntax-error (frame-of (bracketed 'a ''(1)) (bracketed "a" ''(2))) duplicate-name "a"
                        #:contexts '(module))
    (check-syntax-error (frame-of (bracketed 'a ''(1)) (bracketed ''(2) '#:name ''a)) duplicate-name
                        ''a #:contexts '(module))
    (check-exn #rx"^dataframe: could not create a new DataFrame: column with name 'a' has more"
               (lambda () (run (frame-of (bracketed 'a ''(1)) (bracketed "a" ''(2))))))
    (check-syntax-error (datum->syntax #f '(dataframe . 1)) #rx"dataframe: bad syntax"
                        '(dataframe . 1)))

  (test-case "a column clause means the same in brackets and in parentheses"
    (for ([clause (in-list (list (list ''(1 2) '#:name "a") (list "a" ''(1 2))
                                 (list 'kk ''(1 2) '#:dtype ''f64)))])
      (check-equal? (frame-datum (run (frame-of (apply bracketed clause))))
                    (frame-datum (run (frame-of clause))))))

  (test-case "at the top level a head with no binding is looked up each time it runs"
    (define top (fresh-namespace))
    (define (top-run form) (run form top))
    (top-run '(define (mk xs) (series xs #:name "m")))
    (check-equal? (column-names (top-run '(dataframe (mk '(1 2))))) '("m"))
    (check-exn #rx"^dataframe: mk is bound here"
               (lambda () (top-run (frame-of (bracketed 'mk ''(1))))))
    (top-run '(define (b1) (dataframe (later '(1 2)))))
    (top-run '(define (later xs) (series xs #:name "l")))
    (check-equal? (column-names (top-run '(b1))) '("l"))
    (top-run '(define (b2) (dataframe (never '(1)))))
    (check-equal? (column-names (top-run '(b2))) '("never"))
    (top-run '(define (never xs) (series xs #:name "n")))
    (check-equal? (column-names (top-run '(b2))) '("n"))
    (top-run (datum->syntax #f (list 'define '(b3) (frame-of (bracketed 'later2 ''(1))))))
    (top-run '(define later2 1))
    (define (syntax-error? rx)
      (lambda (e) (and (exn:fail:syntax? e) (regexp-match? rx (exn-message e)))))
    (check-exn (syntax-error? #rx"^dataframe: later2 is bound here") (lambda () (top-run '(b3))))
    (check-exn (syntax-error? #rx"^dataframe: k2 has no binding here")
               (lambda () (top-run '(dataframe (k2 '(1) #:name "n")))))
    (top-run '(define zz 1))
    (top-run `(module forward racket/base
                (require polars)
                (provide forward named)
                (define (forward) (dataframe (later '(1))))
                (define (later xs) (series xs #:name "l"))
                (define named ,(frame-of (bracketed 'zz ''(1))))))
    (top-run '(require 'forward))
    (check-equal? (column-names (top-run '(forward))) '("l"))
    (check-equal? (column-names (top-run 'named)) '("zz")))

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
    (define samples (hash '#:dtype ''i64))
    (for ([kw (in-list column-option-keywords)])
      (check-pred dataframe? (run (frame-of (bracketed ''(1) '#:name "a" kw (hash-ref samples kw)))))))

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
    (define-in-namespace! 'carriers carriers)
    (check-equal? (frame-datum (run '(dataframe (list carriers) (series '(1 2) #:name "n"))))
                  '(("c" "n") (string int64) (#("UA" 1) #("AA" 2))))
    (check-equal? (frame-datum (apply dataframe (frame-columns (dataframe [a '(1 2)] [b '(3 4)]))))
                  '(("a" "b") (int64 int64) (#(1 3) #(2 4))))
    (check-syntax-error (frame-of (bracketed 'date '(list (date 2026 1 1))))
                        #rx"^dataframe: date is bound here" 'date #:contexts '(top))
    (check-syntax-error (frame-of (bracketed 'k ''(1 2) '#:name "n"))
                        #rx"^dataframe: k has no binding here" '#:name #:contexts '(top))
    (check-exn #rx"^dataframe: could not create a new DataFrame: height"
               (lambda () (run '(dataframe [a '(1 2)] [b '(3)]))))
    (check-exn (lambda (e) (and (exn:fail:contract:blame? e)
                                (regexp-match? #rx"^dataframe: contract violation" (exn-message e))))
               (lambda () (run '(dataframe [a "abc"]))))))
