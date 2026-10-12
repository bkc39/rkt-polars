#lang racket/base

(require (only-in racket/contract/base contract-out)
         (only-in polars/private/csv
                  csv-reader csv-reader/c csv-scanner csv-scanner/c csv-writer csv-writer/c)
         (only-in polars/private/generic/core
                  dataframe? define-wrapped lazyframe? wrap-dataframe wrap-lazyframe))

(provide (contract-out
          [read-csv (csv-reader/c dataframe?)]
          [scan-csv (csv-scanner/c lazyframe?)]
          [write-csv (csv-writer/c dataframe?)]))

(define-wrapped read-csv wrap-dataframe (csv-reader 'read-csv))
(define-wrapped scan-csv wrap-lazyframe (csv-scanner 'scan-csv))
(define write-csv (csv-writer 'write-csv))

(module+ test
  (require rackunit
           racket/file
           racket/runtime-path
           (only-in racket/dict dict-set)
           (only-in racket/list filter-map range remove-duplicates second)
           (only-in racket/match match-lambda)
           (only-in racket/sequence sequence->list)
           (only-in racket/string string-contains? string-join)
           (only-in polars/private/bulk in-series series->list)
           (only-in threading ~>)
           (only-in gregor datetime)
           (prefix-in contracted: (submod ".."))
           (prefix-in raw: polars/private/csv)
           (only-in polars/private/generic/core
                    column-names dataframe dtype height lazyframe? null-count ref series shape)
           (only-in polars/private/generic/printing series->string)
           (only-in polars/private/generic/reshape collect)
           polars/private/generic/test-fixtures
           (submod polars/private/generic/test-fixtures test))

  (define-runtime-path data-dir "../../scribblings/data")
  (define (read-and-scan-agree path kvs)
    (reads-agree? read-csv scan-csv collect path kvs))
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
      (#:schema-overrides . (("a" . (enum x y))))
      (#:schema-overrides . (("a" . int32) ("a" . f64)))
      (#:schema-overrides . ,(hash "a" 'int32)) (#:encoding . latin1) (#:glob . 1)
      (#:eol-char . "\n") (#:eol-char . #\é) (#:eol-char . 10)
      (#:new-columns . ("x" "x")) (#:new-columns . "x") (#:new-columns . (x))
      (#:row-index-name . i) (#:row-index-offset . -1) (#:row-index-offset . ,(expt 2 32))
      (#:skip-lines . -1) (#:skip-rows-after-header . 1.5) (#:infer-schema . 0)
      (#:raise-if-empty . 1) (#:missing-utf8-is-empty-string . "yes")
      (#:truncate-ragged-lines . 1) (#:decimal-comma . 1)
      (#:new-columns . ("a\u0000b")) (#:null-values . "N\u0000A")
      (#:null-values . ("NA" "N\u0000A")) (#:null-values . (("a\u0000b" . "NA")))
      (#:null-values . (("a" . "N\u0000A"))) (#:schema-overrides . (("a\u0000b" . f64)))
      (#:comment-prefix . "#\u0000") (#:row-index-name . "i\u0000")))
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
      (#:columns . "a") (#:columns . ("a\u0000junk"))))
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

  (define quoted (scratch-file scratch "quoted.csv" "a,b\n\"1,5\",x\n\"2\",y\n"))
  (check-equal? (column (read-csv quoted) "a") '("1,5" "2"))
  (check-exn #rx"found more fields than defined" (lambda () (read-csv quoted #:quote-char #f)))
  (define commented (scratch-file scratch "commented.csv" "# note\na,b\n1,2\n# mid\n3,4\n"))
  (check-equal? (shape (read-csv commented #:comment-prefix "#")) '(2 2))
  (check-equal? (column (read-csv commented #:comment-prefix "#") "a") '(1 3))
  (define slashed (scratch-file scratch "slashed.csv" "x\n//skip\n1\n"))
  (check-equal? (column (read-csv slashed #:comment-prefix "//") "x") '(1))

  (define latin (scratch-file scratch "latin.csv" #"s\ncaf\351\n"))
  (check-exn #rx"invalid utf-8" (lambda () (read-csv latin)))
  (check-equal? (column (read-csv latin #:encoding 'utf8-lossy) "s")
                (list (string #\c #\a #\f (integer->char #xFFFD))))

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
  (check-exn #rx"^lazyframe-collect: " (lambda () (collect (scan-csv gone))))
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

  (define (outcome thunk)
    (with-handlers ([exn:fail? (lambda (e) (cause-of (exn-message e)))]) (thunk)))
  (define (same-outcome? a b)
    (if (string? a)
        (equal? a b)
        (and (not (string? b)) (frame=? a b))))
  (define (readers-agree? path kvs)
    (define globbed (dict-set kvs '#:glob #t))
    (define eager (outcome (lambda () (apply-keywords read-csv kvs path))))
    (and (same-outcome? eager (outcome (lambda () (apply-keywords read-csv globbed
                                                                  (one-file-pattern path)))))
         (same-outcome? eager (outcome (lambda () (collect (apply-keywords scan-csv kvs path)))))))
  (define semi (scratch-file scratch "semi-opts.txt" "# note\na;b\n'x;y';1\n# mid\nz;2\n"))
  (define reader-files
    (list (cons flights #\tab) (cons quoted #\,) (cons commented #\,) (cons slashed #\,)
          (cons dated #\,) (cons typed #\,) (cons latin #\,) (cons semi #\;)))
  (define reader-options
    '(() ((#:has-header . #f)) ((#:quote-char . #\')) ((#:quote-char . #f))
      ((#:comment-prefix . "#")) ((#:comment-prefix . "//"))
      ((#:skip-rows . 1)) ((#:n-rows . 1)) ((#:skip-rows . 1) (#:n-rows . 2))
      ((#:null-values . "NA")) ((#:null-values . ("NA" "-")))
      ((#:infer-schema-length . 0)) ((#:infer-schema-length . 1)) ((#:infer-schema-length . #f))
      ((#:schema-overrides . (("dep_delay" . f64))))
      ((#:schema-overrides . (("d" . date) ("t" . time) ("x" . i32))))
      ((#:ignore-errors . #t)) ((#:try-parse-dates . #t)) ((#:encoding . utf8-lossy))
      ((#:glob . #f))
      ((#:null-values . "NA") (#:try-parse-dates . #t) (#:n-rows . 50)
       (#:schema-overrides . (("dep_delay" . f64))))))
  (for* ([file (in-list reader-files)] [kvs (in-list reader-options)])
    (check-true (readers-agree? (car file) (cons (cons '#:separator (cdr file)) kvs))
                (format "~a ~s" (car file) kvs)))
  (for ([path (list csv-pattern ordered (build-path data-dir "parts" "*.csv"))])
    (check-true (read-and-scan-agree path '()) (format "~a" path)))

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

  (delete-directory/files scratch))
