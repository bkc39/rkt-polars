#lang racket/base

(module+ test
  (require rackunit racket/list
           (only-in polars/private/expr dataframe-group-by-agg)
           (only-in polars/private/expr-core col expr-drop-count lazyframe-drop-count)
           (only-in racket/string string-split)
           (only-in polars/private/foreign
                    dataframe-column dataframe-new series-cast series-new-i32 series-new-i64
                    series-new-null series-new-str series-slice polars-null)
           (only-in polars/private/generic/printing series->printed series->string)
           (only-in (submod polars/private/generic/printing internal) cell)
           (only-in polars/tests/test-helpers settle! with-environment-variable)
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
  (define (allocated thunk)
    (settle!)
    (define before (current-memory-use 'cumulative))
    (thunk)
    (- (current-memory-use 'cumulative) before))
  (define huge (series-new-i64 "huge" (range 1000000)))
  (define eleven (series-new-i64 "eleven" (range 11)))
  (check < (allocated (lambda () (series->string huge)))
         (+ (allocated (lambda () (series->string eleven))) (expt 2 20)))
  (check-equal? (series->string huge)
                (string-append "shape: (1000000,)\nSeries: 'huge' [i64]\n[\n\t0\n\t1\n\t2\n\t3\n"
                               "\t4\n\t…\n\t999995\n\t999996\n\t999997\n\t999998\n\t999999\n]"))
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
  (let ([before (expr-drop-count)]
        [plans-before (lazyframe-drop-count)])
    (series->string zoned)
    (check >= (- (expr-drop-count) before) 2)
    (check-equal? (- (lazyframe-drop-count) plans-before) 2))
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
  (test-case "a binary cell does not follow POLARS_TABLE_WIDTH, as round 1's renderer did"
    (with-environment-variable #"POLARS_TABLE_WIDTH" #"8"
      (check-equal? (binary-cells (list (xs 61) polars-null))
                    (list (string-append "b\"" (xs 60) "\"…") "null" "]"))))
  (define twelve-blobs
    (~> (series-new-str "b" (for/list ([i (in-range 12)])
                              (case i
                                [(2) "a bé"]
                                [(5) polars-null]
                                [(7) (xs 61)]
                                [else (number->string i)])))
        (series-cast 'binary)))
  ;; Python 1.42.1's repr of the same slices
  (check-equal? (series->string (series-slice twelve-blobs 3 4))
                "shape: (4,)\nSeries: 'b' [binary]\n[\n\tb\"3\"\n\tb\"4\"\n\tnull\n\tb\"6\"\n]")
  (check-equal? (series->string (series-slice twelve-blobs 1 11))
                (string-append
                 "shape: (11,)\nSeries: 'b' [binary]\n[\n"
                 "\tb\"1\"\n\tb\"a\\x20b\\xc3\\xa9\"\n\tb\"3\"\n\tb\"4\"\n\tnull\n\t…\n"
                 "\tb\"" (xs 60) "\"…\n\tb\"8\"\n\tb\"9\"\n\tb\"10\"\n\tb\"11\"\n]"))
  (define ten-megabytes (xs 10000000))
  (define large-blobs
    (~> (series-new-str "b" (list ten-megabytes ten-megabytes ten-megabytes)) (series-cast 'binary)))
  (collect-garbage)
  (define allocated-before-print (current-memory-use 'cumulative))
  (check-equal? (cells large-blobs) (append (make-list 3 (string-append "b\"" (xs 60) "\"…")) '("]")))
  (check < (- (current-memory-use 'cumulative) allocated-before-print) 1000000)
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
