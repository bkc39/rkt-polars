#lang racket/base

(module+ test
  (require rackunit
           racket/file
           racket/runtime-path
           (only-in racket/dict in-dict)
           (only-in racket/format ~a)
           (only-in racket/list append* filter-map range remove-duplicates second)
           (only-in racket/match match match-define match-lambda)
           (only-in racket/sequence sequence->list)
           (only-in racket/string string-append* string-contains? string-join)
           (only-in polars/private/bulk in-series series->list)
           (only-in threading ~>)
           (only-in gregor date datetime moment)
           (prefix-in contracted: polars/private/generic/csv)
           (only-in (submod polars/private/generic/csv internal) read-csv scan-csv write-csv)
           (prefix-in raw: polars/private/csv)
           (only-in polars/private/generic/core
                    column-names dataframe dtype height lazyframe? null-count ref series shape)
           (only-in polars/private/generic/printing series->string)
           (only-in polars/private/generic/reshape collect head select slice tail)
           (only-in polars/tests/generic/test-fixtures
                    apply-keywords column contains-all? contract-violation-of dtypes-of frame
                    frame=? gzip-file keyword-of keyword-rejected? message-of nul-expected
                    polars-null scratch-file)
           (only-in (submod polars/tests/generic/test-fixtures test)
                    check-nul-names-round-trip check-readers-agree eager-reader glob-reader
                    outcome-difference scan-reader [eager-and-scan eager-and-scan*]))

  (define-runtime-path data-dir "../../scribblings/data")
  (define eager-and-scan (eager-and-scan* read-csv scan-csv))
  (define flights (build-path data-dir "flights.tsv"))
  (define scratch (make-temporary-directory "rkt-polars-io-~a"))
  (for ([sub '("globbed" "ordered" "mixed" "literal" "dirmix")])
    (make-directory (build-path scratch sub)))

  (check-equal? (remq '#:columns raw:read-keywords) raw:scan-keywords)
  (check-equal? (length raw:scan-keywords) 24)
  (define csv-readers
    (list contracted:read-csv contracted:scan-csv raw:dataframe-read-csv raw:lazyframe-scan-csv))
  (for ([reader (in-list csv-readers)]
        [keywords (list raw:read-keywords raw:scan-keywords raw:read-keywords raw:scan-keywords)])
    (define-values (required accepted) (procedure-keywords reader))
    (check-equal? required '())
    (check-equal? accepted keywords))

  (define missing (build-path scratch "no-such.csv"))
  (define bad-keywords
    `((#:separator . "\t") (#:separator . 9) (#:separator . #\é) (#:separator . #\newline)
      (#:quote-char . "'") (#:comment-prefix . "") (#:null-values . NA)
      (#:null-values . ("NA" 1)) (#:infer-schema-length . -1) (#:infer-schema-length . 1.5)
      (#:null-values . (("a" . "NA") ("a" . "-"))) (#:null-values . (("a" . NA)))
      (#:null-values . ,(hash "a" "NA"))
      (#:schema-overrides . ((a . int32))) (#:schema-overrides . (("a" . bogus)))
      (#:schema-overrides . (("a" . (duration microseconds))))
      (#:schema-overrides . (("a" . null)))
      (#:schema-overrides . (("a" . (enum x y))))
      (#:schema-overrides . (("a" . (datetime microseconds "UTC"))))
      (#:schema-overrides . (("a" . int32) ("a" . f64)))
      (#:schema-overrides . ,(hash "a" 'int32)) (#:encoding . latin1) (#:glob . 1)
      (#:eol-char . "\n") (#:eol-char . #\é) (#:eol-char . 10)
      (#:new-columns . ("x" "x")) (#:new-columns . "x") (#:new-columns . (x))
      (#:row-index-name . i) (#:row-index-offset . -1) (#:row-index-offset . ,(expt 2 32))
      (#:skip-lines . -1) (#:skip-rows-after-header . 1.5) (#:infer-schema . 0)
      (#:raise-if-empty . 1) (#:missing-utf8-is-empty-string . "yes")
      (#:truncate-ragged-lines . 1) (#:decimal-comma . 1)))
  (define bad-together
    '(((#:quote-char . #\,))
      ((#:separator . #\;) (#:quote-char . #\;))
      ((#:separator . #\"))
      ((#:eol-char . #\,))
      ((#:eol-char . #\"))
      ((#:separator . #\;) (#:eol-char . #\;))
      ((#:quote-char . #\') (#:eol-char . #\'))
      ((#:skip-rows . 1) (#:skip-lines . 1))))
  (define bad-columns
    '((#:columns . ("a" "a")) (#:columns . (0 0)) (#:columns . ("a" 0)) (#:columns . (-1))
      (#:columns . "a")))
  (for ([reader (in-list csv-readers)]
        [name '(read-csv scan-csv dataframe-read-csv lazyframe-scan-csv)])
    (check-exn (contract-violation-of name) (lambda () (reader 'sym)))
    (for ([kvs (in-list (append (map list bad-keywords) bad-together))])
      (check-exn (contract-violation-of name)
                 (lambda () (apply-keywords reader kvs missing))
                 (format "~a ~s" name kvs))))
  (for ([reader (list contracted:read-csv raw:dataframe-read-csv)]
        [name '(read-csv dataframe-read-csv)]
        #:when #t
        [kv (in-list bad-columns)])
    (check-exn (contract-violation-of name)
               (lambda () (apply-keywords reader (list kv) missing))
               (format "~a ~s" name kv)))
  (for ([reader (list contracted:scan-csv raw:lazyframe-scan-csv)])
    (check-exn (keyword-rejected? '#:columns) (lambda () (reader missing #:columns '("a")))))
  (check-exn #rx"eol-char must differ from the separator and quote-char"
             (lambda () (contracted:read-csv missing #:separator #\; #:eol-char #\;)))
  (check-exn #rx"only one of skip-rows and skip-lines may be set"
             (lambda () (contracted:scan-csv missing #:skip-rows 1 #:skip-lines 2)))
  (check-exn (contract-violation-of 'write-csv) (lambda () (contracted:write-csv 5 "x")))

  (define flights-na (read-csv flights #:separator #\tab #:null-values "NA"))
  (check-equal? (shape flights-na) '(102 19))
  (check-equal?
   (for/list ([name (column-names flights-na)])
     (define s (ref flights-na #:columns name))
     (list name (dtype s) (null-count s)))
   '(("year" int64 0) ("month" int64 0) ("day" int64 0) ("dep_time" int64 1)
     ("sched_dep_time" int64 0) ("dep_delay" int64 1) ("arr_time" int64 1)
     ("sched_arr_time" int64 0) ("arr_delay" int64 2) ("carrier" string 0)
     ("flight" int64 0) ("tailnum" string 0) ("origin" string 0) ("dest" string 0)
     ("air_time" int64 2) ("distance" int64 0) ("hour" int64 0) ("minute" int64 0)
     ("time_hour" string 0)))
  (define (tail-of df name) (list-tail (column df name) 99))
  (check-equal? (tail-of flights-na "dep_delay") (list -7 -5 polars-null))
  (check-equal? (tail-of flights-na "arr_delay") (list -4 polars-null polars-null))

  (define unparsed (message-of (lambda () (read-csv flights #:separator #\tab))))
  (check-regexp-match
   #rx"^read-csv: failed to read csv from [^:]*flights.tsv: could not parse `NA` as dtype `i64` at column 'arr_delay' \\(column number 9\\)"
   unparsed)
  (check-true (contains-all? unparsed '("#:infer-schema-length 10000" "#:schema-overrides"
                                        "#:ignore-errors to #t" "`NA` to #:null-values")))
  (check-false (regexp-match? #rx"null_values|ignore_errors|infer_schema_length|schema_overrides" unparsed))
  (check-true (frame=? flights-na (read-csv flights #:separator #\tab #:null-values '("NA"))))
  (check-true (frame=? (read-csv flights #:separator #\tab #:infer-schema-length 0)
                       (read-csv flights #:separator #\tab #:infer-schema-length 0
                                 #:null-values '())))
  (check-true (frame=? flights-na (read-csv flights #:separator #\tab #:ignore-errors #t)))
  (check-true (frame=? flights-na (read-csv flights #:separator #\tab #:null-values "NA"
                                            #:quote-char #f)))
  (define primed (scratch-file scratch "primed.csv" "a;b\n'x;y';1\nz;2\n"))
  (check-equal? (column (read-csv primed #:separator #\; #:quote-char #\') "a") '("x;y" "z"))

  (check-equal? (remove-duplicates
                 (map second (dtypes-of (read-csv flights #:separator #\tab
                                                  #:infer-schema-length 0))))
                '(string))
  (define all-rows (read-csv flights #:separator #\tab #:infer-schema-length #f))
  (check-equal? (filter-map (match-lambda [(list name 'string) name] [_ #f])
                            (dtypes-of all-rows))
                '("dep_time" "dep_delay" "arr_time" "arr_delay" "carrier" "tailnum"
                  "origin" "dest" "air_time" "time_hour"))

  (define overridden
    (read-csv flights #:separator #\tab #:null-values "NA"
              #:schema-overrides '(("dep_delay" . f64) ("flight" . int32)
                                   ("time_hour" . (datetime milliseconds)))))
  (check-equal? (dtype (ref overridden #:columns "dep_delay")) 'float64)
  (check-equal? (dtype (ref overridden #:columns "flight")) 'int32)
  (check-equal? (dtype (ref overridden #:columns "time_hour")) '(datetime milliseconds #f))
  (check-equal? (tail-of overridden "dep_delay") (list -7.0 -5.0 polars-null))
  (check-true
   (frame=? (read-csv flights #:separator #\tab #:null-values "NA"
                      #:schema-overrides '(("flight" . i32) ("time_hour" . datetime)))
            (read-csv flights #:separator #\tab #:null-values "NA"
                      #:schema-overrides '(("time_hour" . (datetime microseconds))
                                           ("flight" . int32)))))

  (define ab (scratch-file scratch "ab.csv" "a,b\n1,2\n"))
  (define absent '(("a" . int64) ("zzz" . float32)))
  (check-exn
   #rx"^read-csv: failed to read csv from [^:]*ab.csv: schema overrides name columns not in the file: \"zzz\"$"
   (lambda () (read-csv ab #:schema-overrides absent)))
  (check-exn
   #rx"^scan-csv: failed to scan [^:]*ab.csv: schema overrides name columns not in the file: \"zzz\"$"
   (lambda () (scan-csv ab #:schema-overrides absent)))

  (define typed
    (scratch-file
     scratch
     "typed.csv"
     (string-append
      "i8,i16,i32,i64,u8,u16,u32,u64,f32,f64,b,s,d,dt,dtms\n"
      "1,2,3,4,5,6,7,8,1.5,2.5,true,x,2020-01-02,2020-01-02 03:04:05,2020-01-02 03:04:05\n")))
  (define typed-frame
    (read-csv typed
              #:schema-overrides
              '(("i8" . i8) ("i16" . i16) ("i32" . i32) ("i64" . i64) ("u8" . u8)
                ("u16" . u16) ("u32" . u32) ("u64" . u64) ("f32" . f32) ("f64" . f64)
                ("b" . bool) ("s" . str) ("d" . date) ("dt" . datetime)
                ("dtms" . (datetime milliseconds)))))
  (check-equal? (map second (dtypes-of typed-frame))
                '(int8 int16 int32 int64 uint8 uint16 uint32 uint64 float32 float64
                  boolean string date (datetime microseconds #f)
                  (datetime milliseconds #f)))
  (check-equal? (column typed-frame "dt") (list (datetime 2020 1 2 3 4 5)))

  (define dated (scratch-file scratch "dated.csv" "d,t,ts\n2020-01-02,05:00:00,2013-01-01 05:00:00\n"))
  (define parsed (read-csv dated #:try-parse-dates #t))
  (check-equal? (dtypes-of parsed)
                '(("d" date) ("t" time) ("ts" (datetime microseconds #f))))
  (check-equal? (column parsed "ts") (list (datetime 2013 1 1 5)))
  (define clocked (scratch-file scratch "clocked.csv" "t\n05:00:00\n06:30:15\n"))
  (define clocked-frame (read-csv clocked #:schema-overrides '(("t" . time))))
  (check-equal? (dtypes-of clocked-frame) '(("t" time)))
  (check-true (frame=? clocked-frame (read-csv clocked #:try-parse-dates #t)))
  (check-equal? (~> (read-csv flights #:separator #\tab #:null-values "NA" #:try-parse-dates #t)
                    (ref #:columns "time_hour")
                    dtype)
                '(datetime microseconds #f))
  (define apple (read-csv (build-path data-dir "apple_stock.csv") #:try-parse-dates #t))
  (check-equal? (shape apple) '(100 2))
  (check-equal? (map second (dtypes-of apple)) '(date float64))
  (check-equal? (ref (ref apple #:columns "Date") 0) (date 1981 2 23))
  (check-equal? (ref (ref apple #:columns "Close") 99) 522.06)
  (check-equal? (map second (dtypes-of (read-csv (build-path data-dir "apple_stock.csv"))))
                '(string float64))

  (define quoted (scratch-file scratch "quoted.csv" "a,b\n\"1,5\",x\n\"2\",y\n"))
  (check-equal? (column (read-csv quoted) "a") '("1,5" "2"))
  (check-exn #rx"found more fields than defined" (lambda () (read-csv quoted #:quote-char #f)))
  (define commented (scratch-file scratch "commented.csv" "# note\na,b\n1,2\n# mid\n3,4\n"))
  (check-equal? (shape (read-csv commented #:comment-prefix "#")) '(2 2))
  (check-equal? (column (read-csv commented #:comment-prefix "#") "a") '(1 3))
  (define slashed (scratch-file scratch "slashed.csv" "x\n//skip\n1\n"))
  (check-equal? (column (read-csv slashed #:comment-prefix "//") "x") '(1))
  (define (csv-lines . lines) (string-append* (for/list ([line (in-list lines)]) (~a line "\n"))))
  (define commented-late-na
    (scratch-file
     scratch "commented-late-na.csv"
     (apply csv-lines
            "id,delay"
            (append (append* (for/list ([i (in-range 0 20000 10)])
                               (cons (format "# before row ~a" i)
                                     (for/list ([j (in-range i (+ i 10))])
                                       (format "~a,~a" j (modulo j 7))))))
                    '("20000,NA")))))
  (check-equal? (column (read-csv commented-late-na #:n-rows 1 #:comment-prefix "#") "id") '(0))
  (check-equal? (column (~> (scan-csv commented-late-na #:comment-prefix "#") (head 1) collect) "id")
                '(0))
  (define stray-quote-resynchronised
    (scratch-file
     scratch "stray-quote.csv"
     (apply csv-lines
            "a,b"
            (append (for/list ([i (in-range 8000)]) (format "r~a,v~a" i (modulo i 7)))
                    (list "p1,a\"b" "p2,\"x" (~a (make-string 40000 #\y) "\"") "# \"")
                    (for/list ([i (in-range 20000)]) (format "s~a,v~a" i (modulo i 7)))))))
  (define stray-full (collect (scan-csv stray-quote-resynchronised #:comment-prefix "#")))
  (check-equal? (height stray-full) 28002)
  (check-true (frame=? (~> (scan-csv stray-quote-resynchronised #:comment-prefix "#") (slice 8001 2) collect)
                       (slice stray-full 8001 2)))
  (check-true (frame=? (~> (scan-csv stray-quote-resynchronised #:comment-prefix "#") (tail 20002) collect)
                       (tail stray-full 20002)))
  (define stray-ignored (scratch-file scratch "stray-ignored.csv" "a,b\n1,5\"\n2,6\n# note\n3,7\n"))
  (check-equal? (column (read-csv stray-ignored #:comment-prefix "#" #:ignore-errors #t #:n-rows 2) "b")
                '("5\"" "6"))
  (define unended
    (scratch-file scratch "unended.csv"
                  (~a (apply csv-lines "a" (for/list ([i (in-range 20000)]) (~a "v" i))) "x#y")))
  (check-equal? (height (read-csv unended #:comment-prefix "#" #:ignore-errors #t #:n-rows 20001))
                20001)
  (for* ([prefix (in-list '("#" "//"))]
         [last (in-list (list (~a prefix " the end") (~a "x" prefix "y")))])
    (define rows (for/list ([i (in-range 20000)]) (~a "v" i)))
    (define (ending name suffix)
      (scratch-file scratch name (~a (apply csv-lines "a" rows) last suffix)))
    (define expected (collect (scan-csv (ending "ended.csv" "\n") #:comment-prefix prefix)))
    (define path (ending "unended-last.csv" ""))
    (define label (format "a file ending in ~s" last))
    (check-true (frame=? (read-csv path #:comment-prefix prefix) expected) label)
    (check-true (frame=? (collect (scan-csv path #:comment-prefix prefix)) expected) label)
    (check-true (frame=? (~> (scan-csv path #:comment-prefix prefix) (tail 5) collect)
                         (tail expected 5))
                label))
  (check-equal? (column (read-csv (scratch-file scratch "one-row.csv" "a\nx#y") #:comment-prefix "#")
                        "a")
                '("x#y")
                "routing guard: a commented one-row file reads by scan as it read eagerly")
  (define mkfifo (find-executable-path "mkfifo"))
  (define sh (find-executable-path "sh"))
  (define (spawn . arguments)
    (define-values (process out in err) (apply subprocess #f #f #f arguments))
    (close-input-port out)
    (close-output-port in)
    (close-input-port err)
    process)
  (define piped (scratch-file scratch "piped.csv" "a,b\n1,2\n# c\n3,4\n"))
  (define (read-through-a-fifo name read [source piped])
    (define fifo (build-path scratch name))
    (subprocess-wait (spawn mkfifo (path->string fifo)))
    (define writer
      (spawn sh "-c" "cat \"$1\" > \"$2\"" "sh" (path->string source) (path->string fifo)))
    (define got (with-handlers ([exn:fail? exn-message]) (read fifo)))
    (subprocess-kill writer #t)
    got)
  (if (and mkfifo sh)
      (for ([read (list read-csv
                        (lambda (path) (read-csv path #:comment-prefix "#"))
                        (lambda (path) (read-csv path #:n-rows 2))
                        (lambda (path) (read-csv path #:comment-prefix "#" #:n-rows 1)))]
            [rows (in-list '(3 2 2 1))]
            [i (in-naturals)])
        (define expected (read piped))
        (define got (read-through-a-fifo (format "fifo-~a.csv" i) read))
        (check-equal? (height expected) rows)
        ;; printing a frame here fails the next file write in the nix sandbox (errno 17)
        (check-true (and (not (string? got)) (frame=? got expected))
                    (format "fifo ~a: ~a" i (if (string? got) got "a frame"))))
      (displayln "skipped: the named-pipe reads need mkfifo and sh"))
  (define stray-to-the-end
    (scratch-file scratch "stray-to-the-end.csv"
                  (apply csv-lines "a,b" "1,5\"" (for/list ([i (in-range 1000)]) (~a i "," i)))))
  (for ([read (list collect (lambda (lf) (collect (tail lf 5))))])
    (check-exn #rx"CSV malformed"
               (lambda () (read (scan-csv stray-to-the-end #:comment-prefix "#")))))
  (define quoted-to-the-end
    (scratch-file scratch "quoted-to-the-end.csv"
                  (apply csv-lines "a,b" "\"1,5" (for/list ([i (in-range 2000)]) (~a i "," i)))))
  (for ([read (list collect (lambda (lf) (collect (tail lf 2))))])
    (define message
      (message-of (lambda () (read (select (scan-csv quoted-to-the-end #:comment-prefix "#") "b")))))
    (check-regexp-match #rx"CSV malformed" message)
    (check-false (string-contains? message "1999,1999")))
  (define stray-plain (scratch-file scratch "stray-plain.csv" "a,b\n1,5\"\n2,6\n3,7\n"))
  (for ([scan (list (lambda () (scan-csv stray-ignored #:comment-prefix "#" #:ignore-errors #t))
                    (lambda () (scan-csv stray-plain #:ignore-errors #t)))])
    (define full (collect (scan)))
    (check-equal? (height full) 3)
    (for ([n (in-range 1 5)])
      (check-true (frame=? (collect (tail (scan) n)) (tail full n)))
      (check-true (frame=? (collect (head (scan) n)) (head full n)))))
  (check-equal? (column (~> (scan-csv unended #:comment-prefix "#" #:ignore-errors #t) (tail 1) collect)
                        "a")
                '("x#y"))
  (define (ten-rows-then from rest)
    (~a (apply csv-lines "a,b" (for/list ([i (in-range from (+ from 10))]) (~a i "," i))) rest))
  (define (two-file-glob name first)
    (make-directory (build-path scratch name))
    (scratch-file scratch (build-path name "a0.csv") first)
    (scratch-file scratch (build-path name "a1.csv") (ten-rows-then 100 ""))
    (build-path scratch name "a*.csv"))
  (define malformed-first
    (two-file-glob "malformed-first" (ten-rows-then 10 "1,5\"\n2,6\n# note\n3,7\n")))
  (for ([n (in-list '(2 10 11))])
    (check-exn #rx"CSV malformed"
               (lambda () (collect (tail (scan-csv malformed-first #:comment-prefix "#") n)))))
  (define well-formed
    (two-file-glob "well-formed" (ten-rows-then 10 "1,5\n2,6\n# note\n3,7\n")))
  (define (indexed-glob)
    (scan-csv well-formed #:comment-prefix "#" #:row-index-name "i" #:row-index-offset 5))
  (check-equal? (column (collect (tail (indexed-glob) 2)) "i") '(26 27))
  (for ([n (in-list '(2 10 11 13 14 23 30))])
    (check-true (frame=? (collect (tail (indexed-glob) n)) (tail (collect (indexed-glob)) n))))
  (make-directory (build-path scratch "small-then-large"))
  (for ([file (in-list '("f0.csv" "f1.csv" "f2.csv" "f3.csv"))]
        [rows (in-list (list (range 0 10) (range 10 20) (range 20 30) (range 30 1030)))])
    (scratch-file scratch
                  (build-path "small-then-large" file)
                  (apply csv-lines "a,b" (for/list ([i (in-list rows)]) (~a i "," i)))))
  (define small-then-large (build-path scratch "small-then-large" "f*.csv"))
  (for ([scan (list (lambda () (scan-csv small-then-large #:comment-prefix "#"))
                    (lambda () (scan-csv small-then-large #:ignore-errors #t)))])
    (define cut (collect (slice (scan) -500 5)))
    (check-equal? (column cut "a") '(530 531 532 533 534))
    (check-true (frame=? cut (slice (collect (scan)) -500 5))))

  (define latin (scratch-file scratch "latin.csv" #"s\ncaf\351\n"))
  (check-exn #rx"invalid utf-8" (lambda () (read-csv latin)))
  (check-equal? (column (read-csv latin #:encoding 'utf8-lossy) "s")
                (list (string #\c #\a #\f (integer->char #xFFFD))))

  (define unclosed-readers
    (list* (cons 'glob (glob-reader read-csv))
           (cons 'gzip (lambda (path kvs)
                         (define gz (path-add-extension path #".gz"))
                         (gzip-file path gz)
                         (apply-keywords read-csv kvs gz)))
           eager-and-scan))
  (define unclosed-keywords
    '(() ((#:n-rows . 10)) ((#:comment-prefix . "#")) ((#:null-values . ("x")))))
  (for* ([spec (in-list `((i64 "2" 2 "\"" "\"12" "\"12\"\"" "\"\"\"" "\"1\"2\"")
                          (f64 "2.5" 2.5 "\"" "\"12")
                          (bool "true" #t "\"" "\"t") (date "2020-01-01" ,(date 2020 1 1) "\"2020-01-022")))]
         [(last i) (in-indexed (cdddr spec))])
    (match-define (list dt text value _ ...) spec)
    (define path (scratch-file scratch (format "unclosed-~a-~a.csv" dt i)
                               (format "a,b\n1,~a\n3,~a" text last)))
    (define overrides `((#:schema-overrides . (("b" . ,dt)))))
    (define cause (format "could not parse `~a` as dtype `~a` at column 'b' (column number 2)" last dt))
    (for* ([kvs (in-list unclosed-keywords)]
           [(kind read) (in-dict unclosed-readers)])
      (define label (format "~a ~s ~a ~s" dt last kind kvs))
      (define message (message-of (lambda () (read path (append overrides kvs)))))
      (check-regexp-match
       (regexp (string-append "^(read-csv: failed to read csv from [^:]*: |collect: )" (regexp-quote cause)))
       message
       label)
      (check-true (string-contains? message (format "Field `~a` is not properly escaped." last)) label)
      (check-equal? (column (read path (list* '(#:ignore-errors . #t) (append overrides kvs))) "b")
                    (list value polars-null)
                    label)))
  (define closed (scratch-file scratch "closed.csv" "a,b,c\n1,\"\",\"true\"\n\"2\",\"34\",\"\""))
  (for* ([kvs (in-list unclosed-keywords)]
         [ignore (in-list '(#f #t))]
         [(kind read) (in-dict unclosed-readers)])
    (define df (read closed `((#:ignore-errors . ,ignore)
                              (#:schema-overrides . (("a" . i64) ("b" . i64) ("c" . bool)))
                              ,@kvs)))
    (check-equal? (map (lambda (name) (column df name)) '("a" "b" "c"))
                  (list '(1 2) (list polars-null 34) (list #t polars-null))
                  (format "~a ~s" kind kvs)))
  (define (refuses? thunk cause)
    (define message (message-of thunk))
    (and message (string-contains? message cause)))
  (define (check-unclosed-refused path kvs cause label)
    (for* ([ignore (in-list '(#f #t))]
           [(kind read) (in-dict unclosed-readers)])
      (check-true (refuses? (lambda () (read path `((#:ignore-errors . ,ignore) ,@kvs))) cause)
                  (format "~a ~a ~a" label kind ignore))))
  (for* ([(field i) (in-indexed '("\"ab" "\"ab\"\"" "\"\"\"" "\"a\"b\""))]
         [dt (in-list '(string categorical))])
    (define path (scratch-file scratch (format "unclosed-~a-~a.csv" dt i)
                               (string-append "a\nx\n" field)))
    (for ([kvs (in-list unclosed-keywords)])
      (check-unclosed-refused path `((#:schema-overrides . (("a" . ,dt))) ,@kvs)
                              (format "Field `~a` is not properly escaped." field)
                              (format "~a ~s ~s" dt field kvs))))
  (check-unclosed-refused (scratch-file scratch "unclosed-time.csv" "a\n10:00:00\n\"10:00:001")
                          '((#:schema-overrides . (("a" . time))))
                          "could not parse `\"10:00:001` as dtype `str` at column 'a'"
                          "time")
  (check-unclosed-refused (scratch-file scratch "unclosed-header.csv" "x,\"ab")
                          '()
                          "Column name `\"ab` is not properly escaped."
                          "header")
  (for ([(spec i) (in-indexed '(("\"\"\"" "\"") ("\"NA" "N")))])
    (match-define (list field marker) spec)
    (define path (scratch-file scratch (format "unclosed-null-~a.csv" i)
                               (string-append "a\n1\n" field)))
    (define kvs `((#:null-values . (,marker)) (#:schema-overrides . (("a" . i64)))))
    (for ([(kind read) (in-dict unclosed-readers)])
      (define label (format "~s ~a" field kind))
      (check-true (refuses? (lambda () (read path kvs))
                            (format "Field `~a` is not properly escaped." field))
                  label)
      (check-equal? (column (read path (cons '(#:ignore-errors . #t) kvs)) "a")
                    (list 1 polars-null)
                    label)))
  (define single-quoted '((#:quote-char . #\') (#:schema-overrides . (("a" . i64)))))
  (define single-quoted-string '((#:quote-char . #\') (#:schema-overrides . (("a" . string)))))
  (define odd-single (scratch-file scratch "odd-single.csv" "a\n1\n'12''"))
  (define inner-single (scratch-file scratch "inner-single.csv" "a\nx\n'a\"b'"))
  (for ([(kind read) (in-dict unclosed-readers)])
    (check-true (refuses? (lambda () (read (scratch-file scratch "open-single.csv" "a\n1\n'12")
                                           single-quoted))
                          "Field `'12` is not properly escaped.")
                (format "'12 ~a" kind))
    (check-equal? (column (read (scratch-file scratch "closed-single.csv" "a\n1\n'12'") single-quoted)
                          "a")
                  '(1 12)
                  (format "'12' ~a" kind))
    (check-true (refuses? (lambda () (read odd-single single-quoted))
                          "Field `'12''` is not properly escaped.")
                (format "'12'' ~a" kind))
    (check-equal? (column (read inner-single single-quoted-string) "a")
                  '("x" "a\"b")
                  (format "'a\"b' ~a" kind)))
  (check-unclosed-refused odd-single single-quoted-string
                          "Field `'12''` is not properly escaped."
                          "'12'' string")
  (define trailing (scratch-file scratch "closed-trailing.csv" "a,b\n\"ab\"c,1\n"))
  (for* ([ignore (in-list '(#f #t))]
         [(kind read) (in-dict unclosed-readers)])
    (check-equal? (column (read trailing `((#:ignore-errors . ,ignore)
                                           (#:schema-overrides . (("a" . categorical)))))
                          "a")
                  '(ab)
                  (format "\"ab\"c ~a ~a" kind ignore)))
  (check-unclosed-refused trailing '((#:schema-overrides . (("a" . string))))
                          "Field `\"ab\"c` is not properly escaped."
                          "\"ab\"c string")
  (for ([(marker i) (in-indexed '("\"NA" "\""))])
    (check-unclosed-refused (scratch-file scratch (format "unclosed-marker-~a.csv" i)
                                          (string-append "a,b\n1," marker))
                            `((#:null-values . (,marker)) (#:schema-overrides . (("b" . string))))
                            (format "Field `~a` is not properly escaped." marker)
                            (format "marker ~s" marker)))
  (define hint "You might want to try:")
  (define markerless-keywords '(() ((#:n-rows . 10)) ((#:comment-prefix . "#"))))
  (define unclosed-hintless (scratch-file scratch "unclosed-hintless.csv" "a,b\n1,\"NA"))
  (define bad-value (scratch-file scratch "bad-value.csv" "a\nx"))
  (for* ([kvs (in-list markerless-keywords)]
         [(kind read) (in-dict unclosed-readers)])
    (define label (format "~a ~s" kind kvs))
    (define unclosed-message
      (message-of (lambda () (read unclosed-hintless `((#:schema-overrides . (("b" . i64))) ,@kvs)))))
    (check-true (string-contains? unclosed-message "Field `\"NA` is not properly escaped.") label)
    (check-false (string-contains? unclosed-message hint) label)
    (define bad-message
      (message-of (lambda () (read bad-value `((#:schema-overrides . (("a" . i64))) ,@kvs)))))
    (check-true (string-contains? bad-message hint) label)
    (check-true (string-contains? bad-message "adding `x` to #:null-values") label))
  (define closed-markers
    (for/list ([(spec i) (in-indexed '(("a\n\"NA\"\n1\n" "NA") ("a\n\"N\"\"A\"\n1\n" "N\"\"A")))])
      (match-define (list text marker) spec)
      (list (scratch-file scratch (format "closed-marker-~a.csv" i) text) text marker)))
  (for* ([spec (in-list closed-markers)]
         [overrides (in-list '(() ((#:schema-overrides . (("a" . i64))))))]
         [(kind read) (in-dict unclosed-readers)]
         [kvs (in-list markerless-keywords)])
    (match-define (list path text marker) spec)
    (define df (read path `((#:null-values . (,marker)) ,@overrides ,@kvs)))
    (check-equal? (list (dtype (ref df "a")) (column df "a"))
                  (list 'int64 (list polars-null 1))
                  (format "~s ~a ~s ~s" text kind overrides kvs)))
  (define projected-350
    (read-csv (scratch-file scratch "projected-unclosed-350.csv" "b,a\n1,\"x\n2,y\n3,z\n")
              #:columns '("b")))
  (check-equal? (list (column-names projected-350) (column projected-350 "b"))
                '(("b") (1))
                "#350's gap: an eager read of one file that projects an unclosed field away returns its row")

  (define big (build-path scratch "big.csv"))
  (display-lines-to-file (cons "x" (range 100000)) big)
  (define first-half (read-csv big #:n-rows 50000))
  (check-equal? (height first-half) 50000)
  (check-equal? (ref (ref first-half #:columns "x") 49999) 49999)
  (define skipped (read-csv big #:skip-rows 3 #:has-header #f))
  (check-equal? (height skipped) 99998)
  (check-equal? (ref (ref skipped #:columns "column_1") 0) 2)

  (define gappy (build-path scratch "gappy.csv"))
  (display-lines-to-file (cons "x,s" (for/list ([i (in-range 200000)])
                                       (if (zero? (modulo i 7)) "," (format "~a,s~a" i i))))
                         gappy)
  (define gappy-frame (read-csv gappy))
  (for ([name '("x" "s")])
    (define s (ref gappy-frame #:columns name))
    (define expected (for/list ([i (in-range (height gappy-frame))]) (ref s i)))
    (check-equal? (series->list s) expected name)
    (check-equal? (sequence->list (in-series s #:chunk-rows 4093)) expected name))

  (define gone (build-path scratch "gone.csv"))
  (check-exn #rx"^collect: " (lambda () (collect (scan-csv gone))))
  (check-exn #rx"^scan-csv: failed to scan "
             (lambda () (scan-csv gone #:schema-overrides '(("a" . int32)))))

  (for ([name '("b" "c" "a")] [value '(2 3 1)])
    (scratch-file scratch (format "globbed/~a.csv" name) (format "x\n~a\n" value)))
  (void (scratch-file scratch "globbed/skip.txt" "x\n99\n"))
  (define csv-pattern (build-path scratch "globbed" "*.csv"))
  (check-equal? (column (read-csv csv-pattern) "x") '(1 2 3))
  (check-equal? (~> csv-pattern scan-csv collect (column "x")) '(1 2 3))

  (for ([name '("p0" "p1" "p2")] [rows '(("5" "6") ("1" "2") ("3" "4"))])
    (scratch-file scratch (format "ordered/~a.csv" name)
                  (string-join (cons "x" rows) "\n" #:after-last "\n")))
  (define ordered (build-path scratch "ordered" "p*.csv"))
  (check-equal? (column (read-csv ordered) "x") '(5 6 1 2 3 4))
  (check-equal? (column (read-csv ordered #:n-rows 3) "x") '(5 6 1))
  (check-equal? (column (read-csv ordered #:skip-rows 1 #:has-header #f) "column_1")
                '(5 6 1 2 3 4))

  (void (scratch-file scratch "mixed/a.csv" "x\n1\n")
        (scratch-file scratch "mixed/b.csv" "y\n2\n"))
  (check-exn #rx"^read-csv: " (lambda () (read-csv (build-path scratch "mixed" "*.csv"))))

  (define nothing (build-path scratch "globbed" "*.none"))
  (check-pred lazyframe? (scan-csv nothing))
  (for ([thunk (list (lambda () (read-csv nothing))
                     (lambda () (collect (scan-csv nothing))))])
    (check-exn #rx": no files match the pattern$" thunk))

  (void (scratch-file scratch "literal/a1.csv" "x\n1\n"))
  (define bracketed (scratch-file scratch "literal/a[1].csv" "x\n2\n"))
  (check-equal? (column (read-csv bracketed) "x") '(1))
  (check-equal? (column (read-csv bracketed #:glob #f) "x") '(2))

  (parameterize ([current-directory (build-path scratch "literal")])
    (check-equal? (column (read-csv "a1.csv") "x") '(1)))

  (define bracketed-dir (build-path scratch "proj[1]"))
  (for ([dir (list bracketed-dir (build-path scratch "proj1"))] [value '("7" "1")])
    (make-directory* dir)
    (display-lines-to-file (list "x" value) (build-path dir "data.csv") #:exists 'replace))
  (parameterize ([current-directory bracketed-dir])
    (check-equal? (column (read-csv "data.csv") "x") '(7))
    (check-equal? (column (read-csv "data.csv" #:glob #f) "x") '(7))
    (check-equal? (column (read-csv "*.csv") "x") '(7))
    (check-equal? (~> "data.csv" scan-csv collect (column "x")) '(7))
    (write-csv (read-csv "data.csv") "copy.csv")
    (check-true (file-exists? (build-path bracketed-dir "copy.csv")))
    (make-directory* "sub")
    (write-csv (read-csv "data.csv") "sub/a.csv")
    (check-equal? (~> "sub/*.csv" read-csv (column "x")) '(7))
    (check-equal? (~> (scan-csv "sub" #:glob #f) collect (column "x")) '(7))
    (check-exn #rx"cannot open file: it is a directory" (lambda () (read-csv "sub")))
    (check-exn #rx"cannot open file: [Nn]o such file" (lambda () (read-csv "missing.csv"))))
  (check-equal? (object-name read-csv) 'read-csv)
  (check-exn #rx"^read-csv: " (lambda () (contracted:read-csv "x.csv" "extra")))
  (check-exn #rx"quote-char must differ from the separator"
             (lambda () (contracted:read-csv missing #:quote-char #\,)))

  (void (scratch-file scratch "dirmix/a.csv" "x\n1\n")
        (scratch-file scratch "dirmix/notes.txt" "x\n99\n"))
  (check-exn #rx"^read-csv: failed to read csv from [^:]*dirmix: cannot open file: it is a directory"
             (lambda () (read-csv (build-path scratch "dirmix") #:glob #f)))

  (define every-reader
    (list (cons 'eager (eager-reader read-csv)) (cons 'glob (glob-reader read-csv))
          (cons 'scan (scan-reader scan-csv collect))))
  (define semi (scratch-file scratch "semi-opts.txt" "# note\na;b\n'x;y';1\n# mid\nz;2\n"))
  (define reader-files
    (list (cons flights #\tab) (cons quoted #\,) (cons commented #\,) (cons slashed #\,)
          (cons dated #\,) (cons typed #\,) (cons latin #\,) (cons semi #\;)))
  (define reader-options
    '(() ((#:has-header . #f)) ((#:quote-char . #\')) ((#:quote-char . #f))
      ((#:comment-prefix . "#")) ((#:comment-prefix . "//"))
      ((#:skip-rows . 1)) ((#:n-rows . 0)) ((#:n-rows . 1)) ((#:skip-rows . 1) (#:n-rows . 2))
      ((#:null-values . "NA")) ((#:null-values . ("NA" "-")))
      ((#:infer-schema-length . 0)) ((#:infer-schema-length . 1)) ((#:infer-schema-length . #f))
      ((#:schema-overrides . (("dep_delay" . f64))))
      ((#:schema-overrides . (("d" . date) ("t" . time) ("x" . i32))))
      ((#:ignore-errors . #t)) ((#:try-parse-dates . #t)) ((#:encoding . utf8-lossy))
      ((#:glob . #f))
      ((#:null-values . "NA") (#:try-parse-dates . #t) (#:n-rows . 50)
       (#:schema-overrides . (("dep_delay" . f64))))))
  (for* ([file (in-list reader-files)] [kvs (in-list reader-options)])
    (check-readers-agree every-reader (car file) (cons (cons '#:separator (cdr file)) kvs)))
  (for ([path (list csv-pattern ordered (build-path data-dir "parts" "*.csv"))])
    (check-readers-agree eager-and-scan path '()))
  (define quoted-comment (scratch-file scratch "quoted-comment.csv" "a,b\n1,x\n# it\"s\n2,y\n3,z\n"))
  (check-equal? (column (read-csv quoted-comment #:comment-prefix "#") "a") '(1 2 3))
  (when (and mkfifo sh)
    (check-regexp-match #rx"^read-csv: .*CSV malformed: expected 1 rows, actual 2 rows"
                        (read-through-a-fifo "fifo-quoted-comment.csv"
                                             (lambda (path) (read-csv path #:comment-prefix "#"))
                                             quoted-comment)
                        "a pipe with a quote in a comment line still reads eagerly, and fails"))
  (for ([path (list quoted-comment stray-quote-resynchronised)])
    (check-readers-agree every-reader path '((#:comment-prefix . "#"))))
  (check-true (frame=? (read-csv stray-quote-resynchronised #:comment-prefix "#") stray-full))

  (define (failure-infos thunk)
    (parameterize ([current-check-around (lambda (check) (check))])
      (with-handlers ([exn:test:check? exn:test:check-stack]) (thunk) '())))
  (define (info-text infos name)
    (for/first ([info (in-list infos)] #:when (eq? (check-info-name info) name))
      (match (check-info-value info)
        [(string-info text) text]
        [location (vector-ref (struct->vector location) 1)])))
  (define small (scratch-file scratch "small.csv" "a,b\n1,x\n2,y\n"))
  (define nulled
    (cons 'nulled (lambda (path kvs) (apply-keywords read-csv (cons '(#:null-values . "x") kvs) path))))
  (define disagreeing
    (failure-infos (lambda () (check-readers-agree (list (car eager-and-scan) nulled) small '()))))
  (define call-line (sub1 (syntax-line (quote-syntax here))))
  (check-regexp-match #rx"^eager against nulled: column \"b\", row 0: \"x\" against "
                      (info-text disagreeing 'disagreement))
  (check-regexp-match #rx"^shape [(]2 2[)], dtypes [(][(]\"a\" int64[)] [(]\"b\" string[)][)]\n"
                      (info-text disagreeing 'eager))
  (check-regexp-match #rx"^shape [(]2 2[)]" (info-text disagreeing 'nulled))
  (check-equal? (cadr (info-text disagreeing 'location)) call-line)
  (check-equal? (failure-infos (lambda () (check-readers-agree every-reader small '()))) '())
  (define one-column (dataframe (list (series '(1 2) #:name "a"))))
  (for ([a (list "x" "x" one-column one-column one-column one-column one-column)]
        [b (list "x" "y" one-column "x" (dataframe (list (series '(1 2) #:name "z")))
                 (dataframe (list (series '(1 2) #:name "a" #:dtype 'i32)))
                 (dataframe (list (series '(1) #:name "a"))))]
        [expected (list #f "the errors differ" #f "only the second raised"
                        "columns (\"a\") against (\"z\")" "column \"a\": dtype int64 against int32"
                        "shape (2 1) against (1 1)")])
    (check-equal? (outcome-difference a b) expected))
  (check-equal? (outcome-difference "x" one-column) "only the first raised")

  (define (guard-message path)
    (message-of (lambda () (read-csv path))))
  (check-exn #rx"reads as one column" (lambda () (read-csv flights #:separator #f)))
  (define flights-guard (guard-message flights))
  (check-regexp-match #rx"^read-csv: [^:]*flights.tsv reads as one column" flights-guard)
  (check-regexp-match #rx"splits on #\\\\tab into 19 fields" flights-guard)
  (check-regexp-match #rx"pass #:separator #\\\\tab," flights-guard)
  (check-equal? (length (regexp-match* #rx"flights.tsv" flights-guard)) 1)
  (check-false (exn:fail:contract? (with-handlers ([values values]) (read-csv flights))))
  (check-regexp-match #rx"pass #:separator #\\\\;"
                      (guard-message (scratch-file scratch "semi.csv" "a;b\n1;2\n")))
  (check-regexp-match #rx"pass #:separator #\\\\\\|"
                      (guard-message (scratch-file scratch "pipe.csv" "a|b\n1|2\n")))
  (check-regexp-match #rx"pass #:separator #\\\\;"
                      (guard-message (scratch-file scratch "header-only.csv" "a;b\n")))
  (define ambiguous (scratch-file scratch "ambiguous.csv" "k;v\nx;y\n"))
  (check-regexp-match #rx"reads as one column" (guard-message ambiguous))
  (check-equal? (shape (read-csv ambiguous #:separator #\,)) '(1 1))
  (for ([genuine (list (scratch-file scratch "names.csv" "name\nalice\nbob\n")
                       (scratch-file scratch "titled.csv" "Name; Title\nBob\n")
                       (scratch-file scratch "number.csv" "a|b\n12\n"))])
    (check-true (frame=? (read-csv genuine) (collect (scan-csv genuine))) (format "~a" genuine)))
  (define forced (read-csv flights #:separator #\,))
  (check-equal? (shape forced) '(102 1))
  (check-regexp-match #rx"^year\tmonth\t" (car (column-names forced)))
  (check-equal? (shape (read-csv flights #:has-header #f)) '(103 1))
  (check-equal? (shape (collect (scan-csv flights))) '(102 1))

  (define frame-csv (build-path scratch "frame.csv"))
  (write-csv frame frame-csv)
  (check-true (frame=? (read-csv frame-csv)
                       (dataframe (list (series '("alice" "bob" "carol") #:name "user")
                                        (series '(10 25 18) #:name "score")
                                        (series '(1.2 3.5 2.0) #:name "cost")))))
  (define levels (scratch-file scratch "levels.csv" "level,n\ninfo,1\ndebug,2\ninfo,3\n"))
  (define as-categorical (read-csv levels #:schema-overrides '(("level" . categorical))))
  (check-equal? (dtype (ref as-categorical "level")) 'categorical)
  (check-equal? (column as-categorical "level") '(info debug info))

  (define many 200000)
  (define many-csv (build-path scratch "many.csv"))
  (display-lines-to-file (cons "a,s" (for/list ([i (in-range many)])
                                       (format "~a,row-~a" i (modulo i 977))))
                         many-csv)
  (define gz-csv (build-path scratch "many.csv.gz"))
  (gzip-file many-csv gz-csv)
  (define from-gz-csv (read-csv gz-csv))
  (check-equal? (shape from-gz-csv) (list many 2))
  (check-equal? (ref (ref from-gz-csv "s") (sub1 many)) (format "row-~a" (modulo (sub1 many) 977)))

  (define brussels
    (dataframe (list (series (list (moment 2021 3 27 12 0 0 500000000 #:tz "Europe/Brussels")
                                   polars-null (moment 2021 7 1 #:tz "Europe/Brussels"))
                             #:name "t"))))
  (define brussels-csv (build-path scratch "brussels.csv"))
  (write-csv brussels brussels-csv)
  (check-equal? (file->string brussels-csv)
                "t\n2021-03-27T12:00:00.500000+0100\n\n2021-07-01T00:00:00.000000+0200\n")
  (define offsets (scratch-file scratch "offsets.csv"
                                (string-append "t,u\n"
                                               "2021-03-27T00:00:00+01:00,2021-03-27 00:00\n"
                                               "2021-03-29T00:00:00+02:00,2021-03-29 00:00\n")))
  (for ([read (list (lambda (p) (read-csv p #:try-parse-dates #t))
                    (lambda (p) (collect (scan-csv p #:try-parse-dates #t))))])
    (define parsed (read offsets))
    (check-equal? (dtype (ref parsed "t")) '(datetime microseconds "UTC"))
    (check-equal? (column parsed "t")
                  (list (moment 2021 3 26 23 #:tz "UTC") (moment 2021 3 28 22 #:tz "UTC")))
    (check-equal? (dtype (ref parsed "u")) '(datetime microseconds #f)))

  (define nul-plain (scratch-file scratch "nul-plain.csv" "s,t\n1,2\n"))
  (define nul-named (build-path scratch "nul-named.csv"))
  (check-nul-names-round-trip
   write-csv nul-named (list (assq 'eager eager-and-scan))
   (lambda (n read-with label)
     (check-equal? (column-names (read-with nul-named `((#:columns . (,n))))) (list n) label)))
  (check-nul-names-round-trip
   write-csv nul-named eager-and-scan
   (lambda (n read-with label)
     (check-equal? (column-names (read-with nul-named '())) (list n "s") label)
     (check-equal? (dtype (ref (read-with nul-named `((#:schema-overrides . ((,n . f64))))) n))
                   'float64 label)
     (check-equal? (column (read-with nul-named `((#:null-values . ((,n . "2"))))) n)
                   (list 1 polars-null) label)
     (check-equal? (column-names (read-with nul-plain `((#:new-columns . (,n "t"))))) (list n "t")
                   label)
     (check-equal? (column-names (read-with nul-plain `((#:row-index-name . ,n))))
                   (list n "s" "t") label)))
  (for ([row (in-list (nul-expected 'io-reads))])
    (match-define (list name text marker expected) row)
    (define path (scratch-file scratch "nul-keyword.csv" text))
    (define kvs
      (match name
        ['named-null-values `((#:null-values . (("s" . ,marker))))]
        [_ (list (cons (keyword-of name) marker))]))
    (for ([(kind read-with) (in-dict eager-and-scan)])
      (check-equal? (column (read-with path kvs) "s") expected (format "~a ~s" kind row))))

  (delete-directory/files scratch))
