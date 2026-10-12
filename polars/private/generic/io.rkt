#lang racket/base

(require (only-in racket/contract/base contract-out)
         (only-in polars/private/csv
                  csv-reader csv-reader/c csv-scanner csv-scanner/c csv-writer csv-writer/c)
         (only-in polars/private/parquet
                  parquet-reader parquet-reader/c parquet-scanner parquet-scanner/c
                  parquet-writer parquet-writer/c)
         (only-in polars/private/generic/core
                  dataframe? lazyframe? wrap-dataframe wrap-lazyframe)
         syntax/parse/define)

(provide define-wrapped
         (contract-out
          [read-csv (csv-reader/c dataframe?)]
          [scan-csv (csv-scanner/c lazyframe?)]
          [read-parquet (parquet-reader/c dataframe?)]
          [scan-parquet (parquet-scanner/c lazyframe?)]
          [write-csv (csv-writer/c dataframe?)]
          [write-parquet (parquet-writer/c dataframe?)]))

(define-syntax-parse-rule (define-wrapped name:id wrap:expr reader:expr)
  (define name (procedure-rename (compose1 wrap reader) 'name)))

(define-wrapped read-csv wrap-dataframe (csv-reader 'read-csv))
(define-wrapped scan-csv wrap-lazyframe (csv-scanner 'scan-csv))
(define-wrapped read-parquet wrap-dataframe (parquet-reader 'read-parquet))
(define-wrapped scan-parquet wrap-lazyframe (parquet-scanner 'scan-parquet))
(define write-csv (procedure-rename (csv-writer 'write-csv) 'write-csv))
(define write-parquet (parquet-writer 'write-parquet))

(module+ test
  (require rackunit
           racket/file
           racket/runtime-path
           (only-in file/gzip gzip-through-ports)
           (only-in racket/list filter-map last remove-duplicates second)
           (only-in racket/match match-lambda)
           (only-in racket/sequence sequence->list)
           (only-in racket/string string-contains? string-join)
           (only-in polars/private/bulk in-series series->list)
           (only-in threading ~>)
           (only-in gregor datetime)
           (prefix-in contracted: (submod ".."))
           (prefix-in raw: polars/private/csv)
           (only-in polars/private/generic/core
                    column-names dataframe dtype height null-count ref series shape)
           (only-in polars/private/generic/printing series->string)
           (only-in polars/private/generic/reshape collect)
           polars/private/generic/test-fixtures
           (submod polars/private/generic/test-fixtures test))

  (define-runtime-path data-dir "../../scribblings/data")
  (define flights (build-path data-dir "flights.tsv"))
  (define scratch (make-temporary-directory "rkt-polars-io-~a"))
  (for ([sub '("globbed" "ordered" "mixed" "literal" "dirmix")])
    (make-directory (build-path scratch sub)))

  (define (cause-of message)
    (last (regexp-match #rx"^[^:]*: [^:]*: ([^\n]*)" message)))

  (define (read-and-scan-agree path kvs)
    (define eager
      (with-handlers ([exn:fail? exn-message]) (apply-keywords read-csv kvs path)))
    (define lazy
      (with-handlers ([exn:fail? exn-message]) (collect (apply-keywords scan-csv kvs path))))
    (if (string? eager)
        (and (string? lazy) (equal? (cause-of eager) (cause-of lazy)))
        (and (not (string? lazy)) (frame=? eager lazy))))

  (define scan-keywords
    (sort '(#:comment-prefix #:decimal-comma #:encoding #:eol-char #:glob #:has-header
            #:ignore-errors #:infer-schema #:infer-schema-length
            #:missing-utf8-is-empty-string #:n-rows #:new-columns #:null-values #:quote-char
            #:raise-if-empty #:row-index-name #:row-index-offset #:schema-overrides
            #:separator #:skip-lines #:skip-rows #:skip-rows-after-header
            #:truncate-ragged-lines #:try-parse-dates)
          keyword<?))
  (define read-keywords (sort (cons '#:columns scan-keywords) keyword<?))
  (define csv-readers
    (list contracted:read-csv contracted:scan-csv raw:dataframe-read-csv raw:lazyframe-scan-csv))
  (for ([reader (in-list csv-readers)]
        [keywords (list read-keywords scan-keywords read-keywords scan-keywords)])
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
    (check-exn #rx"does not expect an argument with given keyword\n.*given keyword: #:columns"
               (lambda () (reader missing #:columns '("a")))))
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
  (for ([hint '("#:infer-schema-length 10000" "#:schema-overrides" "#:ignore-errors to #t"
                "`NA` to #:null-values")])
    (check-true (string-contains? unparsed hint) hint))
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

  (define latin (build-path scratch "latin.csv"))
  (call-with-output-file latin #:exists 'replace
    (lambda (out) (void (write-bytes #"s\ncaf\351\n" out))))
  (check-exn #rx"invalid utf-8" (lambda () (read-csv latin)))
  (check-equal? (column (read-csv latin #:encoding 'utf8-lossy) "s")
                (list (string #\c #\a #\f (integer->char #xFFFD))))

  (define big (build-path scratch "big.csv"))
  (call-with-output-file big #:exists 'replace
    (lambda (out)
      (write-string "x\n" out)
      (for ([i (in-range 100000)]) (write-string (format "~a\n" i) out))))
  (define first-half (read-csv big #:n-rows 50000))
  (check-equal? (height first-half) 50000)
  (check-equal? (ref (ref first-half #:columns "x") 49999) 49999)
  (define skipped (read-csv big #:skip-rows 3 #:has-header #f))
  (check-equal? (height skipped) 99998)
  (check-equal? (ref (ref skipped #:columns "column_1") 0) 2)

  (define gappy (build-path scratch "gappy.csv"))
  (call-with-output-file gappy #:exists 'replace
    (lambda (out)
      (write-string "x,s\n" out)
      (for ([i (in-range 200000)])
        (write-string (if (zero? (modulo i 7)) ",\n" (format "~a,s~a\n" i i)) out))))
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
    (scratch-file scratch (format "globbed/~a.csv" name) (format "x\n~a\n" value))
    (write-parquet (dataframe (list (series (list value) #:name "x")))
                   (build-path scratch "globbed" (format "~a.parquet" name))))
  (void (scratch-file scratch "globbed/skip.txt" "x\n99\n"))
  (define csv-pattern (build-path scratch "globbed" "*.csv"))
  (define parquet-pattern (build-path scratch "globbed" "*.parquet"))
  (check-equal? (column (read-csv csv-pattern) "x") '(1 2 3))
  (check-equal? (~> csv-pattern scan-csv collect (column "x")) '(1 2 3))
  (check-equal? (column (read-parquet parquet-pattern) "x") '(1 2 3))
  (check-equal? (~> parquet-pattern scan-parquet collect (column "x")) '(1 2 3))

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
  (check-pred lazyframe? (scan-parquet nothing))
  (for ([thunk (list (lambda () (read-csv nothing))
                     (lambda () (collect (scan-csv nothing)))
                     (lambda () (read-parquet nothing))
                     (lambda () (collect (scan-parquet nothing))))])
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
    (display-lines-to-file (list "x" value) (build-path dir "data.csv") #:exists 'replace)
    (write-parquet (dataframe (list (series (list (string->number value)) #:name "x")))
                   (build-path dir "data.parquet")))
  (parameterize ([current-directory bracketed-dir])
    (check-equal? (column (read-csv "data.csv") "x") '(7))
    (check-equal? (column (read-csv "data.csv" #:glob #f) "x") '(7))
    (check-equal? (column (read-csv "*.csv") "x") '(7))
    (check-equal? (~> "data.csv" scan-csv collect (column "x")) '(7))
    (check-equal? (column (read-parquet "data.parquet") "x") '(7))
    (check-equal? (~> "data.parquet" scan-parquet collect (column "x")) '(7))
    (write-csv (read-csv "data.csv") "copy.csv")
    (check-true (file-exists? (build-path bracketed-dir "copy.csv")))
    (make-directory* "sub")
    (make-directory* "hive/year=2013")
    (write-csv (read-csv "data.csv") "sub/a.csv")
    (write-parquet (read-csv "data.csv") "hive/year=2013/p.parquet")
    (check-equal? (~> "sub/*.csv" read-csv (column "x")) '(7))
    (check-equal? (~> (scan-csv "sub" #:glob #f) collect (column "x")) '(7))
    (check-exn #rx"cannot open file: it is a directory" (lambda () (read-csv "sub")))
    (check-equal? (~> "hive" read-parquet (column "x")) '(7))
    (check-exn #rx"cannot open file: [Nn]o such file" (lambda () (read-csv "missing.csv"))))
  (check-equal? (object-name read-csv) 'read-csv)
  (check-exn #rx"^read-csv: " (lambda () (contracted:read-csv "x.csv" "extra")))
  (check-exn #rx"quote-char must differ from the separator"
             (lambda () (contracted:read-csv missing #:quote-char #\,)))

  (void (scratch-file scratch "dirmix/a.csv" "x\n1\n")
        (scratch-file scratch "dirmix/notes.txt" "x\n99\n"))
  (check-exn #rx"^read-csv: failed to read csv from [^:]*dirmix: cannot open file: it is a directory"
             (lambda () (read-csv (build-path scratch "dirmix") #:glob #f)))

  (for ([year '(2013 2014)])
    (define dir (build-path scratch "hive" (format "year=~a" year)))
    (make-directory* dir)
    (write-parquet (dataframe (list (series (list year) #:name "x")))
                   (build-path dir "p.parquet")))
  (define hive (build-path scratch "hive"))
  (check-equal? (column-names (read-parquet (build-path hive "year=2013" "p.parquet"))) '("x"))
  (check-equal? (column-names (read-parquet (build-path hive "*" "p.parquet"))) '("x"))
  (check-equal? (~> (build-path hive "*" "p.parquet") scan-parquet collect column-names) '("x"))
  (check-equal? (column-names (read-parquet hive)) '("x" "year"))

  (define (one-file-pattern path)
    (define-values (dir name _) (split-path path))
    (define file (path->string name))
    (build-path dir (string-append "[" (substring file 0 1) "]" (substring file 1))))
  (define (outcome thunk)
    (with-handlers ([exn:fail? (lambda (e) (cause-of (exn-message e)))]) (thunk)))
  (define (same-outcome? a b)
    (if (string? a)
        (equal? a b)
        (and (not (string? b)) (frame=? a b))))
  (define (readers-agree? path kvs)
    (define globbed (cons '(#:glob . #t) (filter (lambda (kv) (not (eq? (car kv) '#:glob))) kvs)))
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
  (define frame-parquet (build-path scratch "frame.parquet"))
  (write-parquet frame frame-parquet)
  (check-true (frame=? (read-parquet frame-parquet) frame))
  (check-equal? (height (collect (scan-parquet frame-parquet #:n-rows 2))) 2)

  (define produce (read-parquet (build-path data-dir "produce.parquet")))
  (check-equal? (for/list ([name (column-names produce)]) (dtype (ref produce name)))
                '(categorical (enum low mid high) (decimal 10 2)))
  (check-equal? (column produce "item") '(apple pear apple fig))
  (check-equal? (series->list (ref produce "grade")) (list 'high 'low polars-null 'mid))
  (check-equal? (column produce "price") (list 5/4 4/5 polars-null 12))
  (check-regexp-match #rx"\\[decimal\\[10,2\\]\\]\n\\[\n\t1.25\n\t0.80\n\tnull\n\t12.00\n\\]"
                      (series->string (ref produce "price")))
  (define produce-copy (build-path scratch "produce.parquet"))
  (write-parquet produce produce-copy)
  (check-true (frame=? (read-parquet produce-copy) produce))

  (define levels (scratch-file scratch "levels.csv" "level,n\ninfo,1\ndebug,2\ninfo,3\n"))
  (define as-categorical (read-csv levels #:schema-overrides '(("level" . categorical))))
  (check-equal? (dtype (ref as-categorical "level")) 'categorical)
  (check-equal? (column as-categorical "level") '(info debug info))

  (define (gzip-file name rows)
    (define plain
      (scratch-file scratch (string-append name ".plain") (string-join rows "\n" #:after-last "\n")))
    (define packed (build-path scratch (string-append name ".gz")))
    (call-with-input-file plain
      (lambda (in)
        (call-with-output-file packed #:exists 'replace
          (lambda (out) (gzip-through-ports in out #f 0)))))
    packed)
  (define many 200000)
  (define gz-csv
    (gzip-file "many.csv" (cons "a,s" (for/list ([i (in-range many)])
                                       (format "~a,row-~a" i (modulo i 977))))))
  (define from-gz-csv (read-csv gz-csv))
  (check-equal? (shape from-gz-csv) (list many 2))
  (check-equal? (ref (ref from-gz-csv "s") (sub1 many)) (format "row-~a" (modulo (sub1 many) 977)))

  (delete-directory/files scratch))

(module+ test
  (require (only-in racket/string string-contains?)
           (only-in polars/private/generic/operators [> p>])
           (only-in polars/private/generic/reshape explain lazy select)
           (only-in polars/private/generic/reshape [filter frame-filter]))

  (define pq-dir (make-temporary-directory "rkt-polars-io-parquet-~a"))
  (define (pq-file name) (build-path pq-dir name))
  (define (data name) (build-path data-dir name))

  (define pq-flights (read-parquet (data "flights.parquet")))
  (check-true (frame=? pq-flights
                       (read-csv flights #:separator #\tab #:null-values "NA"
                                 #:try-parse-dates #t)))
  (check-equal? (shape pq-flights) '(102 19))
  (check-equal? (column (read-parquet (data "flights.parquet")
                                      #:columns '("carrier" "dep_delay") #:n-rows 3)
                        "dep_delay")
                '(2 4 2))
  (define numbered (read-parquet (data "flights.parquet") #:columns '(0 1 -1) #:n-rows 2
                                 #:row-index-name "row" #:row-index-offset 1))
  (check-equal? (column-names numbered) '("row" "year" "time_hour"))
  (check-equal? (column numbered "row") '(1 2))
  (check-equal? (column-names (read-parquet (data "produce.parquet") #:include-file-paths "file"))
                '("item" "grade" "price" "file"))
  (parameterize ([current-directory data-dir])
    (check-equal? (message-of (lambda () (read-parquet "produce.parquet"
                                                       #:columns '("item" "colour"))))
                  (string-append "read-parquet: failed to read parquet from produce.parquet: "
                                 "columns not in the file: \"colour\"")))

  (define pq-produce (read-parquet (data "produce.parquet")))
  (make-directory* (pq-file "mixed"))
  (write-parquet pq-produce (pq-file "mixed/a.parquet"))
  (write-parquet (select pq-produce "item") (pq-file "mixed/b.parquet"))
  (define mixed (pq-file "mixed/*.parquet"))
  (check-regexp-match
   #rx"^read-parquet: failed to read parquet from [^:]*mixed/[*].parquet: .*grade.*#:missing-columns 'insert"
   (message-of (lambda () (read-parquet mixed))))
  (parameterize ([current-directory pq-dir])
    (check-regexp-match
     #rx"^read-parquet: failed to read parquet from mixed/[*][.]parquet: .*grade"
     (message-of (lambda () (read-parquet "mixed/*.parquet")))))
  (check-equal? (shape (read-parquet (data "flights.parquet") #:parallel 'row-groups
                                     #:use-statistics #f #:low-memory #t #:rechunk #t))
                '(102 19))
  (parameterize ([current-directory data-dir])
    (check-equal? (shape (read-parquet "produce.parque?")) '(4 3))
    (check-regexp-match
     #rx"^read-parquet: failed to read parquet from produce[.]parque[?]: cannot open file: "
     (message-of (lambda () (read-parquet "produce.parque?" #:glob #f)))))
  (define cached (collect (scan-parquet (data "produce.parquet") #:cache #f
                                        #:row-index-name "row")))
  (check-equal? (column-names cached) '("row" "item" "grade" "price"))
  (check-equal? (column cached "row") '(0 1 2 3))
  (check-regexp-match
   #rx"^explain: failed to explain the query: [^\n]*\"colour\""
   (message-of (lambda () (explain (select (lazy pq-produce) "colour")))))
  (define inserted (read-parquet mixed #:missing-columns 'insert))
  (check-equal? (shape inserted) '(8 3))
  (check-equal? (dtypes-of inserted) (dtypes-of pq-produce))
  (check-equal? (null-count (ref inserted "grade")) 5)

  (define late
    (~> (scan-parquet (data "flights.parquet"))
        (frame-filter (p> (col "dep_delay") 20))
        (select "carrier" "dep_delay")))
  (check-equal? (column (collect late) "dep_delay") '(24 47 39))
  (check-equal? (column (collect late) "carrier") '("EV" "UA" "MQ"))
  (define optimised (explain late))
  (check-regexp-match #rx"^Parquet SCAN [[][^]]*/flights[.]parquet[]]\n" optimised)
  (for ([part '("PROJECT 2/19 COLUMNS" "SELECTION: col(\"dep_delay\") > 20")])
    (check-true (string-contains? optimised part) part))
  (define unoptimised (explain late #:optimized #f))
  (check-false (string-contains? unoptimised "PROJECT 2/19 COLUMNS"))
  (for ([part '("SELECT [col(\"carrier\"), col(\"dep_delay\")]"
                "FILTER col(\"dep_delay\") > 20" "FROM" "Parquet SCAN [" "PROJECT */19 COLUMNS")])
    (check-true (string-contains? unoptimised part) part))
  (check-true (string-contains? (explain late #:format 'tree) "SELECTION"))
  (define tree (explain (select (lazy pq-produce) "item") #:format 'tree))
  (for ([part '("DF [\"item\", \"grade\", \"price\"]" "PROJECT: [\"item\"]; 1/3 COLUMNS")])
    (check-true (string-contains? tree part) part))
  (check-regexp-match #rx"^scan-parquet: contract violation\n  expected: parquet-parallel/c\n  given: 'row_groups"
                      (message-of (lambda () (contracted:scan-parquet (data "flights.parquet")
                                                                      #:parallel 'row_groups))))
  (check-regexp-match #rx"^application: procedure does not expect an argument with given keyword\n  procedure: scan-parquet\n  given keyword: #:columns"
                      (message-of (lambda () (contracted:scan-parquet (data "produce.parquet")
                                                                      #:columns '("item")))))
  (check-regexp-match #rx"^(lazyframe-)?collect: .*[Nn]o such file"
                      (message-of (lambda () (collect (scan-parquet "/no/such/file.parquet")))))
  (for ([i '(1 2 3)])
    (write-parquet (read-csv (data (format "parts/part-~a.csv" i)))
                   (pq-file (format "part-~a.parquet" i))))
  (check-equal? (height (read-parquet (pq-file "part-*.parquet")))
                (for/sum ([i '(1 2 3)]) (height (read-csv (data (format "parts/part-~a.csv" i))))))
  (check-equal? (height (collect (scan-parquet (pq-file "part-*.parquet") #:n-rows 3))) 3)

  (define out (pq-file "produce.parquet"))
  (write-parquet pq-produce out #:compression 'gzip #:compression-level 9 #:statistics #f)
  (check-true (frame=? (read-parquet out) pq-produce))
  (write-parquet pq-produce out #:compression 'lz4 #:row-group-size 2
                 #:statistics '(min max null-count distinct-count)
                 #:data-page-size 4096)
  (check-true (frame=? (read-parquet out) pq-produce))
  (check-regexp-match
   #rx"^write-parquet: contract violation\n  #:compression-level 30 is outside zstd's levels, 1 to 22\n"
   (message-of (lambda () (contracted:write-parquet pq-produce out #:compression-level 30))))
  (check-regexp-match
   #rx"^write-parquet: contract violation\n  expected: parquet-statistics/c\n  given: '[(]null-count[)]"
   (message-of (lambda () (contracted:write-parquet pq-produce out #:statistics '(null-count)))))
  (check-true (frame=? (read-parquet out) pq-produce))
  (check-equal? (message-of (lambda () (write-parquet pq-produce "/no/such/dir/out.parquet")))
                (string-append "write-parquet: failed to write parquet to /no/such/dir/out.parquet: "
                               "cannot create file: No such file or directory (os error 2)"))
  (check-regexp-match #rx"^read-parquet: failed to read parquet from [^:]*: .*PAR1"
                      (message-of (lambda () (read-parquet (data "flights.tsv")))))
  (check-regexp-match #rx"^explain: contract violation\n  expected: lazyframe[?]"
                      (message-of (lambda () (explain pq-produce))))
  (check-regexp-match #rx"^explain: contract violation\n  expected: explain-format/c\n  given: 'dot"
                      (message-of (lambda () (explain late #:format 'dot))))

  (define foo-bar
    (dataframe (list (series '(1 2 3) #:name "foo")
                     (series (list polars-null "bak" "baz") #:name "bar"))))
  (write-parquet foo-bar (pq-file "path.parquet"))
  (check-true (frame=? (read-parquet (pq-file "path.parquet")) foo-bar))
  (check-true (frame=? (collect (scan-parquet (pq-file "path.parquet"))) foo-bar))

  (write-csv pq-produce (pq-file "produce.csv"))
  (check-equal? (map second (dtypes-of (read-csv (pq-file "produce.csv")))) '(string string float64))
  (check-equal? (column (read-csv (pq-file "produce.csv")) "price") (list 1.25 0.8 polars-null 12.0))
  (write-parquet pq-produce (pq-file "produce-copy.parquet"))
  (check-equal? (map second (dtypes-of (read-parquet (pq-file "produce-copy.parquet"))))
                '(categorical (enum low mid high) (decimal 10 2)))
  (define stamps (select pq-flights "time_hour"))
  (write-csv stamps (pq-file "stamps.csv"))
  (check-equal? (dtype (ref (read-csv (pq-file "stamps.csv")) "time_hour")) 'string)
  (write-parquet stamps (pq-file "stamps.parquet"))
  (check-equal? (dtype (ref (read-parquet (pq-file "stamps.parquet")) "time_hour"))
                '(datetime microseconds #f))

  (define framed (read-parquet (data "flights.parquet") #:columns '("row" "carrier" "dep_delay")
                               #:n-rows 3 #:row-index-name "row"))
  (check-equal? (column framed "row") '(0 1 2))
  (check-equal? (column framed "carrier") '("UA" "UA" "AA"))
  (write-parquet pq-flights (pq-file "flights.parquet")
                 #:compression 'gzip #:compression-level 9 #:statistics 'full #:row-group-size 50)
  (check-true (frame=? (read-parquet (pq-file "flights.parquet")) pq-flights))

  (check-staged-write write-parquet "parquet" pq-produce)
  (define leftover (pq-file "leftover"))
  (make-directory leftover)
  (write-parquet pq-produce (build-path leftover "a.parquet"))
  (copy-file (build-path leftover "a.parquet") (build-path leftover ".rkt-polars-1-0.partial"))
  (check-equal? (height (read-parquet (build-path leftover "*.parquet"))) 4)
  (check-equal? (height (read-parquet (build-path leftover "*"))) 8)
  (check-regexp-match
   #rx"directory contained paths with different file extensions: first path: [^,]*/[.]rkt-polars-1-0[.]partial,"
   (message-of (lambda () (read-parquet leftover))))

  (delete-directory/files pq-dir))

(module+ test
  (require (only-in polars/private/generic/reshape rename select [filter frame-filter])
           (only-in polars/private/generic/operators [> gt]))
  (define csv-dir (make-temporary-directory "rkt-polars-csv-options-~a"))
  (define (rows-of df)
    (for/list ([i (in-range (height df))])
      (for/list ([name (in-list (column-names df))]) (list-ref (column df name) i))))

  (define abc (scratch-file csv-dir "abc.csv" "a,b,c\n1,NA,x\nNA,2,-\n3,4,y\n"))
  (define abc-pattern (build-path csv-dir "[a]bc.csv"))

  (define a-only (read-csv abc #:null-values '(("a" . "NA"))))
  (check-equal? (map second (dtypes-of a-only)) '(int64 string string))
  (check-equal? (rows-of a-only) (list (list 1 "NA" "x") (list polars-null "2" "-")
                                       (list 3 "4" "y")))
  (check-equal? (rows-of (read-csv abc #:null-values '(("a" . "NA") ("c" . "-"))))
                (list (list 1 "NA" "x") (list polars-null "2" polars-null) (list 3 "4" "y")))
  (check-true (frame=? a-only (read-csv abc-pattern #:null-values '(("a" . "NA")))))
  (check-true (read-and-scan-agree abc '((#:null-values . (("a" . "NA"))))))
  (check-true (frame=? (read-csv abc #:null-values '()) (read-csv abc)))
  (check-regexp-match
   #rx"^read-csv: failed to read csv from [^:]*abc.csv: not found: unable to find column \"zzz\"; valid columns: \\[\"a\", \"b\", \"c\"\\]"
   (message-of (lambda () (read-csv abc #:null-values '(("zzz" . "NA"))))))
  (check-regexp-match #rx"unable to find column \"zzz\""
                      (message-of (lambda () (collect (scan-csv abc #:null-values '(("zzz" . "NA")))))))

  (check-equal? (column-names (read-csv abc #:columns '("c" "a"))) '("a" "c"))
  (check-equal? (column-names (read-csv abc #:columns '(2 0))) '("a" "c"))
  (check-true (frame=? (read-csv abc #:columns '("c" "a")) (read-csv abc-pattern #:columns '(2 0))))
  (check-true (frame=? (read-csv abc #:columns '()) (read-csv abc)))
  (check-regexp-match #rx"^read-csv: failed to read csv from [^:]*abc.csv: not found: unable to find column \"zzz\""
                      (message-of (lambda () (read-csv abc #:columns '("zzz")))))
  (for ([path (list abc abc-pattern)])
    (check-regexp-match #rx"projection index: 7 is out of bounds for csv schema with length: 3$"
                        (message-of (lambda () (read-csv path #:columns '(7))))))
  (check-equal? (column-names (read-csv abc #:columns '("b") #:row-index-name "i")) '("i" "b"))
  (check-equal? (column-names (read-csv abc #:columns '(1) #:row-index-name "i")) '("i" "b"))

  (check-equal? (column-names (read-csv abc #:new-columns '("x"))) '("x" "b" "c"))
  (check-true (read-and-scan-agree abc '((#:new-columns . ("x")))))
  (define na-in-a (read-csv abc #:null-values '(("a" . "NA"))))
  (for ([renamed (list (read-csv abc #:new-columns '("x") #:null-values '(("x" . "NA")))
                       (collect (scan-csv abc #:new-columns '("x")
                                          #:null-values '(("x" . "NA")))))])
    (check-equal? (map second (dtypes-of renamed)) '(int64 string string))
    (check-true (frame=? renamed (rename na-in-a "a" "x"))))
  (define swapped-keywords
    '((#:new-columns . ("c" "x" "a")) (#:null-values . (("c" . "NA")))
      (#:row-index-name . "b")))
  (define swapped (apply-keywords read-csv swapped-keywords abc))
  (check-equal? (column-names swapped) '("b" "c" "x" "a"))
  (check-equal? (map second (dtypes-of swapped)) '(uint32 int64 string string))
  (check-equal? (column swapped "b") '(0 1 2))
  (check-equal? (for/list ([name '("c" "x" "a")]) (column swapped name))
                (for/list ([name '("a" "b" "c")]) (column na-in-a name)))
  (check-true (frame=? swapped (collect (apply-keywords scan-csv swapped-keywords abc))))
  (check-regexp-match #rx"^read-csv: failed to read csv from [^:]*abc.csv: 4 new column names for a file of 3 columns$"
                      (message-of (lambda () (read-csv abc #:new-columns '("p" "q" "r" "s")))))
  (check-regexp-match #rx"^scan-csv: failed to scan [^:]*abc.csv: 4 new column names for a file of 3 columns$"
                      (message-of (lambda () (scan-csv abc #:new-columns '("p" "q" "r" "s")))))
  (check-regexp-match #rx"duplicate: column with name 'b' has more than one occurrence$"
                      (message-of (lambda () (read-csv abc #:new-columns '("b")))))
  (define headerless (read-csv abc #:has-header #f #:new-columns '("p" "q" "r")))
  (check-equal? (column-names headerless) '("p" "q" "r"))
  (check-equal? (height headerless) 4)
  (define renamed-typed
    (read-csv abc #:new-columns '("x") #:null-values '(("x" . "NA"))
              #:schema-overrides '(("x" . f64))))
  (check-equal? (map second (dtypes-of renamed-typed)) '(float64 string string))
  (check-equal? (column renamed-typed "x") (list 1.0 polars-null 3.0))
  (check-regexp-match #rx"schema overrides name columns not in the file: \"a\"$"
                      (message-of (lambda () (read-csv abc #:new-columns '("x")
                                                       #:schema-overrides '(("a" . f64))))))
  (check-regexp-match #rx"^scan-csv: failed to scan [^:]*nope.csv: "
                      (message-of (lambda () (scan-csv (build-path csv-dir "nope.csv")
                                                       #:new-columns '("x")))))
  (check-equal? (column-names (read-csv abc #:new-columns '("x") #:columns '("x" "c")))
                '("x" "c"))
  (define no-match (build-path csv-dir "*.none"))
  (check-regexp-match #rx"^scan-csv: failed to scan [^:]*[*][.]none: no files match the pattern$"
                      (message-of (lambda () (scan-csv no-match #:new-columns '("x")))))
  (check-regexp-match #rx"^read-csv: failed to read csv from [^:]*[*][.]none: no files match the pattern$"
                      (message-of (lambda () (read-csv no-match #:new-columns '("x")))))

  (define indexed (read-csv abc #:row-index-name "i" #:row-index-offset 10))
  (check-equal? (column-names indexed) '("i" "a" "b" "c"))
  (check-equal? (dtype (ref indexed "i")) 'uint32)
  (check-equal? (column indexed "i") '(10 11 12))
  (check-true (read-and-scan-agree abc '((#:row-index-name . "i") (#:row-index-offset . 10))))
  (define clash "duplicate: cannot add row_index with name 'a': column already exists in file.")
  (check-equal? (cause-of (message-of (lambda () (read-csv abc #:row-index-name "a")))) clash)
  (check-equal? (cause-of (message-of (lambda () (read-csv abc #:row-index-name "a"
                                                           #:columns '("b")))))
                clash)
  (check-regexp-match (regexp-quote clash)
                      (message-of (lambda () (collect (scan-csv abc #:row-index-name "a")))))
  (check-regexp-match #rx"cannot add row_index with name 'x'"
                      (message-of (lambda () (scan-csv abc #:new-columns '("x")
                                                       #:row-index-name "x"))))
  (check-regexp-match #rx"^read-csv: failed to read csv from [^:]*abc.csv: polars panicked: .*overflows"
                      (message-of (lambda () (read-csv abc #:row-index-name "i"
                                                       #:row-index-offset #xFFFFFFFE))))

  (define eol-fixture (build-path data-dir "eol.csv"))
  (check-equal? (rows-of (read-csv eol-fixture #:eol-char #\;)) '(("UA" 1545) ("AA" 1141)))
  (check-equal? (map second (dtypes-of (read-csv eol-fixture #:eol-char #\;))) '(string int64))
  (check-equal? (rows-of (collect (scan-csv eol-fixture #:eol-char #\; #:row-index-name "row"
                                            #:row-index-offset 1)))
                '((1 "UA" 1545) (2 "AA" 1141)))
  (check-true (read-and-scan-agree eol-fixture '((#:eol-char . #\;) (#:row-index-name . "row")
                                                 (#:row-index-offset . 1))))
  (define eol (scratch-file csv-dir "eol.csv" "a,b;1,x;2,y;"))
  (check-equal? (rows-of (read-csv eol #:eol-char #\;)) '((1 "x") (2 "y")))
  (check-true (read-and-scan-agree eol '((#:eol-char . #\;))))
  (define ragged (scratch-file csv-dir "ragged.csv" "a,b\n1,x\n2,y,extra\n3\n"))
  (check-regexp-match #rx"found more fields than defined in 'Schema'\n\nConsider setting #:truncate-ragged-lines #t\\.$"
                      (message-of (lambda () (read-csv ragged))))
  (check-equal? (rows-of (read-csv ragged #:truncate-ragged-lines #t))
                (list '(1 "x") '(2 "y") (list 3 polars-null)))
  (check-true (read-and-scan-agree ragged '((#:truncate-ragged-lines . #t))))
  (define commas (scratch-file csv-dir "commas.csv" "a;b\n1,5;x\n2,25;y\n"))
  (check-equal? (column (read-csv commas #:separator #\;) "a") '("1,5" "2,25"))
  (check-equal? (column (read-csv commas #:separator #\; #:decimal-comma #t) "a") '(1.5 2.25))
  (define quoted-commas (scratch-file csv-dir "quoted-commas.csv" "a,b\n\"1,5\",x\n\"2,25\",y\n"))
  (check-equal? (column (read-csv quoted-commas #:decimal-comma #t) "a") '(1.5 2.25))
  (define preamble (scratch-file csv-dir "preamble.csv" "junk \"quoted\nstill junk\na,b\n1,x\n2,y\n3,z\n"))
  (check-equal? (rows-of (read-csv preamble #:skip-lines 2)) '((1 "x") (2 "y") (3 "z")))
  (check-regexp-match #rx"empty CSV" (message-of (lambda () (read-csv preamble #:skip-rows 2))))
  (check-equal? (rows-of (read-csv preamble #:skip-lines 2 #:skip-rows-after-header 1))
                '((2 "y") (3 "z")))
  (check-true (read-and-scan-agree preamble '((#:skip-lines . 2) (#:skip-rows-after-header . 1))))
  (define empty-file (scratch-file csv-dir "empty.csv" ""))
  (check-regexp-match #rx"^read-csv: failed to read csv from [^:]*empty.csv: no data: empty CSV$"
                      (message-of (lambda () (read-csv empty-file))))
  (check-equal? (shape (read-csv empty-file #:raise-if-empty #f)) '(0 0))
  (check-equal? (shape (collect (scan-csv empty-file #:raise-if-empty #f))) '(0 0))
  (define gaps (scratch-file csv-dir "gaps.csv" "a,b\n1,\n,x\n"))
  (check-equal? (column (read-csv gaps) "b") (list polars-null "x"))
  (check-equal? (column (read-csv gaps #:missing-utf8-is-empty-string #t) "b") '("" "x"))
  (check-equal? (column (read-csv gaps #:missing-utf8-is-empty-string #t) "a")
                (list 1 polars-null))
  (check-equal? (map second (dtypes-of (read-csv abc #:infer-schema #f #:null-values "NA")))
                '(string string string))
  (check-true (frame=? (read-csv abc #:infer-schema #f #:infer-schema-length 50)
                       (read-csv abc #:infer-schema-length 0)))

  (define stations (build-path data-dir "stations.csv"))
  (define station-frame
    (read-csv stations #:skip-lines 1 #:separator #\; #:decimal-comma #t
              #:null-values '(("temp" . "-") ("rain" . "n/a")) #:truncate-ragged-lines #t))
  (check-equal? (map second (dtypes-of station-frame)) '(string string string float64 float64 string))
  (check-equal? (rows-of (select station-frame "station" "temp" "rain" "note"))
                (list (list "Oslo" 12.5 0.0 "-") (list "Bergen" polars-null 3.2 polars-null)
                      (list "Tromso" 4.0 polars-null "cold") (list "Narvik" 3.5 1.0 "windy")))
  (check-equal? (column (read-csv stations #:skip-lines 1 #:separator #\; #:decimal-comma #t
                                  #:null-values '("-" "n/a") #:truncate-ragged-lines #t)
                        "note")
                (list polars-null polars-null "cold" "windy"))
  (check-equal? (column (read-csv stations #:skip-lines 1 #:separator #\; #:decimal-comma #t
                                  #:null-values '(("temp" . "-") ("rain" . "n/a"))
                                  #:truncate-ragged-lines #t #:missing-utf8-is-empty-string #t)
                        "note")
                '("-" "" "cold" "windy"))
  (define dated-stations
    (read-csv stations #:skip-lines 1 #:separator #\; #:decimal-comma #t
              #:null-values '(("temp" . "-") ("rain" . "n/a")) #:truncate-ragged-lines #t
              #:try-parse-dates #t))
  (check-equal? (map second (dtypes-of dated-stations)) '(string date time float64 float64 string))
  (define stations-out (build-path csv-dir "stations-out.csv"))
  (define (stations-written frame . kvs)
    (keyword-apply write-csv (map car kvs) (map cdr kvs) (list frame stations-out))
    (file->string stations-out))
  (check-equal? (stations-written dated-stations '(#:date-format . "%d.%m.%Y")
                                  '(#:decimal-comma . #t) '(#:null-value . "-")
                                  '(#:separator . #\;) '(#:time-format . "%H:%M"))
                "station;day;at;temp;rain;note\nOslo;01.05.2024;06:00;12,5;0,0;-\nBergen;01.05.2024;06:30;-;3,2;-\nTromso;02.05.2024;07:15;4,0;-;cold\nNarvik;02.05.2024;08:00;3,5;1,0;windy\n")
  (check-equal? (stations-written (select dated-stations "station" "temp")
                                  '(#:float-precision . 2))
                "station,temp\nOslo,12.50\nBergen,\nTromso,4.00\nNarvik,3.50\n")
  (check-equal? (stations-written (select dated-stations "station" "temp")
                                  '(#:float-precision . 2) '(#:quote-style . non-numeric))
                "\"station\",\"temp\"\n\"Oslo\",12.50\n\"Bergen\",\n\"Tromso\",4.00\n\"Narvik\",3.50\n")
  (check-equal? (stations-written (select dated-stations "station" "temp")
                                  '(#:float-scientific . #t))
                "station,temp\nOslo,1.25e1\nBergen,\nTromso,4e0\nNarvik,3.5e0\n")
  (check-equal? (stations-written (select dated-stations "station" "note")
                                  '(#:include-header . #f) '(#:line-terminator . "\r\n")
                                  '(#:quote-style . always))
                "\"Oslo\",\"-\"\r\n\"Bergen\",\"\"\r\n\"Tromso\",\"cold\"\r\n\"Narvik\",\"windy\"\r\n")
  (check-equal? (stations-written (select (read-csv flights #:separator #\tab #:null-values "NA"
                                                    #:try-parse-dates #t #:n-rows 3)
                                          "carrier" "flight" "time_hour")
                                  '(#:batch-size . 1) '(#:datetime-format . "%Y-%m-%dT%H:%M")
                                  '(#:include-bom . #t) '(#:quote-style . non-numeric))
                "﻿\"carrier\",\"flight\",\"time_hour\"\n\"UA\",1545,\"2013-01-01T05:00\"\n\"UA\",1714,\"2013-01-01T05:00\"\n\"AA\",1141,\"2013-01-01T05:00\"\n")
  (check-equal? (rows-of (read-csv flights #:separator #\tab #:null-values "NA"
                                   #:columns '("carrier" "flight" "dep_delay")
                                   #:row-index-name "row" #:n-rows 3))
                '((0 2 "UA" 1545) (1 4 "UA" 1714) (2 2 "AA" 1141)))
  (check-equal? (column-names (read-csv (build-path data-dir "parts" "part-1.csv")
                                        #:has-header #f #:skip-rows 1
                                        #:new-columns '("from" "to" "delay")))
                '("from" "to" "delay"))

  (define part-1 (build-path data-dir "parts" "part-1.csv"))
  (check-equal? (rows-of (read-csv flights #:separator #\tab #:null-values "NA"
                                   #:columns '("carrier" "flight" "dep_delay")
                                   #:row-index-name "row" #:row-index-offset 1 #:n-rows 3))
                '((1 2 "UA" 1545) (2 4 "UA" 1714) (3 2 "AA" 1141)))
  (check-equal? (column-names (read-csv flights #:separator #\tab #:columns '(9 10) #:n-rows 2))
                '("carrier" "flight"))
  (check-regexp-match #rx"projection index: 42 is out of bounds for csv schema with length: 19$"
                      (message-of (lambda () (read-csv flights #:separator #\tab
                                                       #:columns '(42)))))
  (check-regexp-match #rx"4 new column names for a file of 3 columns$"
                      (message-of (lambda () (read-csv part-1 #:new-columns '("a" "b" "c" "d")))))
  (check-regexp-match #rx"cannot add row_index with name 'origin'"
                      (message-of (lambda () (read-csv part-1 #:row-index-name "origin"))))
  (check-regexp-match #rx"found more fields than defined in 'Schema'"
                      (message-of (lambda () (read-csv stations #:skip-lines 1
                                                       #:separator #\;))))
  (check-regexp-match #rx"unable to find column \"temperature\""
                      (message-of (lambda () (read-csv stations #:skip-lines 1 #:separator #\;
                                                       #:null-values '(("temperature" . "-"))))))
  (check-equal? (rows-of (read-csv part-1 #:skip-rows-after-header 1)) '(("LGA" "IAH" 4)))
  (check-equal? (~> (read-csv flights #:separator #\tab #:infer-schema #f)
                    (ref #:columns "year")
                    dtype)
                'string)
  (check-equal? (rows-of (~> (scan-csv part-1 #:new-columns '("from" "to") #:row-index-name "row")
                             (frame-filter (gt (col "dep_delay") 3))
                             collect))
                '((1 "LGA" "IAH" 4)))

  (define compressed (build-path data-dir "compressed"))
  (define part-1-frame (read-csv part-1))
  (define zlib-looking (scratch-file csv-dir "zlib-looking.csv" "x^2,y\n1,2\n3,4\n"))
  (define tiny-zlib-looking (scratch-file csv-dir "tiny-zlib-looking.csv" "x^\n1\n"))
  (define bom-first (scratch-file csv-dir "bom-first.csv" "﻿x^2,y\n1,2\n3,4\n"))
  (define (scan-message path)
    (message-of (lambda () (collect (scan-csv path)))))
  (for ([ext '("gz" "zlib" "zst")])
    (define path (build-path compressed (string-append "part-1.csv." ext)))
    (check-true (frame=? (read-csv path) part-1-frame) ext)
    (check-true (frame=? (collect (scan-csv path)) part-1-frame) ext)
    (check-equal? (rows-of (read-csv path #:n-rows 1)) '(("EWR" "IAH" 2)) ext)
    (check-equal? (column-names (read-csv path #:new-columns '("from"))) '("from" "dest" "dep_delay")
                  ext)
    (check-equal? (column-names (collect (scan-csv path #:new-columns '("from"))))
                  '("from" "dest" "dep_delay")
                  ext))
  (check-regexp-match #rx"^read-csv: failed to read csv from [^:]*zlib-looking.csv: .*corrupt deflate stream"
                      (message-of (lambda () (read-csv zlib-looking))))
  (check-regexp-match #rx"corrupt deflate stream" (scan-message zlib-looking))
  (check-regexp-match #rx"^read-csv: failed to read csv from [^:]*tiny-zlib-looking.csv: incomplete deflate stream$"
                      (message-of (lambda () (read-csv tiny-zlib-looking))))
  (check-equal? (rows-of (read-csv bom-first)) '((1 2) (3 4)))
  (check-equal? (column-names (read-csv bom-first)) '("x^2" "y"))
  (check-true (frame=? (read-csv bom-first) (collect (scan-csv bom-first))))

  (check-regexp-match #rx"reads as one column"
                      (message-of (lambda () (read-csv flights #:row-index-name "i"))))
  (check-equal? (shape (read-csv flights #:new-columns '("line"))) '(102 1))
  (define semicolon-name (scratch-file csv-dir "semicolon-name.csv" "a;b,c\n1;2,3\n"))
  (for ([columns '(("a;b") (0))])
    (check-equal? (rows-of (read-csv semicolon-name #:columns columns)) '(("1;2")))
    (check-equal? (column-names (read-csv semicolon-name #:columns columns)) '("a;b")))
  (define semicolons (scratch-file csv-dir "semicolons.csv" "a;b\n1;2\n"))
  (check-regexp-match #rx"reads as one column" (message-of (lambda () (read-csv semicolons))))
  (check-equal? (rows-of (read-csv semicolons #:columns '("a;b"))) '(("1;2")))

  (define size-max (sub1 (expt 2 64)))
  (define (read-message kw value)
    (message-of (lambda () (apply-keywords contracted:read-csv (list (cons kw value)) abc))))
  (for* ([kw '(#:skip-rows #:skip-lines #:skip-rows-after-header #:n-rows #:infer-schema-length)]
         [value (list (expt 2 64) (add1 (expt 2 64)))])
    (check-exn (contract-violation-of 'read-csv)
               (lambda () (apply-keywords contracted:read-csv (list (cons kw value)) abc))
               (format "~a" kw)))
  (check-exn (contract-violation-of 'read-csv)
             (lambda () (contracted:read-csv abc #:columns (list (expt 2 64)))))
  (check-regexp-match #rx"^read-csv: failed to read csv from [^:]*abc.csv: projection index: 18446744073709551615 is out of bounds for csv schema with length: 3$"
                      (read-message '#:columns (list size-max)))
  (check-regexp-match #rx"^read-csv: failed to read csv from [^:]*abc.csv: no data: specified skip_lines is larger than total number of lines\\.$"
                      (read-message '#:skip-lines size-max))
  (check-regexp-match #rx"^read-csv: failed to read csv from [^:]*abc.csv: no data: empty CSV$"
                      (read-message '#:skip-rows size-max))
  (check-equal? (shape (read-csv abc #:skip-rows-after-header size-max)) '(0 3))
  (check-equal? (shape (read-csv abc #:n-rows size-max)) '(3 3))

  (define oracle-source
    (scratch-file csv-dir "write-oracle.csv"
              (string-append
               "i,f,s,d,t,h,b\n"
               "1,1.5,\"a,b\",2024-01-02,2024-01-02 03:04:05.006,05:06:07,true\n"
               ",1e-10,\"q\"\"t\",,,,false\n"
               "3,12345678.9,,2024-12-31,2024-12-31 00:00:00,23:59:59.999999,\n")))
  (define oracle-frame (read-csv oracle-source #:try-parse-dates #t))
  (check-equal? (map second (dtypes-of oracle-frame))
                '(int64 float64 string date (datetime microseconds #f) time boolean))
  (define written-path (build-path csv-dir "written.csv"))
  (define (written kvs)
    (apply-keywords write-csv kvs oracle-frame written-path)
    (file->string written-path))
  (define python-1.42.1-write-csv
    '((()
       "i,f,s,d,t,h,b\n1,1.5,\"a,b\",2024-01-02,2024-01-02T03:04:05.006000,05:06:07.000000000,true\n,1e-10,\"q\"\"t\",,,,false\n3,12345678.9,,2024-12-31,2024-12-31T00:00:00.000000,23:59:59.999999000,\n")
      (((#:include-header . #f))
       "1,1.5,\"a,b\",2024-01-02,2024-01-02T03:04:05.006000,05:06:07.000000000,true\n,1e-10,\"q\"\"t\",,,,false\n3,12345678.9,,2024-12-31,2024-12-31T00:00:00.000000,23:59:59.999999000,\n")
      (((#:include-bom . #t))
       "\ufeffi,f,s,d,t,h,b\n1,1.5,\"a,b\",2024-01-02,2024-01-02T03:04:05.006000,05:06:07.000000000,true\n,1e-10,\"q\"\"t\",,,,false\n3,12345678.9,,2024-12-31,2024-12-31T00:00:00.000000,23:59:59.999999000,\n")
      (((#:separator . #\;))
       "i;f;s;d;t;h;b\n1;1.5;a,b;2024-01-02;2024-01-02T03:04:05.006000;05:06:07.000000000;true\n;1e-10;\"q\"\"t\";;;;false\n3;12345678.9;;2024-12-31;2024-12-31T00:00:00.000000;23:59:59.999999000;\n")
      (((#:line-terminator . "\r\n"))
       "i,f,s,d,t,h,b\r\n1,1.5,\"a,b\",2024-01-02,2024-01-02T03:04:05.006000,05:06:07.000000000,true\r\n,1e-10,\"q\"\"t\",,,,false\r\n3,12345678.9,,2024-12-31,2024-12-31T00:00:00.000000,23:59:59.999999000,\r\n")
      (((#:quote-char . #\'))
       "i,f,s,d,t,h,b\n1,1.5,'a,b',2024-01-02,2024-01-02T03:04:05.006000,05:06:07.000000000,true\n,1e-10,q\"t,,,,false\n3,12345678.9,,2024-12-31,2024-12-31T00:00:00.000000,23:59:59.999999000,\n")
      (((#:quote-style . always))
       "\"i\",\"f\",\"s\",\"d\",\"t\",\"h\",\"b\"\n\"1\",\"1.5\",\"a,b\",\"2024-01-02\",\"2024-01-02T03:04:05.006000\",\"05:06:07.000000000\",\"true\"\n\"\",\"1e-10\",\"q\"\"t\",\"\",\"\",\"\",\"false\"\n\"3\",\"12345678.9\",\"\",\"2024-12-31\",\"2024-12-31T00:00:00.000000\",\"23:59:59.999999000\",\"\"\n")
      (((#:quote-style . non-numeric))
       "\"i\",\"f\",\"s\",\"d\",\"t\",\"h\",\"b\"\n1,1.5,\"a,b\",\"2024-01-02\",\"2024-01-02T03:04:05.006000\",\"05:06:07.000000000\",\"true\"\n,1e-10,\"q\"\"t\",,,,\"false\"\n3,12345678.9,,\"2024-12-31\",\"2024-12-31T00:00:00.000000\",\"23:59:59.999999000\",\n")
      (((#:quote-style . never))
       "i,f,s,d,t,h,b\n1,1.5,a,b,2024-01-02,2024-01-02T03:04:05.006000,05:06:07.000000000,true\n,1e-10,q\"t,,,,false\n3,12345678.9,,2024-12-31,2024-12-31T00:00:00.000000,23:59:59.999999000,\n")
      (((#:batch-size . 1))
       "i,f,s,d,t,h,b\n1,1.5,\"a,b\",2024-01-02,2024-01-02T03:04:05.006000,05:06:07.000000000,true\n,1e-10,\"q\"\"t\",,,,false\n3,12345678.9,,2024-12-31,2024-12-31T00:00:00.000000,23:59:59.999999000,\n")
      (((#:datetime-format . "%Y/%m/%d %H:%M") (#:date-format . "%d.%m.%Y")
        (#:time-format . "%H-%M"))
       "i,f,s,d,t,h,b\n1,1.5,\"a,b\",02.01.2024,2024/01/02 03:04,05-06,true\n,1e-10,\"q\"\"t\",,,,false\n3,12345678.9,,31.12.2024,2024/12/31 00:00,23-59,\n")
      (((#:float-scientific . #t))
       "i,f,s,d,t,h,b\n1,1.5e0,\"a,b\",2024-01-02,2024-01-02T03:04:05.006000,05:06:07.000000000,true\n,1e-10,\"q\"\"t\",,,,false\n3,1.23456789e7,,2024-12-31,2024-12-31T00:00:00.000000,23:59:59.999999000,\n")
      (((#:float-scientific . #f))
       "i,f,s,d,t,h,b\n1,1.5,\"a,b\",2024-01-02,2024-01-02T03:04:05.006000,05:06:07.000000000,true\n,0.0000000001,\"q\"\"t\",,,,false\n3,12345678.9,,2024-12-31,2024-12-31T00:00:00.000000,23:59:59.999999000,\n")
      (((#:float-precision . 2))
       "i,f,s,d,t,h,b\n1,1.50,\"a,b\",2024-01-02,2024-01-02T03:04:05.006000,05:06:07.000000000,true\n,0.00,\"q\"\"t\",,,,false\n3,12345678.90,,2024-12-31,2024-12-31T00:00:00.000000,23:59:59.999999000,\n")
      (((#:float-precision . 2) (#:float-scientific . #t))
       "i,f,s,d,t,h,b\n1,1.50e0,\"a,b\",2024-01-02,2024-01-02T03:04:05.006000,05:06:07.000000000,true\n,1.00e-10,\"q\"\"t\",,,,false\n3,1.23e7,,2024-12-31,2024-12-31T00:00:00.000000,23:59:59.999999000,\n")
      (((#:decimal-comma . #t))
       "i,f,s,d,t,h,b\n1,\"1,5\",\"a,b\",2024-01-02,2024-01-02T03:04:05.006000,05:06:07.000000000,true\n,\"1e-10\",\"q\"\"t\",,,,false\n3,\"12345678,9\",,2024-12-31,2024-12-31T00:00:00.000000,23:59:59.999999000,\n")
      (((#:decimal-comma . #t) (#:separator . #\;))
       "i;f;s;d;t;h;b\n1;1,5;a,b;2024-01-02;2024-01-02T03:04:05.006000;05:06:07.000000000;true\n;1e-10;\"q\"\"t\";;;;false\n3;12345678,9;;2024-12-31;2024-12-31T00:00:00.000000;23:59:59.999999000;\n")
      (((#:null-value . "NA"))
       "i,f,s,d,t,h,b\n1,1.5,\"a,b\",2024-01-02,2024-01-02T03:04:05.006000,05:06:07.000000000,true\nNA,1e-10,\"q\"\"t\",NA,NA,NA,false\n3,12345678.9,NA,2024-12-31,2024-12-31T00:00:00.000000,23:59:59.999999000,NA\n")))
  (for ([case (in-list python-1.42.1-write-csv)])
    (check-equal? (written (car case)) (cadr case) (format "~s" (car case))))
  (check-equal? (written '((#:float-scientific . auto) (#:quote-style . necessary)
                           (#:null-value . "")))
                (written '()))
  (for ([batch-size (list 2 3 4 (expt 2 32) size-max)])
    (check-equal? (written `((#:batch-size . ,batch-size))) (written '()) (format "~a" batch-size)))
  (define precise (written '((#:float-precision . 65535))))
  (check-equal? (string-length precise) (+ (string-length (written '((#:float-precision . 0))))
                                           (* 3 65536)))
  (for ([kv '((#:datetime-format . "%Q") (#:date-format . "%H") (#:time-format . "%Y"))]
        [cause '("cannot format NaiveDateTime with format '%Q'"
                 "cannot format NaiveDate with format '%H'"
                 "cannot format NaiveTime with format '%Y'")])
    (check-regexp-match (regexp (string-append "^write-csv: failed to write csv to [^:]*written.csv: "
                                               (regexp-quote cause) "$"))
                        (message-of (lambda () (written (list kv))))))
  (check-regexp-match #rx"^write-csv: failed to write csv to [^:]*out.csv: cannot create file: "
                      (message-of (lambda () (write-csv oracle-frame
                                                        (build-path csv-dir "no" "out.csv")))))
  (define round-trip (build-path csv-dir "round-trip.csv"))
  (write-csv station-frame round-trip #:separator #\; #:decimal-comma #t #:null-value "n/a"
             #:quote-style 'always)
  (check-true (frame=? (read-csv round-trip #:separator #\; #:decimal-comma #t
                                 #:null-values "n/a")
                       station-frame))
  (for ([kv `((#:separator . ";") (#:separator . #\newline) (#:quote-char . #\é)
              (#:quote-style . non_numeric) (#:batch-size . 0) (#:float-scientific . yes)
              (#:float-precision . -1) (#:null-value . #f) (#:line-terminator . #\newline)
              (#:datetime-format . sym) (#:include-header . 1) (#:include-bom . "no")
              (#:decimal-comma . 1) (#:batch-size . ,(expt 2 64))
              (#:batch-size . ,(add1 (expt 2 64))) (#:float-precision . 65536)
              (#:float-precision . ,(expt 2 64)))])
    (check-exn (contract-violation-of 'write-csv)
               (lambda () (keyword-apply contracted:write-csv (list (car kv)) (list (cdr kv))
                                         (list oracle-frame round-trip)))
               (format "~s" kv)))
  (check-exn #rx"quote-char must differ from the separator"
             (lambda () (contracted:write-csv oracle-frame round-trip
                                              #:separator #\; #:quote-char #\;)))
  (check-exn #rx"quote-char must differ from the separator"
             (lambda () (contracted:write-csv oracle-frame round-trip #:quote-char #\,)))

  (define keep (scratch-file csv-dir "keep.csv" "PRECIOUS"))
  (check-exn #rx"^write-csv: failed to write csv to [^:]*keep.csv: cannot format NaiveDate with format '%H'$"
             (lambda () (write-csv oracle-frame keep #:date-format "%H")))
  (check-equal? (file->string keep) "PRECIOUS")
  (check-equal? (staging-files csv-dir) '())
  (check-staged-write write-csv "csv" oracle-frame)

  (delete-directory/files csv-dir))
