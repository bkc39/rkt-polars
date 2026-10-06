#lang racket/base

(require (only-in racket/contract/base -> ->* contract-out or/c)
         (only-in polars/private/csv csv-reader/c dataframe-read-csv lazyframe-scan-csv)
         (only-in polars/private/expr lazyframe-scan-parquet)
         (only-in polars/private/foreign
                  dataframe-read-json-lines dataframe-read-parquet dataframe-write-csv
                  dataframe-write-json-lines dataframe-write-parquet)
         (only-in polars/private/generic/core
                  dataframe? lazyframe? wrap-dataframe wrap-lazyframe)
         syntax/parse/define)

(provide (contract-out
          [read-csv (csv-reader/c dataframe?)]
          [scan-csv (csv-reader/c lazyframe?)]
          [read-parquet (-> path-string? dataframe?)]
          [scan-parquet (->* (path-string?)
                             (#:n-rows (or/c #f exact-nonnegative-integer?))
                             lazyframe?)]
          [read-ndjson (-> path-string? dataframe?)]
          [write-csv (-> dataframe? path-string? void?)]
          [write-parquet (-> dataframe? path-string? void?)]
          [write-ndjson (-> dataframe? path-string? void?)]))

(define-syntax-parse-rule (define-wrapped name:id wrap:expr reader:expr)
  (define name (procedure-rename (compose1 wrap reader) 'name)))

(define-wrapped read-csv wrap-dataframe dataframe-read-csv)
(define-wrapped scan-csv wrap-lazyframe lazyframe-scan-csv)
(define-wrapped read-parquet wrap-dataframe dataframe-read-parquet)
(define-wrapped scan-parquet wrap-lazyframe lazyframe-scan-parquet)
(define-wrapped read-ndjson wrap-dataframe dataframe-read-json-lines)
(define write-csv dataframe-write-csv)
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
           (only-in gregor date datetime moment)
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

  (define csv-keywords
    '(#:comment-prefix #:encoding #:glob #:has-header #:ignore-errors
      #:infer-schema-length #:n-rows #:null-values #:quote-char
      #:schema-overrides #:separator #:skip-rows #:try-parse-dates))
  (define csv-readers
    (list contracted:read-csv contracted:scan-csv raw:dataframe-read-csv raw:lazyframe-scan-csv))
  (for ([reader (in-list csv-readers)])
    (define-values (required accepted) (procedure-keywords reader))
    (check-equal? required '())
    (check-equal? accepted csv-keywords))

  (define missing (build-path scratch "no-such.csv"))
  (define bad-keywords
    `((#:separator . "\t") (#:separator . 9) (#:separator . #\é) (#:separator . #\newline)
      (#:quote-char . "'") (#:comment-prefix . "") (#:null-values . NA)
      (#:null-values . ("NA" 1)) (#:infer-schema-length . -1) (#:infer-schema-length . 1.5)
      (#:schema-overrides . ((a . int32))) (#:schema-overrides . (("a" . bogus)))
      (#:schema-overrides . (("a" . (duration microseconds))))
      (#:schema-overrides . (("a" . (enum x y))))
      (#:schema-overrides . (("a" . (datetime microseconds "UTC"))))
      (#:schema-overrides . (("a" . int32) ("a" . f64)))
      (#:schema-overrides . ,(hash "a" 'int32)) (#:encoding . latin1) (#:glob . 1)
))
  (for ([reader (in-list csv-readers)]
        [name '(read-csv scan-csv dataframe-read-csv lazyframe-scan-csv)])
    (define blamed (regexp (format "^~a: contract violation" name)))
    (check-exn blamed (lambda () (reader 'sym)))
    (for ([kvs (in-list (append (map list bad-keywords)
                                '(((#:quote-char . #\,))
                                  ((#:separator . #\;) (#:quote-char . #\;))
                                  ((#:separator . #\")))))])
      (check-exn (lambda (e) (and (exn:fail:contract:blame? e)
                                  (regexp-match? blamed (exn-message e))))
                 (lambda () (with-keywords reader missing kvs))
                 (format "~a ~s" name kvs))))
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
   #rx"^dataframe-read-csv: failed to read csv from [^:]*flights.tsv: could not parse `NA` as dtype `i64` at column 'arr_delay' \\(column number 9\\)"
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
   #rx"^dataframe-read-csv: failed to read csv from [^:]*ab.csv: schema overrides name columns not in the file: \"zzz\"$"
   (lambda () (read-csv ab #:schema-overrides absent)))
  (check-exn
   #rx"^lazyframe-scan-csv: failed to scan [^:]*ab.csv: schema overrides name columns not in the file: \"zzz\"$"
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
  (define apple (read-csv (build-path data-dir "apple_stock.csv") #:try-parse-dates #t))
  (check-equal? (shape apple) '(100 2))
  (check-equal? (dtypes-of apple) '(date float64))
  (check-equal? (ref (ref apple #:columns "Date") 0) (date 1981 2 23))
  (check-equal? (ref (ref apple #:columns "Close") 99) 522.06)
  (check-equal? (dtypes-of (read-csv (build-path data-dir "apple_stock.csv"))) '(string float64))

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
  (check-exn #rx"^lazyframe-scan-csv: failed to scan "
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
  (check-exn #rx"^dataframe-read-csv: " (lambda () (read-csv (build-path scratch "mixed" "*.csv"))))

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
  (check-exn #rx"^dataframe-read-csv: failed to read csv from [^:]*dirmix: cannot open file: it is a directory"
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
  (check-regexp-match #rx"^dataframe-read-csv: [^:]*flights.tsv reads as one column" flights-guard)
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

  (define brussels
    (dataframe (list (series (list (moment 2021 3 27 12 0 0 500000000 #:tz "Europe/Brussels")
                                   polars-null (moment 2021 7 1 #:tz "Europe/Brussels"))
                             #:name "t"))))
  (define brussels-csv (build-path scratch "brussels.csv"))
  (write-csv brussels brussels-csv)
  (check-equal? (file->string brussels-csv)
                "t\n2021-03-27T12:00:00.500000+0100\n\n2021-07-01T00:00:00.000000+0200\n")
  (define brussels-parquet (build-path scratch "brussels.parquet"))
  (write-parquet brussels brussels-parquet)
  (check-true (frame=? (read-parquet brussels-parquet) brussels))
  (check-equal? (dtype (ref (read-parquet brussels-parquet) "t"))
                '(datetime microseconds "Europe/Brussels"))
  (define brussels-ndjson (build-path scratch "brussels.ndjson"))
  (write-ndjson brussels brussels-ndjson)
  (check-equal? (file->string brussels-ndjson)
                (string-append "{\"t\":\"2021-03-27T12:00:00.500+01:00\"}\n{\"t\":null}\n"
                               "{\"t\":\"2021-07-01T00:00:00+02:00\"}\n"))
  (define offsets (scratch-file "offsets.csv" "t,u"
                                "2021-03-27T00:00:00+01:00,2021-03-27 00:00"
                                "2021-03-29T00:00:00+02:00,2021-03-29 00:00"))
  (for ([read (list (lambda (p) (read-csv p #:try-parse-dates #t))
                    (lambda (p) (collect (scan-csv p #:try-parse-dates #t))))])
    (define parsed (read offsets))
    (check-equal? (dtype (ref parsed "t")) '(datetime microseconds "UTC"))
    (check-equal? (column parsed "t")
                  (list (moment 2021 3 26 23 #:tz "UTC") (moment 2021 3 28 22 #:tz "UTC")))
    (check-equal? (dtype (ref parsed "u")) '(datetime microseconds #f)))

  (delete-directory/files scratch))
