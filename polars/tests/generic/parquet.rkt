#lang racket/base

(module+ test
  (require rackunit
           racket/file
           racket/runtime-path
           (only-in racket/list second)
           (only-in racket/string string-contains?)
           (only-in gregor moment)
           (only-in threading ~>)
           (prefix-in contracted: polars/private/generic/parquet)
           (only-in (submod polars/private/generic/parquet internal)
                    read-parquet scan-parquet write-parquet)
           (only-in polars/private/bulk series->list)
           (only-in polars/private/expr-core col)
           (only-in polars/private/generic/core
                    column-names dataframe dtype height lazyframe? null-count ref series shape)
           (only-in polars/private/generic/datetime dt-convert-time-zone dt-replace-time-zone)
           (only-in polars/private/generic/operators [> p>])
           (only-in polars/private/generic/printing series->string)
           (only-in polars/private/generic/reductions alias)
           (only-in polars/private/generic/csv read-csv write-csv)
           (only-in polars/private/generic/reshape
                    collect explain lazy select [filter frame-filter])
           (only-in polars/tests/generic/test-fixtures
                    apply-keywords column contains-all? dtypes-of explain-failure frame frame=?
                    keyword-rejected? message-of polars-null)
           (only-in (submod polars/tests/generic/test-fixtures test)
                    check-nul-names-round-trip check-staged-write eager-and-scan eager-reader))

  (define-runtime-path data-dir "../../scribblings/data")
  (define scratch (make-temporary-directory "rkt-polars-parquet-~a"))
  (define (one-column value)
    (dataframe (list (series (list value) #:name "x"))))

  (for ([name '("b" "c" "a")] [value '(2 3 1)])
    (write-parquet (one-column value) (build-path scratch (format "~a.parquet" name))))
  (define parquet-pattern (build-path scratch "*.parquet"))
  (check-equal? (column (read-parquet parquet-pattern) "x") '(1 2 3))
  (check-equal? (~> parquet-pattern scan-parquet collect (column "x")) '(1 2 3))
  (define widened (build-path scratch "widened"))
  (make-directory widened)
  (for ([name '("a" "b")] [integer '(i32 i64)])
    (write-parquet (dataframe (list (series '(1) #:name "a" #:dtype integer)))
                   (build-path widened (format "~a.parquet" name))))
  (define widened-message (message-of (lambda () (read-parquet (build-path widened "*.parquet")))))
  (check-regexp-match
   #rx"^read-parquet: [^\n]*data type mismatch for column a: incoming: Int64 != target: Int32$"
   widened-message)
  (check-false (regexp-match? #rx"cast_options|pl[.]" widened-message))

  (define nothing (build-path scratch "*.none"))
  (check-pred lazyframe? (scan-parquet nothing))
  (for ([thunk (list (lambda () (read-parquet nothing))
                     (lambda () (collect (scan-parquet nothing))))])
    (check-exn #rx": no files match the pattern$" thunk))

  (define bracketed-dir (build-path scratch "proj[1]"))
  (for ([dir (list bracketed-dir (build-path scratch "proj1"))] [value '(7 1)])
    (make-directory* dir)
    (write-parquet (one-column value) (build-path dir "data.parquet")))
  (parameterize ([current-directory bracketed-dir])
    (check-equal? (column (read-parquet "data.parquet") "x") '(7))
    (check-equal? (~> "data.parquet" scan-parquet collect (column "x")) '(7))
    (make-directory* "hive/year=2013")
    (write-parquet (one-column 7) "hive/year=2013/p.parquet")
    (check-equal? (~> "hive" read-parquet (column "x")) '(7)))

  (for ([year '(2013 2014)])
    (define dir (build-path scratch "hive" (format "year=~a" year)))
    (make-directory* dir)
    (write-parquet (one-column year) (build-path dir "p.parquet")))
  (define hive (build-path scratch "hive"))
  (check-equal? (column-names (read-parquet (build-path hive "year=2013" "p.parquet"))) '("x"))
  (check-equal? (column-names (read-parquet (build-path hive "*" "p.parquet"))) '("x"))
  (check-equal? (~> (build-path hive "*" "p.parquet") scan-parquet collect column-names) '("x"))
  (check-equal? (column-names (read-parquet hive)) '("x" "year"))

  (define frame-parquet (build-path scratch "frame.parquet"))
  (write-parquet frame frame-parquet)
  (check-true (frame=? (read-parquet frame-parquet) frame))
  (check-equal? (height (collect (scan-parquet frame-parquet #:n-rows 2))) 2)
  (define from-csv (read-csv (build-path data-dir "parts" "part-1.csv")))
  (define from-csv-parquet (build-path scratch "from-csv.parquet"))
  (write-parquet from-csv from-csv-parquet)
  (check-true (frame=? (read-parquet from-csv-parquet) from-csv))

  (define produce (read-parquet (build-path data-dir "produce.parquet")))
  (check-equal? (map second (dtypes-of produce))
                '(categorical (enum low mid high) (decimal 10 2)))
  (check-equal? (column produce "item") '(apple pear apple fig))
  (check-equal? (series->list (ref produce "grade")) (list 'high 'low polars-null 'mid))
  (check-equal? (column produce "price") (list 5/4 4/5 polars-null 12))
  (check-regexp-match #rx"\\[decimal\\[10,2\\]\\]\n\\[\n\t1.25\n\t0.80\n\tnull\n\t12.00\n\\]"
                      (series->string (ref produce "price")))
  (define produce-copy (build-path scratch "produce.parquet"))
  (write-parquet produce produce-copy)
  (check-true (frame=? (read-parquet produce-copy) produce))

  (define pq-dir (make-temporary-directory "rkt-polars-io-parquet-~a"))
  (define (pq-file name) (build-path pq-dir name))
  (define (data name) (build-path data-dir name))

  (define pq-flights (read-parquet (data "flights.parquet")))
  (check-true (frame=? pq-flights
                       (read-csv (data "flights.tsv") #:separator #\tab #:null-values "NA"
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

  (make-directory* (pq-file "mixed"))
  (write-parquet produce (pq-file "mixed/a.parquet"))
  (write-parquet (select produce "item") (pq-file "mixed/b.parquet"))
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
   (explain-failure 'explain "colour")
   (message-of (lambda () (explain (select (lazy produce) "colour")))))
  (define inserted (read-parquet mixed #:missing-columns 'insert))
  (check-equal? (shape inserted) '(8 3))
  (check-equal? (dtypes-of inserted) (dtypes-of produce))
  (check-equal? (null-count (ref inserted "grade")) 5)

  (define late
    (~> (scan-parquet (data "flights.parquet"))
        (frame-filter (p> (col "dep_delay") 20))
        (select "carrier" "dep_delay")))
  (check-equal? (column (collect late) "dep_delay") '(24 47 39))
  (check-equal? (column (collect late) "carrier") '("EV" "UA" "MQ"))
  (define optimised (explain late))
  (check-regexp-match #rx"^Parquet SCAN [[][^]]*/flights[.]parquet[]]\n" optimised)
  (check-true (contains-all? optimised '("PROJECT 2/19 COLUMNS"
                                         "SELECTION: col(\"dep_delay\") > 20")))
  (define unoptimised (explain late #:optimized #f))
  (check-false (string-contains? unoptimised "PROJECT 2/19 COLUMNS"))
  (check-true (contains-all? unoptimised '("SELECT [col(\"carrier\"), col(\"dep_delay\")]"
                                           "FILTER col(\"dep_delay\") > 20" "FROM"
                                           "Parquet SCAN [" "PROJECT */19 COLUMNS")))
  (check-true (string-contains? (explain late #:format 'tree) "SELECTION"))
  (define tree (explain (select (lazy produce) "item") #:format 'tree))
  (check-true (contains-all? tree '("DF [\"item\", \"grade\", \"price\"]"
                                    "PROJECT: [\"item\"]; 1/3 COLUMNS")))
  (check-regexp-match #rx"^scan-parquet: contract violation\n  expected: parquet-parallel/c\n  given: 'row_groups"
                      (message-of (lambda () (contracted:scan-parquet (data "flights.parquet")
                                                                      #:parallel 'row_groups))))
  (check-exn (keyword-rejected? '#:columns)
             (lambda () (contracted:scan-parquet (data "produce.parquet")
                                                 #:columns '("item"))))
  (check-regexp-match #rx"^(lazyframe-)?collect: .*[Nn]o such file"
                      (message-of (lambda () (collect (scan-parquet "/no/such/file.parquet")))))
  (for ([i '(1 2 3)])
    (write-parquet (read-csv (data (format "parts/part-~a.csv" i)))
                   (pq-file (format "part-~a.parquet" i))))
  (check-equal? (height (read-parquet (pq-file "part-*.parquet")))
                (for/sum ([i '(1 2 3)]) (height (read-csv (data (format "parts/part-~a.csv" i))))))
  (check-equal? (height (collect (scan-parquet (pq-file "part-*.parquet") #:n-rows 3))) 3)

  (define out (pq-file "produce.parquet"))
  (write-parquet produce out #:compression 'gzip #:compression-level 9 #:statistics #f)
  (check-true (frame=? (read-parquet out) produce))
  (write-parquet produce out #:compression 'lz4 #:row-group-size 2
                 #:statistics '(min max null-count distinct-count)
                 #:data-page-size 4096)
  (check-true (frame=? (read-parquet out) produce))
  (check-regexp-match
   #rx"^write-parquet: contract violation\n  #:compression-level 30 is outside zstd's levels, 1 to 22\n"
   (message-of (lambda () (contracted:write-parquet produce out #:compression-level 30))))
  (check-regexp-match
   #rx"^write-parquet: contract violation\n  expected: parquet-statistics/c\n  given: '[(]null-count[)]"
   (message-of (lambda () (contracted:write-parquet produce out #:statistics '(null-count)))))
  (check-true (frame=? (read-parquet out) produce))
  (check-equal? (message-of (lambda () (write-parquet produce "/no/such/dir/out.parquet")))
                (string-append "write-parquet: failed to write parquet to /no/such/dir/out.parquet: "
                               "cannot create file: No such file or directory (os error 2)"))
  (check-regexp-match #rx"^read-parquet: failed to read parquet from [^:]*: .*PAR1"
                      (message-of (lambda () (read-parquet (data "flights.tsv")))))
  (check-regexp-match #rx"^explain: contract violation\n  expected: lazyframe[?]"
                      (message-of (lambda () (explain produce))))
  (check-regexp-match #rx"^explain: contract violation\n  expected: explain-format/c\n  given: 'dot"
                      (message-of (lambda () (explain late #:format 'dot))))

  (define foo-bar
    (dataframe (list (series '(1 2 3) #:name "foo")
                     (series (list polars-null "bak" "baz") #:name "bar"))))
  (write-parquet foo-bar (pq-file "path.parquet"))
  (check-true (frame=? (read-parquet (pq-file "path.parquet")) foo-bar))
  (check-true (frame=? (collect (scan-parquet (pq-file "path.parquet"))) foo-bar))

  (write-csv produce (pq-file "produce.csv"))
  (check-equal? (map second (dtypes-of (read-csv (pq-file "produce.csv")))) '(string string float64))
  (check-equal? (column (read-csv (pq-file "produce.csv")) "price") (list 1.25 0.8 polars-null 12.0))
  (write-parquet produce (pq-file "produce-copy.parquet"))
  (check-equal? (map second (dtypes-of (read-parquet (pq-file "produce-copy.parquet"))))
                '(categorical (enum low mid high) (decimal 10 2)))
  (define stamps
    (select pq-flights "time_hour"
            (~> (col "time_hour") (dt-replace-time-zone "America/New_York") (alias "local"))))
  (write-csv stamps (pq-file "stamps.csv"))
  (check-equal? (dtypes-of (read-csv (pq-file "stamps.csv")))
                '(("time_hour" string) ("local" string)))
  (define stamps-parsed (read-csv (pq-file "stamps.csv") #:try-parse-dates #t))
  (check-equal? (dtypes-of stamps-parsed)
                '(("time_hour" (datetime microseconds #f)) ("local" (datetime microseconds "UTC"))))
  (check-true (frame=? (select stamps-parsed "local")
                       (select stamps (dt-convert-time-zone (col "local") "UTC"))))
  (write-parquet stamps (pq-file "stamps.parquet"))
  (check-equal? (dtypes-of (read-parquet (pq-file "stamps.parquet")))
                '(("time_hour" (datetime microseconds #f))
                  ("local" (datetime microseconds "America/New_York"))))
  (check-true (frame=? (read-parquet (pq-file "stamps.parquet")) stamps))

  (define framed (read-parquet (data "flights.parquet") #:columns '("row" "carrier" "dep_delay")
                               #:n-rows 3 #:row-index-name "row"))
  (check-equal? (column framed "row") '(0 1 2))
  (check-equal? (column framed "carrier") '("UA" "UA" "AA"))
  (write-parquet pq-flights (pq-file "flights.parquet")
                 #:compression 'gzip #:compression-level 9 #:statistics 'full #:row-group-size 50)
  (check-true (frame=? (read-parquet (pq-file "flights.parquet")) pq-flights))

  (check-staged-write write-parquet read-parquet "parquet" produce)
  (define leftover (pq-file "leftover"))
  (make-directory leftover)
  (write-parquet produce (build-path leftover "a.parquet"))
  (copy-file (build-path leftover "a.parquet") (build-path leftover ".rkt-polars-1-0.partial"))
  (check-equal? (height (read-parquet (build-path leftover "*.parquet"))) 4)
  (check-equal? (height (read-parquet (build-path leftover "*"))) 8)
  (check-regexp-match
   #rx"directory contained paths with different file extensions: .*/[.]rkt-polars-1-0[.]partial"
   (message-of (lambda () (read-parquet leftover))))


  (define compressible
    (dataframe (list (series (for/list ([i (in-range 20000)]) (modulo i 7)) #:name "n")
                     (series (for/list ([i (in-range 20000)]) (if (even? i) "even" "odd"))
                             #:name "s"))))
  (define (written-size . kvs)
    (define path (pq-file "sized.parquet"))
    (apply-keywords write-parquet kvs compressible path)
    (check-true (frame=? (read-parquet path) compressible) (format "~s" kvs))
    (file-size path))
  (define sizes
    (for/hash ([codec '(uncompressed snappy gzip brotli lz4 zstd)])
      (values codec (written-size (cons '#:compression codec)))))
  (for ([codec '(snappy gzip brotli lz4 zstd)])
    (check < (hash-ref sizes codec) (hash-ref sizes 'uncompressed) (format "~a" codec)))
  (check-equal? (written-size) (hash-ref sizes 'zstd))
  (for ([codec+level '((gzip . 0) (gzip . 9) (brotli . 0) (brotli . 11) (zstd . 1) (zstd . 22)
                       (snappy . 99) (lz4 . -5) (uncompressed . 123456789012))])
    (check-pred exact-positive-integer?
                (written-size (cons '#:compression (car codec+level))
                              (cons '#:compression-level (cdr codec+level)))))
  (check-equal? (written-size '(#:compression-level . 3)) (hash-ref sizes 'zstd))
  (check < (written-size '(#:compression . gzip) '(#:compression-level . 9))
         (written-size '(#:compression . gzip) '(#:compression-level . 0)))
  (define unstated (written-size '(#:statistics . #f)))
  (check < unstated (written-size))
  (check-equal? (written-size '(#:statistics . ())) unstated)
  (check-equal? (written-size '(#:statistics . (min max null-count))) (written-size))
  (check-equal? (written-size '(#:statistics . full))
                (written-size '(#:statistics . (min max distinct-count null-count))))
  (check-equal? (written-size '(#:statistics . (null-count max distinct-count min)))
                (written-size '(#:statistics . full)))
  (check < (written-size) (written-size '(#:row-group-size . 1000)))
  (check-equal? (written-size '(#:row-group-size . 0)) (written-size))
  (check < (written-size) (written-size '(#:data-page-size . 64)))
  (check-pred exact-positive-integer? (written-size '(#:data-page-size . 0)))

  (delete-directory/files pq-dir)

  (define brussels
    (dataframe (list (series (list (moment 2021 3 27 12 0 0 500000000 #:tz "Europe/Brussels")
                                   polars-null (moment 2021 7 1 #:tz "Europe/Brussels"))
                             #:name "t"))))
  (define brussels-parquet (build-path scratch "brussels.parquet"))
  (write-parquet brussels brussels-parquet)
  (check-true (frame=? (read-parquet brussels-parquet) brussels))
  (check-equal? (dtype (ref (read-parquet brussels-parquet) "t"))
                '(datetime microseconds "Europe/Brussels"))

  (define nul-parquet (build-path scratch "nul.parquet"))
  (define nul-plain (build-path scratch "nul-plain.parquet"))
  (write-parquet (dataframe (list (series '("x" "y") #:name "s"))) nul-plain)
  (check-nul-names-round-trip
   write-parquet nul-parquet (list (cons 'eager (eager-reader read-parquet)))
   (lambda (n read-with label)
     (check-equal? (column-names (read-with nul-parquet '())) (list n "s") label)
     (check-equal? (column (read-with nul-parquet `((#:columns . (,n)))) n) '(1 2) label)
     (check-equal? (column-names (read-with nul-parquet `((#:columns . (,n))))) (list n) label)))
  (check-nul-names-round-trip
   write-parquet nul-parquet (eager-and-scan read-parquet scan-parquet)
   (lambda (n read-with label)
     (check-equal? (column-names (read-with nul-plain `((#:row-index-name . ,n)))) (list n "s")
                   label)
     (check-equal? (column-names (read-with nul-plain `((#:include-file-paths . ,n))))
                   (list "s" n) label)))

  (delete-directory/files scratch))
