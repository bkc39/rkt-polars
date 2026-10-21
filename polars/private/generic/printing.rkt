#lang racket/base

;; Polars-style rendering of a series to a string (used by the series wrapper's
;; prop:custom-write).  Operates on the raw FFI series (a wrapped series marshals
;; through), so this is a leaf with no dependency on the wrapper core.

(require (only-in gregor
                  ->date ->nanoseconds ->time ->year date->iso8601 date? datetime? moment?)
         (only-in gregor/period period-ref)
         (only-in gregor/time time? time->iso8601)
         (only-in racket/format ~r)
         racket/list
         racket/string
         (only-in polars/private/expr
                  expr-all expr-drop expr-dt-strftime lazyframe-collect/raw lazyframe-select)
         (only-in (submod polars/private/expr internal) call-with-plan)
         (only-in polars/private/resource with-release)
         polars/private/foreign
         (only-in threading ~>>))

(provide series->printed series->string)

(define (dtype->polars-label dt)
  (define (tu->label tu)
    (case tu
      [(milliseconds) "ms"]
      [(microseconds) "us"]
      [(nanoseconds)  "ns"]
      [else (format "~a" tu)]))
  (cond
    [(symbol? dt)
     (case dt
       [(int8) "i8"] [(int16) "i16"] [(int32) "i32"] [(int64) "i64"]
       [(uint8) "u8"] [(uint16) "u16"] [(uint32) "u32"] [(uint64) "u64"]
       [(float32) "f32"] [(float64) "f64"]
       [(string) "str"] [(boolean) "bool"]
       [(date) "date"] [(time) "time"]
       [(categorical) "cat"]
       [else (format "~a" dt)])]
    [(and (pair? dt) (eq? (car dt) 'enum)) "enum"]
    [(decimal-dtype? dt) (format "decimal[~a,~a]" (cadr dt) (caddr dt))]
    [(zoned-datetime-dtype? dt)
     (format "datetime[~a, ~a]" (tu->label (cadr dt)) (caddr dt))]
    [(and (pair? dt) (eq? (car dt) 'datetime))
     (format "datetime[~a]" (tu->label (cadr dt)))]
    [(and (pair? dt) (eq? (car dt) 'duration))
     (format "duration[~a]" (tu->label (cadr dt)))]
    [else (format "~a" dt)]))

(define (clock->cell t)
  (define ns (->nanoseconds t))
  (define whole (car (string-split (time->iso8601 t) ".")))
  (define digits
    (cond [(zero? ns) 0]
          [(zero? (remainder ns 1000000)) 3]
          [(zero? (remainder ns 1000)) 6]
          [else 9]))
  (if (zero? digits)
      whole
      (string-append whole "." (substring (~r ns #:min-width 9 #:pad-string "0") 0 digits))))

(define (duration->cell v unit)
  (define-values (sizes zero fraction-labels)
    (case unit
      [(nanoseconds) (values '(86400000000000 3600000000000 60000000000 1000000000)
                             "0ns" '("ns" "µs" "ms"))]
      [(milliseconds) (values '(86400000 3600000 60000 1000) "0ms" '("ms" "" ""))]
      [else (values '(86400000000 3600000000 60000000 1000000) "0µs" '("µs" "ms" ""))]))
  (define (whole-parts)
    (for/list ([size (in-list sizes)]
               [above (in-list (cons #f sizes))]
               [label (in-list '("d" "h" "m" "s"))]
               #:unless (zero? (quotient (if above (remainder v above) v) size)))
      (string-append (number->string (quotient (if above (remainder v above) v) size))
                     label
                     (if (zero? (remainder v size)) "" " "))))
  (define (fraction-part)
    (define f (remainder v (last sizes)))
    (cond
      [(zero? f) ""]
      [(not (zero? (remainder f 1000))) (format "~a~a" f (first fraction-labels))]
      [(not (zero? (remainder f 1000000))) (format "~a~a" (quotient f 1000) (second fraction-labels))]
      [else (format "~a~a" (quotient f 1000000) (third fraction-labels))]))
  (if (zero? v)
      zero
      (string-append (string-append* (whole-parts)) (fraction-part))))

(define (date->cell d)
  (if (> (->year d) 9999)
      (string-append "+" (date->iso8601 d))
      (date->iso8601 d)))

(struct unreadable (reason))

(define (cannot-print reason #:kind [kind #f])
  (format "#<~acannot print: ~a>" (if kind (format "~a: " kind) "") reason))

(define (call/cannot-print thunk #:kind [kind #f])
  (with-handlers ([exn:fail? (lambda (e) (cannot-print (exn-message e) #:kind kind))])
    (thunk)))

(define binary-shown-bytes 60)

(define (byte->cell b)
  (if (<= #x21 b #x7e)
      (string (integer->char b))
      (string-append "\\x" (~r b #:base 16 #:min-width 2 #:pad-string "0"))))

(define (bytes->cell v)
  (define shown (min (bytes-length v) binary-shown-bytes))
  (string-append "b\""
                 (~>> (subbytes v 0 shown) bytes->list (map byte->cell) string-append*)
                 (if (< shown (bytes-length v)) "\"…" "\"")))

(define (value->cell v dt [abbreviation #f])
  (cond
    [(polars-null? v) "null"]
    [(unreadable? v) (cannot-print (unreadable-reason v))]
    [(bytes? v) (bytes->cell v)]
    [(and (pair? dt) (eq? (car dt) 'duration)) (duration->cell (period-ref v (cadr dt)) (cadr dt))]
    [(date? v) (date->cell v)]
    [(time? v) (clock->cell v)]
    [(or (datetime? v) (moment? v))
     (string-append (date->cell (->date v)) " " (clock->cell (->time v))
                    (if abbreviation (string-append " " abbreviation) ""))]
    [(string? v) (format "~s" v)]      ; quoted, like Polars
    [(symbol? v) (format "~s" (symbol->string v))]
    [(and (decimal-dtype? dt) (positive? (caddr dt))) (real->decimal-string v (caddr dt))]
    [else (format "~a" v)]))

;; Polars shows at most ~10 rows: the first 5, an ellipsis, then the last 5.
(define (row-indices len)
  (if (<= len 10)
      (range len)
      (append (range 0 5) (list 'ellipsis) (range (- len 5) len))))

(define (zone-abbreviations s start count)
  (define collected
    (with-release ([rows (series-slice s start count) series-drop]
                   [frame (dataframe-new (list rows)) dataframe-drop]
                   [all (expr-all) expr-drop]
                   [zone (expr-dt-strftime all "%Z") expr-drop])
      (call-with-plan frame
                      (lambda (source) (lazyframe-select source (list zone)))
                      lazyframe-collect/raw)))
  (cond
    [collected
     (with-release ([out collected dataframe-drop]
                    [names (dataframe-column out (dataframe-column-name out 0)) series-drop])
       (for/list ([i (in-range count)])
         (series-ref names i)))]
    [(= count 1) (list #f)]
    [else (append-map (lambda (i) (zone-abbreviations s i 1)) (range start (+ start count)))]))

(define (shown-abbreviations s dt len)
  (cond
    [(not (zoned-datetime-dtype? dt)) (make-list len #f)]
    [(<= len 10) (zone-abbreviations s 0 len)]
    [else (append (zone-abbreviations s 0 5) (list #f) (zone-abbreviations s (- len 5) 5))]))

(define (cell s dt i abbreviation)
  (call/cannot-print
   (lambda ()
     (cond
       [(eq? i 'ellipsis) "…"]
       [(eq? dt 'binary) (value->cell (series-ref-bytes 'series->string s i) dt)]
       [else (value->cell (series-value 'series->string s i #:unreadable unreadable)
                          dt abbreviation)]))))

(define (series->printed s)
  (call/cannot-print (lambda () (series->string s)) #:kind 'series))

(define (series->string s)
  (define len (series-len s))
  (define dt (series-dtype s))
  (define lines
    (for/list ([i (in-list (row-indices len))]
               [abbreviation (in-list (shown-abbreviations s dt len))])
      (string-append "\t" (cell s dt i abbreviation) "\n")))
  (string-append
   (format "shape: (~a,)\n" len)
   (format "Series: '~a' [~a]\n" (series-name s) (dtype->polars-label dt))
   "[\n"
   (string-append* lines)
   "]"))

(module+ test
  ;; series->string operates on the raw FFI series, so build them directly here
  ;; (printing is a leaf — no dependency on the wrapper core).
  (require rackunit racket/list
           (only-in polars/private/expr dataframe-group-by-agg)
           (only-in polars/private/expr-core col expr-drop-count)
           (only-in polars/private/foreign
                    series-cast series-new-i32 series-new-i64 series-new-null series-new-str
                    polars-null)
           (only-in polars/private/test-helpers settle!)
           (only-in threading ~>))
  (define ints (series-new-i32 "ints" '(1 2 3 4)))
  (check-equal? (series->string (series-new-null "nothing" 3))
                "shape: (3,)\nSeries: 'nothing' [null]\n[\n\tnull\n\tnull\n\tnull\n]")
  (check-equal? (series->string (series-new-i32 "e" '())) "shape: (0,)\nSeries: 'e' [i32]\n[\n]")
  (check-equal? (series->string (series-new-i32 "one" '(7)))
                "shape: (1,)\nSeries: 'one' [i32]\n[\n\t7\n]")
  (check-true (regexp-match? #rx"shape: \\(4,\\)" (series->string ints)))
  (check-true (regexp-match? #rx"Series: 'ints' \\[i32\\]" (series->string ints)))
  (define big (series-new-i64 "big" (range 100)))
  (check-true (regexp-match? #rx"\n\t4\n\t…\n\t95\n" (series->string big)))
  (check-true (regexp-match? #rx"\n\t99\n]$" (series->string big)))
  (define withnull (series-new-i32 "withnull" (list 10 polars-null 30)))
  (check-true (regexp-match? #rx"null" (series->string withnull)))
  (define bears (series-new-str "bears" '("Polar" "Brown")))
  (check-equal? (series->string (series-cast bears 'categorical))
                "shape: (2,)\nSeries: 'bears' [cat]\n[\n\t\"Polar\"\n\t\"Brown\"\n]")
  (check-true (regexp-match? #rx"\\[enum\\]"
                             (series->string (series-cast bears '(enum Brown Polar)))))
  (check-true (regexp-match? (regexp-quote "\t\"a\\u0000b\"\n")
                             (series->string (series-new-str "nul" '("a\u0000b")))))
  (define (cells s) (cdddr (string-split (series->string s) #rx"\n\t?")))
  (check-equal? (cells (series-cast (series-new-i32 "d" '(15706 -1 2932897 -719893)) 'date))
                '("2013-01-01" "1969-12-31" "+10000-01-01" "-0001-01-01" "]"))
  (check-equal? (cells (series-cast (series-new-i64 "t" '(0 1500000000 1000 1)) 'time))
                '("00:00:00" "00:00:01.500" "00:00:00.000001" "00:00:00.000000001" "]"))
  (check-equal? (cells (series-cast (series-new-i64 "dt" (list 1500 -1 polars-null))
                                    '(datetime milliseconds)))
                '("1970-01-01 00:00:01.500" "1969-12-31 23:59:59.999" "null" "]"))
  (check-equal? (cells (series-cast (series-new-i64 "d" (list 0 5400000000 129600000000 -1500
                                                              86400000001 polars-null))
                                    '(duration microseconds)))
                '("0µs" "1h 30m" "1d 12h" "-1500µs" "1d 1µs" "null" "]"))
  (check-equal? (cells (series-cast (series-new-i64 "d" '(1500 61000000000)) '(duration nanoseconds)))
                '("1500ns" "1m 1s" "]"))
  (check-equal? (cells (series-cast (series-new-i64 "d" '(1500 0)) '(duration milliseconds)))
                '("1s 500ms" "0ms" "]"))
  (define zoned
    (series-cast (series-new-i64 "t" (list 1616842800500 polars-null 1625090400000 -1))
                 '(datetime milliseconds "Europe/Brussels")))
  (check-equal? (series->string zoned)
                (string-append "shape: (4,)\nSeries: 't' [datetime[ms, Europe/Brussels]]\n[\n"
                               "\t2021-03-27 12:00:00.500 CET\n\tnull\n\t2021-07-01 00:00:00 CEST\n"
                               "\t1970-01-01 00:59:59.999 CET\n]"))
  (settle!)
  (let ([before (expr-drop-count)])
    (series->string zoned)
    (check >= (- (expr-drop-count) before) 2))
  (check-equal? (cells (series-cast (series-new-i64 "k" '(1616842800000000))
                                    '(datetime microseconds "Asia/Kathmandu")))
                '("2021-03-27 16:45:00 +0545" "]"))
  (check-equal? (cells (series-cast (series-new-i64 "k" '(1616842800000000))
                                    '(datetime microseconds "UTC")))
                '("2021-03-27 11:00:00 UTC" "]"))
  (check-regexp-match #rx"^[+][0-9]+-[0-9][0-9]-[0-9][0-9] [0-9:.]+$"
                      (car (cells (series-cast (series-new-i64 "k" '(9223372036854775807))
                                               '(datetime milliseconds "UTC")))))
  ;; polars' reading: an LMT offset, a summer after 2037, a backward-compatible name
  (check-equal? (cells (series-cast (series-new-i64 "k" (list (* (- -2208988800 20476) 1000000)))
                                    '(datetime microseconds "Asia/Kathmandu")))
                '("1900-01-01 00:00:00 LMT" "]"))
  (check-equal? (cells (series-cast (series-new-i64 "b" '(2540368800)) '(datetime milliseconds
                                                                          "Europe/Brussels")))
                '("1970-01-30 10:39:28.800 CET" "]"))
  (check-equal? (cells (series-cast (series-new-i64 "b" '(2540282400000000))
                                    '(datetime microseconds "Europe/Brussels")))
                '("2050-07-01 12:00:00 CEST" "]"))
  (check-equal? (cells (series-cast (series-new-i64 "e" '(9223369200000000001))
                                    '(datetime nanoseconds "Asia/Tokyo")))
                '("2262-04-12 08:00:00.000000001 JST" "]"))
  (check-equal? (cells (series-cast (series-new-i64 "w" (list (+ (- (sub1 (expt 2 63)))
                                                                 3600000000000)))
                                    '(datetime nanoseconds "America/New_York")))
                '("1677-09-20 20:16:41.145224193 LMT" "]"))
  (check-equal? (cells (series-cast (series-new-i64 "p" '(1616842800000000))
                                    '(datetime microseconds "US/Pacific")))
                '("2021-03-27 04:00:00 PDT" "]"))
  (define hourly (series-cast (series-new-i64 "h" (for/list ([h (in-range 12)])
                                                    (* (+ 1616889600 (* 3600 h)) 1000000)))
                              '(datetime microseconds "Europe/Brussels")))
  (check-equal? (cells hourly)
                '("2021-03-28 01:00:00 CET" "2021-03-28 03:00:00 CEST" "2021-03-28 04:00:00 CEST"
                  "2021-03-28 05:00:00 CEST" "2021-03-28 06:00:00 CEST" "…"
                  "2021-03-28 09:00:00 CEST" "2021-03-28 10:00:00 CEST" "2021-03-28 11:00:00 CEST"
                  "2021-03-28 12:00:00 CEST" "2021-03-28 13:00:00 CEST" "]"))
  (check-equal? (cells (series-cast (series-new-i32 "d" '(2000000000)) 'date))
                '("+5477784-01-06" "]"))
  (check-equal? (cells (series-cast (series-new-i64 "k" '(1 9000000000000000000))
                                    '(datetime microseconds "Europe/Brussels")))
                '("1970-01-01 01:00:00.000001 CET"
                  "#<cannot print: polars panicked: invalid or out-of-range datetime>" "]"))
  (define (binary-cells values) (~> (series-new-str "b" values) (series-cast 'binary) cells))
  (define (check-binary-cell value shown) (check-equal? (binary-cells (list value)) (list shown "]")))
  (define (xs n) (make-string n #\x))
  ;; Python 1.42.1's series repr of each value as Binary
  (for ([value+shown
         (in-list
          `(("a" "b\"a\"")
            ("z\"q " "b\"z\"q\\x20\"")
            ("" "b\"\"")
            ("\\" "b\"\\\"")
            ("\u007f" "b\"\\x7f\"")
            ("\u0000\u001f!~" "b\"\\x00\\x1f!~\"")
            ("é" "b\"\\xc3\\xa9\"")
            (,(xs 60) ,(string-append "b\"" (xs 60) "\""))
            (,(xs 61) ,(string-append "b\"" (xs 60) "\"…"))
            (,(xs 1000) ,(string-append "b\"" (xs 60) "\"…"))
            (,(string-append (xs 59) "é") ,(string-append "b\"" (xs 59) "\\xc3\"…"))
            (,(string-append (xs 27) "é") ,(string-append "b\"" (xs 27) "\\xc3\\xa9\""))))])
    (apply check-binary-cell value+shown))
  (check-equal? (~> (series-new-str "b" (list "a" polars-null "x")) (series-cast 'binary) series->string)
                "shape: (3,)\nSeries: 'b' [binary]\n[\n\tb\"a\"\n\tnull\n\tb\"x\"\n]")
  (check-equal? (binary-cells (map number->string (range 12)))
                '("b\"0\"" "b\"1\"" "b\"2\"" "b\"3\"" "b\"4\"" "…"
                  "b\"7\"" "b\"8\"" "b\"9\"" "b\"10\"" "b\"11\"" "]"))
  (define table-width (getenv "POLARS_TABLE_WIDTH"))
  (dynamic-wind
   (lambda () (putenv "POLARS_TABLE_WIDTH" "8"))
   (lambda ()
     (check-equal? (binary-cells (list (xs 61) polars-null))
                   (list (string-append "b\"" (xs 60) "\"…") "null" "]")))
   (lambda ()
     (environment-variables-set! (current-environment-variables) #"POLARS_TABLE_WIDTH"
                                 (and table-width (string->bytes/utf-8 table-width)))))
  (check-equal? (cell ints 'binary 0 #f)
                "#<cannot print: series->string: cannot read a binary value at index 0>")
  (define nested
    (dataframe-group-by-agg (dataframe-new (list (series-new-i32 "g" '(1 1))
                                                 (series-new-i32 "v" '(2 3))))
                            '("g")
                            (list (col "v"))))
  (check-regexp-match #rx"\n\\[\n\t#<cannot print: series->string: unsupported dtype "
                      (series->string (dataframe-column nested "v")))
  (check-regexp-match #rx"^#<series: cannot print: Series-ptr->C: " (series->printed 'not-a-series)))
