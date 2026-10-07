#lang racket/base

(require (only-in racket/contract/base -> ->* contract-out or/c)
         (only-in polars/private/csv
                  csv-reader csv-reader/c csv-scanner csv-scanner/c csv-writer csv-writer/c)
         (only-in polars/private/expr lazyframe-scan-parquet)
         (only-in polars/private/foreign
                  dataframe-read-json-lines dataframe-read-parquet
                  dataframe-write-json-lines dataframe-write-parquet)
         (only-in polars/private/generic/core
                  dataframe? lazyframe? wrap-dataframe wrap-lazyframe)
         syntax/parse/define)

(provide (contract-out
          [read-csv (csv-reader/c dataframe?)]
          [scan-csv (csv-scanner/c lazyframe?)]
          [read-parquet (-> path-string? dataframe?)]
          [scan-parquet (->* (path-string?)
                             (#:n-rows (or/c #f exact-nonnegative-integer?))
                             lazyframe?)]
          [read-ndjson (-> path-string? dataframe?)]
          [write-csv (csv-writer/c dataframe?)]
          [write-parquet (-> dataframe? path-string? void?)]
          [write-ndjson (-> dataframe? path-string? void?)]))

(define-syntax-parse-rule (define-wrapped name:id wrap:expr reader:expr)
  (define name (procedure-rename (compose1 wrap reader) 'name)))

(define-wrapped read-csv wrap-dataframe (csv-reader 'read-csv))
(define-wrapped scan-csv wrap-lazyframe (csv-scanner 'scan-csv))
(define-wrapped read-parquet wrap-dataframe dataframe-read-parquet)
(define-wrapped scan-parquet wrap-lazyframe lazyframe-scan-parquet)
(define-wrapped read-ndjson wrap-dataframe dataframe-read-json-lines)
(define write-csv (procedure-rename (csv-writer 'write-csv) 'write-csv))
(define write-parquet dataframe-write-parquet)
(define write-ndjson dataframe-write-json-lines)

(module+ test
  (require rackunit
           racket/file
           racket/runtime-path
           (only-in racket/contract exn:fail:contract:blame?)
           (only-in racket/list last remove-duplicates)
           (only-in racket/sequence sequence->list)
           (only-in racket/string string-contains?)
           (only-in polars/private/bulk in-series series->list)
           (only-in threading ~>)
           (only-in gregor datetime)
           (prefix-in contracted: (submod ".."))
           (prefix-in raw: polars/private/csv)
           (only-in polars/private/generic/core
                    column-names dataframe dtype height null-count ref series shape)
           (only-in polars/private/generic/printing series->string)
           (only-in polars/private/generic/reshape collect)
           polars/private/generic/test-fixtures)

  (define-runtime-path data-dir "../../scribblings/data")
  (define flights (build-path data-dir "flights.tsv"))
  (define scratch (make-temporary-directory "rkt-polars-io-~a"))
  (define (scratch-file name . lines)
    (define path (build-path scratch name))
    (make-parent-directory* path)
    (display-lines-to-file lines path #:exists 'replace)
    path)

  (define (with-keywords f path kvs)
    (define sorted (sort kvs keyword<? #:key car))
    (keyword-apply f (map car sorted) (map cdr sorted) (list path)))

  (define (message-of thunk)
    (with-handlers ([exn:fail? exn-message]) (thunk) #f))

  (define (cause-of message)
    (last (regexp-match #rx"^[^:]*: [^:]*: ([^\n]*)" message)))

  (define (read-and-scan-agree path kvs)
    (define eager
      (with-handlers ([exn:fail? exn-message]) (with-keywords read-csv path kvs)))
    (define lazy
      (with-handlers ([exn:fail? exn-message]) (collect (with-keywords scan-csv path kvs))))
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
    (define blamed (regexp (format "^~a: contract violation" name)))
    (check-exn blamed (lambda () (reader 'sym)))
    (for ([kvs (in-list (append (map list bad-keywords) bad-together))])
      (check-exn (lambda (e) (and (exn:fail:contract:blame? e)
                                  (regexp-match? blamed (exn-message e))))
                 (lambda () (with-keywords reader missing kvs))
                 (format "~a ~s" name kvs))))
  (for ([reader (list contracted:read-csv raw:dataframe-read-csv)]
        [name '(read-csv dataframe-read-csv)]
        #:when #t
        [kv (in-list bad-columns)])
    (check-exn (regexp (format "^~a: contract violation" name))
               (lambda () (with-keywords reader missing (list kv)))
               (format "~a ~s" name kv)))
  (for ([reader (list contracted:scan-csv raw:lazyframe-scan-csv)])
    (check-exn #rx"does not expect an argument with given keyword\n.*given keyword: #:columns"
               (lambda () (reader missing #:columns '("a")))))
  (check-exn #rx"eol-char must differ from the separator and quote-char"
             (lambda () (contracted:read-csv missing #:separator #\; #:eol-char #\;)))
  (check-exn #rx"only one of skip-rows and skip-lines may be set"
             (lambda () (contracted:scan-csv missing #:skip-rows 1 #:skip-lines 2)))
  (check-exn #rx"^write-csv: contract violation" (lambda () (contracted:write-csv 5 "x")))

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
  (define primed (scratch-file "primed.csv" "a;b" "'x;y';1" "z;2"))
  (check-equal? (column (read-csv primed #:separator #\; #:quote-char #\') "a") '("x;y" "z"))

  (define (dtypes-of df)
    (map (lambda (name) (dtype (ref df #:columns name))) (column-names df)))
  (check-equal? (remove-duplicates
                 (dtypes-of (read-csv flights #:separator #\tab #:infer-schema-length 0)))
                '(string))
  (define all-rows (read-csv flights #:separator #\tab #:infer-schema-length #f))
  (check-equal? (for/list ([name (column-names all-rows)]
                           [type (dtypes-of all-rows)]
                           #:when (eq? type 'string))
                  name)
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

  (define ab (scratch-file "ab.csv" "a,b" "1,2"))
  (define absent '(("a" . int64) ("zzz" . float32)))
  (check-exn
   #rx"^read-csv: failed to read csv from [^:]*ab.csv: schema overrides name columns not in the file: \"zzz\"$"
   (lambda () (read-csv ab #:schema-overrides absent)))
  (check-exn
   #rx"^scan-csv: failed to scan [^:]*ab.csv: schema overrides name columns not in the file: \"zzz\"$"
   (lambda () (scan-csv ab #:schema-overrides absent)))

  (define typed
    (scratch-file
     "typed.csv"
     "i8,i16,i32,i64,u8,u16,u32,u64,f32,f64,b,s,d,dt,dtms"
     "1,2,3,4,5,6,7,8,1.5,2.5,true,x,2020-01-02,2020-01-02 03:04:05,2020-01-02 03:04:05"))
  (define typed-frame
    (read-csv typed
              #:schema-overrides
              '(("i8" . i8) ("i16" . i16) ("i32" . i32) ("i64" . i64) ("u8" . u8)
                ("u16" . u16) ("u32" . u32) ("u64" . u64) ("f32" . f32) ("f64" . f64)
                ("b" . bool) ("s" . str) ("d" . date) ("dt" . datetime)
                ("dtms" . (datetime milliseconds)))))
  (check-equal? (dtypes-of typed-frame)
                '(int8 int16 int32 int64 uint8 uint16 uint32 uint64 float32 float64
                  boolean string date (datetime microseconds #f)
                  (datetime milliseconds #f)))
  (check-equal? (column typed-frame "dt") (list (datetime 2020 1 2 3 4 5)))

  (define dated (scratch-file "dated.csv" "d,t,ts" "2020-01-02,05:00:00,2013-01-01 05:00:00"))
  (define parsed (read-csv dated #:try-parse-dates #t))
  (check-equal? (dtypes-of parsed) '(date time (datetime microseconds #f)))
  (check-equal? (column parsed "ts") (list (datetime 2013 1 1 5)))
  (define clocked (scratch-file "clocked.csv" "t" "05:00:00" "06:30:15"))
  (define clocked-frame (read-csv clocked #:schema-overrides '(("t" . time))))
  (check-equal? (dtypes-of clocked-frame) '(time))
  (check-true (frame=? clocked-frame (read-csv clocked #:try-parse-dates #t)))
  (check-equal? (~> (read-csv flights #:separator #\tab #:null-values "NA" #:try-parse-dates #t)
                    (ref #:columns "time_hour")
                    dtype)
                '(datetime microseconds #f))

  (define quoted (scratch-file "quoted.csv" "a,b" "\"1,5\",x" "\"2\",y"))
  (check-equal? (column (read-csv quoted) "a") '("1,5" "2"))
  (check-exn #rx"found more fields than defined" (lambda () (read-csv quoted #:quote-char #f)))
  (define commented (scratch-file "commented.csv" "# note" "a,b" "1,2" "# mid" "3,4"))
  (check-equal? (shape (read-csv commented #:comment-prefix "#")) '(2 2))
  (check-equal? (column (read-csv commented #:comment-prefix "#") "a") '(1 3))
  (define slashed (scratch-file "slashed.csv" "x" "//skip" "1"))
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
    (scratch-file (format "globbed/~a.csv" name) "x" (number->string value))
    (write-parquet (dataframe (list (series (list value) #:name "x")))
                   (build-path scratch "globbed" (format "~a.parquet" name))))
  (void (scratch-file "globbed/skip.txt" "x" "99"))
  (define csv-pattern (build-path scratch "globbed" "*.csv"))
  (define parquet-pattern (build-path scratch "globbed" "*.parquet"))
  (check-equal? (column (read-csv csv-pattern) "x") '(1 2 3))
  (check-equal? (~> csv-pattern scan-csv collect (column "x")) '(1 2 3))
  (check-equal? (column (read-parquet parquet-pattern) "x") '(1 2 3))
  (check-equal? (~> parquet-pattern scan-parquet collect (column "x")) '(1 2 3))

  (for ([name '("p0" "p1" "p2")] [rows '(("5" "6") ("1" "2") ("3" "4"))])
    (apply scratch-file (format "ordered/~a.csv" name) "x" rows))
  (define ordered (build-path scratch "ordered" "p*.csv"))
  (check-equal? (column (read-csv ordered) "x") '(5 6 1 2 3 4))
  (check-equal? (column (read-csv ordered #:n-rows 3) "x") '(5 6 1))
  (check-equal? (column (read-csv ordered #:skip-rows 1 #:has-header #f) "column_1")
                '(5 6 1 2 3 4))

  (void (scratch-file "mixed/a.csv" "x" "1")
        (scratch-file "mixed/b.csv" "y" "2"))
  (check-exn #rx"^read-csv: " (lambda () (read-csv (build-path scratch "mixed" "*.csv"))))

  (define nothing (build-path scratch "globbed" "*.none"))
  (check-pred lazyframe? (scan-csv nothing))
  (check-pred lazyframe? (scan-parquet nothing))
  (for ([thunk (list (lambda () (read-csv nothing))
                     (lambda () (collect (scan-csv nothing)))
                     (lambda () (read-parquet nothing))
                     (lambda () (collect (scan-parquet nothing))))])
    (check-exn #rx": no files match the pattern$" thunk))

  (void (scratch-file "literal/a1.csv" "x" "1"))
  (define bracketed (scratch-file "literal/a[1].csv" "x" "2"))
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

  (void (scratch-file "dirmix/a.csv" "x" "1")
        (scratch-file "dirmix/notes.txt" "x" "99"))
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
    (define eager (outcome (lambda () (with-keywords read-csv path kvs))))
    (and (same-outcome? eager (outcome (lambda () (with-keywords read-csv (one-file-pattern path)
                                                                  globbed))))
         (same-outcome? eager (outcome (lambda () (collect (with-keywords scan-csv path kvs)))))))
  (define semi (scratch-file "semi-opts.txt" "# note" "a;b" "'x;y';1" "# mid" "z;2"))
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
                      (guard-message (scratch-file "semi.csv" "a;b" "1;2")))
  (check-regexp-match #rx"pass #:separator #\\\\\\|"
                      (guard-message (scratch-file "pipe.csv" "a|b" "1|2")))
  (check-regexp-match #rx"pass #:separator #\\\\;"
                      (guard-message (scratch-file "header-only.csv" "a;b")))
  (define ambiguous (scratch-file "ambiguous.csv" "k;v" "x;y"))
  (check-regexp-match #rx"reads as one column" (guard-message ambiguous))
  (check-equal? (shape (read-csv ambiguous #:separator #\,)) '(1 1))
  (for ([genuine (list (scratch-file "names.csv" "name" "alice" "bob")
                       (scratch-file "titled.csv" "Name; Title" "Bob")
                       (scratch-file "number.csv" "a|b" "12"))])
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
  (define frame-ndjson (build-path scratch "frame.ndjson"))
  (write-ndjson frame frame-ndjson)
  (check-equal? (shape (read-ndjson frame-ndjson)) '(3 3))

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

  (define levels (scratch-file "levels.csv" "level,n" "info,1" "debug,2" "info,3"))
  (define as-categorical (read-csv levels #:schema-overrides '(("level" . categorical))))
  (check-equal? (dtype (ref as-categorical "level")) 'categorical)
  (check-equal? (column as-categorical "level") '(info debug info))

  (delete-directory/files scratch))

(module+ test
  (require (only-in polars/private/generic/reshape select [filter frame-filter])
           (only-in polars/private/generic/operators [> gt]))
  (define csv-dir (make-temporary-directory "rkt-polars-csv-options-~a"))
  (define (csv-file name contents)
    (define path (build-path csv-dir name))
    (call-with-output-file path #:exists 'replace
      (lambda (out) (void (write-string contents out))))
    path)
  (define (rows-of df)
    (for/list ([i (in-range (height df))])
      (for/list ([name (in-list (column-names df))]) (list-ref (column df name) i))))

  (define abc (csv-file "abc.csv" "a,b,c\n1,NA,x\nNA,2,-\n3,4,y\n"))
  (define abc-pattern (build-path csv-dir "[a]bc.csv"))

  (define a-only (read-csv abc #:null-values '(("a" . "NA"))))
  (check-equal? (dtypes-of a-only) '(int64 string string))
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
  (check-equal? (dtypes-of renamed-typed) '(float64 string string))
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

  (define eol (csv-file "eol.csv" "a,b;1,x;2,y;"))
  (check-equal? (rows-of (read-csv eol #:eol-char #\;)) '((1 "x") (2 "y")))
  (check-true (read-and-scan-agree eol '((#:eol-char . #\;))))
  (define ragged (csv-file "ragged.csv" "a,b\n1,x\n2,y,extra\n3\n"))
  (check-regexp-match #rx"found more fields than defined in 'Schema'\n\nConsider setting #:truncate-ragged-lines #t\\.$"
                      (message-of (lambda () (read-csv ragged))))
  (check-equal? (rows-of (read-csv ragged #:truncate-ragged-lines #t))
                (list '(1 "x") '(2 "y") (list 3 polars-null)))
  (check-true (read-and-scan-agree ragged '((#:truncate-ragged-lines . #t))))
  (define commas (csv-file "commas.csv" "a;b\n1,5;x\n2,25;y\n"))
  (check-equal? (column (read-csv commas #:separator #\;) "a") '("1,5" "2,25"))
  (check-equal? (column (read-csv commas #:separator #\; #:decimal-comma #t) "a") '(1.5 2.25))
  (define quoted-commas (csv-file "quoted-commas.csv" "a,b\n\"1,5\",x\n\"2,25\",y\n"))
  (check-equal? (column (read-csv quoted-commas #:decimal-comma #t) "a") '(1.5 2.25))
  (define preamble (csv-file "preamble.csv" "junk \"quoted\nstill junk\na,b\n1,x\n2,y\n3,z\n"))
  (check-equal? (rows-of (read-csv preamble #:skip-lines 2)) '((1 "x") (2 "y") (3 "z")))
  (check-regexp-match #rx"empty CSV" (message-of (lambda () (read-csv preamble #:skip-rows 2))))
  (check-equal? (rows-of (read-csv preamble #:skip-lines 2 #:skip-rows-after-header 1))
                '((2 "y") (3 "z")))
  (check-true (read-and-scan-agree preamble '((#:skip-lines . 2) (#:skip-rows-after-header . 1))))
  (define empty-file (csv-file "empty.csv" ""))
  (check-regexp-match #rx"^read-csv: failed to read csv from [^:]*empty.csv: no data: empty CSV$"
                      (message-of (lambda () (read-csv empty-file))))
  (check-equal? (shape (read-csv empty-file #:raise-if-empty #f)) '(0 0))
  (check-equal? (shape (collect (scan-csv empty-file #:raise-if-empty #f))) '(0 0))
  (define gaps (csv-file "gaps.csv" "a,b\n1,\n,x\n"))
  (check-equal? (column (read-csv gaps) "b") (list polars-null "x"))
  (check-equal? (column (read-csv gaps #:missing-utf8-is-empty-string #t) "b") '("" "x"))
  (check-equal? (column (read-csv gaps #:missing-utf8-is-empty-string #t) "a")
                (list 1 polars-null))
  (check-equal? (dtypes-of (read-csv abc #:infer-schema #f #:null-values "NA"))
                '(string string string))
  (check-true (frame=? (read-csv abc #:infer-schema #f #:infer-schema-length 50)
                       (read-csv abc #:infer-schema-length 0)))

  (define stations (build-path data-dir "stations.csv"))
  (define station-frame
    (read-csv stations #:skip-lines 1 #:separator #\; #:decimal-comma #t
              #:null-values '(("temp" . "-") ("rain" . "n/a")) #:truncate-ragged-lines #t))
  (check-equal? (dtypes-of station-frame) '(string string string float64 float64 string))
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
  (check-equal? (dtypes-of dated-stations) '(string date time float64 float64 string))
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
  (define decompress?
    (not (message-of (lambda () (read-csv (build-path compressed "part-1.csv.gz"))))))
  (define zlib-looking (csv-file "zlib-looking.csv" "x^2,y\n1,2\n3,4\n"))
  (define tiny-zlib-looking (csv-file "tiny-zlib-looking.csv" "x^\n1\n"))
  (define bom-first (csv-file "bom-first.csv" "﻿x^2,y\n1,2\n3,4\n"))
  (define (scan-message path)
    (message-of (lambda () (collect (scan-csv path)))))
  (cond
    [decompress?
     (for ([ext '("gz" "zlib" "zst")])
       (define path (build-path compressed (string-append "part-1.csv." ext)))
       (check-true (frame=? (read-csv path) part-1-frame) ext)
       (check-true (frame=? (collect (scan-csv path)) part-1-frame) ext)
       (check-equal? (rows-of (read-csv path #:n-rows 1)) '(("EWR" "IAH" 2)) ext))
     (check-regexp-match #rx"^read-csv: failed to read csv from [^:]*zlib-looking.csv: .*corrupt deflate stream"
                         (message-of (lambda () (read-csv zlib-looking))))
     (check-regexp-match #rx"corrupt deflate stream" (scan-message zlib-looking))
     (check-equal? (shape (read-csv tiny-zlib-looking)) '(0 1))
     (check-false (equal? (column-names (read-csv tiny-zlib-looking)) '("x^")))]
    [else
     (for ([path (list (build-path compressed "part-1.csv.gz") (build-path compressed "part-1.csv.zlib")
                       (build-path compressed "part-1.csv.zst") zlib-looking tiny-zlib-looking)])
       (check-regexp-match #rx"^read-csv: failed to read csv from [^:]*: cannot read compressed CSV file; compile with feature 'decompress'$"
                           (message-of (lambda () (read-csv path))))
       (check-regexp-match #rx"^lazyframe-collect: failed to collect the query: polars panicked: activate 'decompress' feature$"
                           (scan-message path))
       (check-regexp-match #rx"^scan-csv: failed to scan [^:]*: polars panicked: activate 'decompress' feature$"
                           (message-of (lambda () (scan-csv path #:schema-overrides '(("y" . str)))))))])
  (check-equal? (rows-of (read-csv bom-first)) '((1 2) (3 4)))
  (check-equal? (column-names (read-csv bom-first)) '("x^2" "y"))
  (check-true (frame=? (read-csv bom-first) (collect (scan-csv bom-first))))

  (check-regexp-match #rx"reads as one column"
                      (message-of (lambda () (read-csv flights #:row-index-name "i"))))
  (check-equal? (shape (read-csv flights #:new-columns '("line"))) '(102 1))

  (define oracle-source
    (csv-file "write-oracle.csv"
              (string-append
               "i,f,s,d,t,h,b\n"
               "1,1.5,\"a,b\",2024-01-02,2024-01-02 03:04:05.006,05:06:07,true\n"
               ",1e-10,\"q\"\"t\",,,,false\n"
               "3,12345678.9,,2024-12-31,2024-12-31 00:00:00,23:59:59.999999,\n")))
  (define oracle-frame (read-csv oracle-source #:try-parse-dates #t))
  (check-equal? (dtypes-of oracle-frame)
                '(int64 float64 string date (datetime microseconds #f) time boolean))
  (define written-path (build-path csv-dir "written.csv"))
  (define (written kvs)
    (define sorted (sort kvs keyword<? #:key car))
    (keyword-apply write-csv (map car sorted) (map cdr sorted) (list oracle-frame written-path))
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
              (#:decimal-comma . 1))])
    (check-exn #rx"^write-csv: contract violation"
               (lambda () (keyword-apply contracted:write-csv (list (car kv)) (list (cdr kv))
                                         (list oracle-frame round-trip)))
               (format "~s" kv)))
  (check-exn #rx"quote-char must differ from the separator"
             (lambda () (contracted:write-csv oracle-frame round-trip
                                              #:separator #\; #:quote-char #\;)))
  (check-exn #rx"quote-char must differ from the separator"
             (lambda () (contracted:write-csv oracle-frame round-trip #:quote-char #\,)))

  (delete-directory/files csv-dir))
