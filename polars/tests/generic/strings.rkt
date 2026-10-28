#lang racket/base

(module+ test
  (require rackunit (only-in threading ~>)
           (only-in racket/contract exn:fail:contract:blame?)
           (only-in racket/contract/base contract-name)
           (only-in gregor date datetime moment resolve-offset/post resolve-offset/pre)
           (only-in polars/private/bulk series->list)
           (only-in polars/private/c-integer int64/c nonnegative-int64/c)
           (only-in racket/match match match-define)
           (only-in polars/private/expr col lit)
           (only-in polars/private/generic/nullable fill-null)
           (only-in polars/private/generic/operators [= p=] [!= p!=])
           (only-in polars/tests/generic/test-fixtures nul-expected)
           (only-in polars/private/foreign polars-null)
           (only-in polars/private/generic/core column-names dataframe dtype ref series)
           (only-in polars/private/generic/reductions alias)
           (only-in polars/private/generic/reshape collect lazy select with-columns)
           (prefix-in contracted: polars/private/generic/strings)
           (only-in polars/private/generic/strings
                    str->date str->time str-contains str-count-matches str-ends-with str-find
                    str-find-literal str-head str-len-bytes str-len-chars str-replace
                    str-replace-all str-starts-with str-strip-chars str-strip-prefix
                    str-strip-suffix str-tail str-to-lowercase str-to-uppercase)
           (only-in (submod polars/private/generic/strings internal)
                    str->datetime str-extract str-slice))
  (define df (dataframe (list (series '("Ab" "cD" "ef") #:name "s"))))
  (define out
    (~> df lazy
        (with-columns
          (alias (str-to-lowercase "s") "lo")
          (alias (str-to-uppercase "s") "hi")
          (alias (str-contains "s" "b") "has_b")
          (alias (str-starts-with "s" "A") "starts_a")
          (alias (str-ends-with "s" "f") "ends_f"))
        collect))
  (check-equal? (ref (ref out #:columns "lo") 0) "ab")
  (check-equal? (ref (ref out #:columns "hi") 1) "CD")
  (check-equal? (ref (ref out #:columns "has_b") 0) #t)
  (check-equal? (ref (ref out #:columns "has_b") 1) #f)
  (check-equal? (ref (ref out #:columns "starts_a") 0) #t)
  (check-equal? (ref (ref out #:columns "ends_f") 2) #t)
  ;; an Expr argument works the same as a column-name string
  (check-equal? (ref (ref (~> df (with-columns (alias (str-to-uppercase (col "s")) "u")))
                          #:columns "u")
                     0)
                "AB")
  ;; batch 2: strip / replace / extract
  (define t
    (dataframe (list (series '("  alpha  " "--beta--" "id=123" "report.txt" "banana")
                             #:name "text"))))
  (define out2
    (~> t (with-columns
            (alias (str-strip-chars "text") "trimmed")
            (alias (str-strip-chars "text" "-") "stripped")
            (alias (str-strip-prefix "text" "id=") "no_prefix")
            (alias (str-strip-suffix "text" ".txt") "no_suffix")
            (alias (str-replace "text" "\\d+" "#") "rep")
            (alias (str-replace-all "text" "a" "A" #:literal #t) "rep_all")
            (alias (str-extract "text" "([0-9]+)") "digits"))))
  (check-equal? (ref (ref out2 #:columns "trimmed") 0) "alpha")
  (check-equal? (ref (ref out2 #:columns "stripped") 1) "beta")
  (check-equal? (ref (ref out2 #:columns "no_prefix") 2) "123")
  (check-equal? (ref (ref out2 #:columns "no_suffix") 3) "report")
  (check-equal? (ref (ref out2 #:columns "rep") 2) "id=#")
  (check-equal? (ref (ref out2 #:columns "rep_all") 4) "bAnAnA")
  (check-equal? (ref (ref out2 #:columns "digits") 2) "123")
  ;; batch 3: lengths / slice / head / tail / find / count
  (define u
    (dataframe (list (series '("hello" "héllo" "banana" "abc123abc") #:name "text"))))
  (define out3
    (~> u (with-columns
            (alias (str-len-bytes "text") "bytes")
            (alias (str-len-chars "text") "chars")
            (alias (str-slice "text" 1 3) "slice")
            (alias (str-head "text" 2) "head")
            (alias (str-tail "text" 2) "tail")
            (alias (str-find "text" "[0-9]+") "find_d")
            (alias (str-find-literal "text" "na") "find_na")
            (alias (str-count-matches "text" "a" #:literal #t) "count_a"))))
  (check-equal? (ref (ref out3 #:columns "bytes") 1) 6)   ; é is 2 bytes
  (check-equal? (ref (ref out3 #:columns "chars") 1) 5)
  (check-equal? (ref (ref out3 #:columns "slice") 0) "ell")
  (check-equal? (ref (ref out3 #:columns "head") 1) "hé")
  (check-equal? (ref (ref out3 #:columns "tail") 2) "na")
  (check-equal? (ref (ref out3 #:columns "find_d") 3) 3)
  (check-equal? (ref (ref out3 #:columns "find_na") 2) 2)
  (check-equal? (ref (ref out3 #:columns "count_a") 2) 3)
  (define words
    (dataframe (list (series (list "hello" "héllo" polars-null "ab") #:name "s")
                     (series (list 1 polars-null 2 0) #:name "n"))))
  (define (sliced . exprs)
    (define d (apply select words exprs))
    (map (lambda (name) (series->list (ref d name))) (column-names d)))
  (check-equal? (sliced (alias (str-slice "s" 1 #f) "rest")
                        (alias (str-slice "s" 1) "omitted")
                        (alias (str-slice "s" 1 polars-null) "null")
                        (alias (str-slice "s" -2) "last2")
                        (alias (str-slice "s" -4 2) "mid")
                        (alias (str-slice "s" 10) "past")
                        (alias (str-slice "s" 0 (col "n")) "by_col"))
                (list (list "ello" "éllo" polars-null "b")
                      (list "ello" "éllo" polars-null "b")
                      (list "ello" "éllo" polars-null "b")
                      (list "lo" "lo" polars-null "ab")
                      (list "el" "él" polars-null "")
                      (list "" "" polars-null "")
                      (list "h" "héllo" polars-null "")))
  ;; string-to-temporal: parse Date/Datetime/Time; #:strict #f -> null on failure
  (define p
    (dataframe (list (series '("2024-01-02" "not-a-date" "2024-05-09 extra") #:name "date_s")
                     (series '("2024-01-02 03:04:05" "bad" "x") #:name "dt_s")
                     (series '("03:04:05.123456789" "bad" "x") #:name "time_s"))))
  (define out4
    (~> p (with-columns
            (alias (str->date "date_s" #:strict #f) "d_infer")
            (alias (str->date "date_s" #:format "%Y-%m-%d" #:strict #f #:exact #f) "d_embed")
            (alias (str->datetime "dt_s" #:format "%Y-%m-%d %H:%M:%S"
                                  #:unit 'milliseconds #:strict #f) "dt")
            (alias (str->time "time_s" #:format "%H:%M:%S%.f" #:strict #f) "tm"))))
  (check-equal? (ref (ref out4 #:columns "d_infer") 0) (date 2024 1 2))
  (check-equal? (ref (ref out4 #:columns "d_infer") 1) polars-null)
  (check-equal? (ref (ref out4 #:columns "d_embed") 2) (date 2024 5 9)) ; #:exact #f
  (check-equal? (ref (ref out4 #:columns "dt") 0) (datetime 2024 1 2 3 4 5))
  (check-equal? (ref (ref out4 #:columns "dt") 1) polars-null)
  (check-not-eq? (ref (ref out4 #:columns "tm") 0) polars-null)
  (check-equal? (ref (ref out4 #:columns "tm") 1) polars-null)

  (define slice-length-refused
    (regexp (string-append "^str-slice: contract violation\n  expected: "
                           (regexp-quote
                            (format "(or/c #f polars-null? Expr-ptr? ~s)"
                                    (contract-name nonnegative-int64/c))))))
  (for ([bad (list -1 "n" #t 1.5 (expt 2 63))])
    (check-exn slice-length-refused (lambda () (contracted:str-slice "s" 0 bad))))
  (check-equal? (sliced (contracted:str-slice "s" 1 polars-null))
                (sliced (contracted:str-slice "s" 1 #f)))
  (check-exn (regexp (string-append "^str-slice: contract violation\n  expected: "
                                    (regexp-quote (format "(or/c Expr-ptr? ~s)"
                                                          (contract-name int64/c)))))
             (lambda () (contracted:str-slice "s" #\a 2)))
  (define stamps
    (dataframe (list (series '("2021-03-27 03:00" "2021-10-31 02:30") #:name "clock")
                     (series '("2021-03-27T00:00:00+0100" "2021-03-29T00:00:00+0200")
                             #:name "offset"))))
  (define (parsed . exprs)
    (define d (apply select stamps exprs))
    (for/list ([name (in-list (column-names d))])
      (define s (ref d name))
      (cons (dtype s) (for/list ([x s]) x))))
  (check-equal? (parsed (str->datetime "offset" #:format "%Y-%m-%dT%H:%M:%S%z"))
                (list (list '(datetime microseconds "UTC")
                            (moment 2021 3 26 23 #:tz "UTC") (moment 2021 3 28 22 #:tz "UTC"))))
  (check-exn #rx"^select: .*no format and no time zone, but a time zone is part of"
             (lambda () (parsed (str->datetime "offset"))))
  (check-equal? (parsed (str->datetime "offset" #:time-zone "Asia/Tokyo" #:unit 'milliseconds))
                (list (list '(datetime milliseconds "Asia/Tokyo")
                            (moment 2021 3 27 8 #:tz "Asia/Tokyo")
                            (moment 2021 3 29 7 #:tz "Asia/Tokyo"))))
  (check-equal? (parsed (str->datetime "clock" #:time-zone "Europe/Brussels"
                                       #:ambiguous 'earliest))
                (list (list '(datetime microseconds "Europe/Brussels")
                            (moment 2021 3 27 3 #:tz "Europe/Brussels")
                            (moment 2021 10 31 2 30 #:tz "Europe/Brussels"
                                    #:resolve-offset resolve-offset/pre))))
  (check-equal? (list-ref (car (parsed (str->datetime "clock" #:time-zone "Europe/Brussels"
                                                       #:ambiguous 'null #:strict #f)))
                          2)
                polars-null)
  (check-exn #rx"^select: .*conversion from `str` to `datetime\\[μs, Europe/Brussels\\]`"
             (lambda () (parsed (str->datetime "clock" #:time-zone "Europe/Brussels"
                                               #:ambiguous 'null))))
  (check-exn #rx"^select: .*is ambiguous in time zone 'Europe/Brussels'\\. Please use #:amb"
             (lambda () (parsed (str->datetime "clock" #:time-zone "Europe/Brussels"))))
  (check-exn (regexp (string-append "^str->datetime: cannot parse into the time zone"
                                    " \"Mars/Base\": unable to parse time zone: 'Mars/Base'"))
             (lambda () (str->datetime "clock" #:time-zone "Mars/Base")))
  (check-equal? (parsed (str->datetime "offset" #:time-zone "Asia/Tokyo")
                        (str->datetime "clock" #:time-zone "Europe/Brussels" #:ambiguous 'latest))
                (list (list '(datetime microseconds "Asia/Tokyo")
                            (moment 2021 3 27 8 #:tz "Asia/Tokyo")
                            (moment 2021 3 29 7 #:tz "Asia/Tokyo"))
                      (list '(datetime microseconds "Europe/Brussels")
                            (moment 2021 3 27 3 #:tz "Europe/Brussels")
                            (moment 2021 10 31 2 30 #:tz "Europe/Brussels"
                                    #:resolve-offset resolve-offset/post))))
  (check-exn #rx"^str->datetime: cannot parse into the time zone \"Asia/Tokio\": .*'Asia/Tokyo'"
             (lambda () (str->datetime "offset" #:time-zone "Asia/Tokio")))
  (for ([bad (list (lambda () (contracted:str->datetime 5))
                   (lambda () (contracted:str->datetime "clock" #:time-zone ""))
                   (lambda () (contracted:str->datetime "clock" #:ambiguous 'first))
                   (lambda () (contracted:str->datetime "clock" #:unit 'seconds))
                   (lambda () (contracted:str->datetime "clock" #:strict 1)))])
    (check-exn exn:fail:contract:blame? bad))
  (define (strings-through xs make)
    (~> (dataframe (list (series xs #:name "s" #:dtype 'string)))
        (select (alias (make "s") "s"))
        (ref "s")
        series->list))
  (for ([row (in-list nul-expected)])
    (match-define (list op args ... expected) row)
    (define xs (match op ['lit '("x")] [_ (car args)]))
    (define make
      (match row
        [(list 'lit v _) (lambda (_) (lit v))]
        [(list 'fill-null _ v _) (lambda (c) (fill-null c v))]
        [(list 'strip-chars _ v _) (lambda (c) (str-strip-chars c v))]
        [(list 'replace-literal _ v by _) (lambda (c) (str-replace c v by #:literal #t))]
        [(list 'contains _ v _) (lambda (c) (str-contains c v))]
        [(list 'starts-with _ v _) (lambda (c) (str-starts-with c v))]
        [(list 'eq _ v _) (lambda (c) (p= (col c) v))]
        [(list 'ne _ v _) (lambda (c) (p!= (col c) v))]))
    (check-equal? (strings-through xs make) expected (format "~s" row)))
  (for ([row (in-list nul-expected)] #:when (memq (car row) '(eq ne)))
    (match row
      [(list 'eq xs v expected) (check-equal? (series->list (p= (series xs) v)) expected)]
      [(list 'ne xs v expected) (check-equal? (series->list (p!= (series xs) v)) expected)])))
