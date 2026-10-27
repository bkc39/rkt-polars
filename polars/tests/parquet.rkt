#lang racket/base

(module+ test
  (require rackunit
           racket/file
           racket/runtime-path
           (only-in racket/list make-list)
           (only-in polars/private/expr
                    col dataframe-lazy expr-gt lazyframe-collect lazyframe-explain
                    lazyframe-filter lazyframe-select)
           (only-in polars/private/foreign
                    dataframe-column dataframe-column-names dataframe-drop-count
                    dataframe-drop dataframe-height dataframe-new polars-null
                    series-new-f64 series-new-i32 series-new-i64 series-new-str series-ref)
           (prefix-in contracted: polars/private/parquet)
           (only-in (submod polars/private/parquet internal)
                    dataframe-read-parquet dataframe-write-parquet dataframe-write-parquet/raw
                    lazyframe-scan-parquet make-CompatParquetWriteOptions)
           (only-in polars/private/io-contracts size-max)
           (only-in polars/tests/test-helpers
                    apply-keywords contract-violation-of drops-once
                    keyword-rejected? message-of scratch-file))

  (define scratch (make-temporary-directory "rkt-polars-parquet-~a"))
  (define (in-scratch name) (build-path scratch name))
  (define (values-of df name)
    (define s (dataframe-column df name))
    (for/list ([i (in-range (dataframe-height df))]) (series-ref s i)))
  (define (frame-values df)
    (for/list ([name (in-list (dataframe-column-names df))])
      (cons name (values-of df name))))

  (define cities
    (dataframe-new
     (list (series-new-str "city" '("Boston" "New York" "Chicago"))
           (series-new-f64 "population_millions" '(0.65 8.8 2.7))
           (series-new-i32 "founded" '(1630 1624 1837)))))
  (define cities-parquet (in-scratch "cities.parquet"))
  (contracted:dataframe-write-parquet cities cities-parquet)
  (check-equal? (frame-values (contracted:dataframe-read-parquet cities-parquet))
                (frame-values cities))

  (define shared-keywords
    '(#:glob #:include-file-paths #:low-memory #:missing-columns #:n-rows #:parallel
      #:rechunk #:row-index-name #:row-index-offset #:use-statistics))
  (for ([proc (list contracted:dataframe-read-parquet contracted:lazyframe-scan-parquet
                    contracted:dataframe-write-parquet)]
        [keywords (list (cons '#:columns shared-keywords) (cons '#:cache shared-keywords)
                        '(#:compression #:compression-level #:data-page-size
                          #:row-group-size #:statistics))])
    (define-values (required accepted) (procedure-keywords proc))
    (check-equal? required '())
    (check-equal? accepted keywords))

  (define numbers
    (dataframe-new
     (list (series-new-i64 "a" '(1 2 3 4))
           (series-new-str "b" '("x" "y" "z" "w"))
           (series-new-f64 "c" '(1.5 2.5 3.0 4.0)))))
  (define numbers-parquet (in-scratch "numbers.parquet"))
  (dataframe-write-parquet numbers numbers-parquet)
  (define (read-numbers . kvs)
    (frame-values (apply-keywords dataframe-read-parquet kvs numbers-parquet)))

  (check-equal? (read-numbers '(#:columns . ("c" "a")))
                '(("c" 1.5 2.5 3.0 4.0) ("a" 1 2 3 4)))
  (check-equal? (read-numbers '(#:columns . (2 0))) (read-numbers '(#:columns . ("c" "a"))))
  (check-equal? (read-numbers '(#:columns . (-1))) '(("c" 1.5 2.5 3.0 4.0)))
  (check-equal? (read-numbers '(#:columns . ())) '())
  (check-equal? (read-numbers '(#:n-rows . 2)) '(("a" 1 2) ("b" "x" "y") ("c" 1.5 2.5)))
  (check-equal? (read-numbers '(#:n-rows . 0)) '(("a") ("b") ("c")))
  (check-equal? (read-numbers '(#:row-index-name . "i") '(#:row-index-offset . 10)
                              '(#:columns . ("i" "b")))
                '(("i" 10 11 12 13) ("b" "x" "y" "z" "w")))
  (check-equal? (read-numbers '(#:row-index-name . "i") '(#:columns . (0)))
                '(("i" 0 1 2 3)))
  (check-equal? (read-numbers '(#:row-index-offset . 10)) (frame-values numbers))
  (check-equal? (read-numbers '(#:n-rows . 2) '(#:row-index-name . "i") '(#:row-index-offset . 5))
                '(("i" 5 6) ("a" 1 2) ("b" "x" "y") ("c" 1.5 2.5)))
  (for* ([parallel '(auto columns row-groups prefiltered none)]
         [kvs (list '() '((#:use-statistics . #f)) '((#:low-memory . #t)) '((#:rechunk . #t)))])
    (check-equal? (apply read-numbers (cons '#:parallel parallel) kvs)
                  (frame-values numbers)
                  (format "~a ~s" parallel kvs)))
  (check-equal? (read-numbers '(#:include-file-paths . "source") '(#:columns . ("source" "a")))
                `(("source" ,@(make-list 4 (path->string numbers-parquet))) ("a" 1 2 3 4)))

  (define (scan-numbers . kvs)
    (frame-values (lazyframe-collect (apply-keywords lazyframe-scan-parquet kvs
                                                     numbers-parquet))))
  (for ([kvs (list '() '((#:cache . #f)) '((#:parallel . prefiltered) (#:use-statistics . #f))
                   '((#:low-memory . #t) (#:rechunk . #t)))])
    (check-equal? (apply scan-numbers kvs) (frame-values numbers) (format "~s" kvs)))
  (check-equal? (scan-numbers '(#:n-rows . 1) '(#:row-index-name . "i"))
                '(("i" 0) ("a" 1) ("b" "x") ("c" 1.5)))
  (check-equal? (frame-values
                 (lazyframe-collect
                  (lazyframe-filter (lazyframe-scan-parquet numbers-parquet #:row-index-name "i")
                                    (expr-gt (col "a") 2))))
                '(("i" 2 3) ("a" 3 4) ("b" "z" "w") ("c" 3.0 4.0)))

  (check-regexp-match
   #rx"^dataframe-read-parquet: failed to read parquet from [^:]*: column index 7 is out of range for 3 columns$"
   (message-of (lambda () (dataframe-read-parquet numbers-parquet #:columns '(0 7)))))
  (check-regexp-match
   #rx": column index -4 is out of range for 3 columns$"
   (message-of (lambda () (dataframe-read-parquet numbers-parquet #:columns '(-4)))))
  (check-regexp-match
   #rx": column \"a\" is selected more than once$"
   (message-of (lambda () (dataframe-read-parquet numbers-parquet #:columns '("a" "a")))))
  (check-regexp-match
   #rx": column \"c\" is selected more than once$"
   (message-of (lambda () (dataframe-read-parquet numbers-parquet #:columns '(2 -1)))))
  (check-regexp-match
   #rx"^dataframe-read-parquet: failed to read parquet from [^:]*numbers[.]parquet: .*'a'"
   (message-of (lambda () (dataframe-read-parquet numbers-parquet #:row-index-name "a"))))

  (define last-offset (- #xFFFFFFFF 3))
  (check-equal? (values-of (dataframe-read-parquet numbers-parquet #:row-index-name "i"
                                                   #:row-index-offset last-offset)
                           "i")
                (for/list ([i 4]) (+ last-offset i)))
  (define past-last '((#:row-index-name . "i") (#:row-index-offset . 4294967293)))
  (for ([read (list (lambda () (apply-keywords dataframe-read-parquet past-last numbers-parquet))
                    (lambda ()
                      (lazyframe-collect
                       (apply-keywords lazyframe-scan-parquet past-last numbers-parquet))))])
    (check-regexp-match #rx"^[^:]*: (failed to [^:]*: )?row index from offset 4294967293 overflows u32$"
                        (message-of read)))

  (define kept-dir (in-scratch "kept"))
  (make-directory* kept-dir)
  (define kept (build-path kept-dir "kept.parquet"))
  (dataframe-write-parquet cities kept)
  (define kept-bytes (file->bytes kept))
  (define floats (dataframe-new (list (series-new-f64 "f" '(1.5 2.5 3.5)))))
  (define min-max-only (make-CompatParquetWriteOptions 5 #f 3 #f #f 0 0 0))
  (check-equal? (dataframe-write-parquet/raw floats (path->string kept) min-max-only) 4)
  (check-equal? (file->bytes kept) kept-bytes)
  (check-equal? (directory-list kept-dir) (list (string->path "kept.parquet")))
  (define junk (scratch-file scratch "junk.bin" "this is not parquet"))
  (check-exn #rx"^dataframe-read-parquet: failed to read parquet from [^:]*: cannot open file: [Nn]o such file"
             (lambda () (dataframe-read-parquet (in-scratch "no-such.parquet"))))
  (check-exn #rx"^lazyframe-collect: .*PAR1"
             (lambda () (lazyframe-collect (lazyframe-scan-parquet junk))))

  (make-directory* (in-scratch "parts"))
  (dataframe-write-parquet numbers (in-scratch "parts/a.parquet"))
  (dataframe-write-parquet (dataframe-new (list (series-new-i64 "a" '(5))
                                                (series-new-str "b" '("v"))))
                           (in-scratch "parts/b.parquet"))
  (define parts (in-scratch "parts/*.parquet"))
  (check-regexp-match
   #px"^dataframe-read-parquet: failed to read parquet from [^:]*parts/[*][.]parquet: .*\\bc\\b.*#:missing-columns 'insert"
   (message-of (lambda () (dataframe-read-parquet parts))))
  (check-equal? (frame-values (dataframe-read-parquet parts #:missing-columns 'insert))
                `(("a" 1 2 3 4 5) ("b" "x" "y" "z" "w" "v") ("c" 1.5 2.5 3.0 4.0 ,polars-null)))
  (check-equal? (values-of (dataframe-read-parquet parts #:missing-columns 'insert
                                                   #:include-file-paths "file")
                           "file")
                (append (make-list 4 (path->string (in-scratch "parts/a.parquet")))
                        (list (path->string (in-scratch "parts/b.parquet")))))

  (make-directory* (in-scratch "widening"))
  (dataframe-write-parquet (dataframe-new (list (series-new-i64 "a" '(5))))
                           (in-scratch "widening/a.parquet"))
  (dataframe-write-parquet numbers (in-scratch "widening/b.parquet"))
  (define widening-message
    (message-of (lambda () (dataframe-read-parquet (in-scratch "widening/*.parquet")))))
  (check-regexp-match
   #px"^dataframe-read-parquet: failed to read parquet from [^:]*widening/[*][.]parquet: .*\\bb\\b.*widening/b[.]parquet"
   widening-message)
  (check-false (regexp-match? #rx"extra_columns|schema, or pass" widening-message))

  (define bracketed (in-scratch "x[1].parquet"))
  (dataframe-write-parquet numbers bracketed)
  (dataframe-write-parquet cities (in-scratch "x1.parquet"))
  (check-equal? (dataframe-column-names (dataframe-read-parquet bracketed))
                (dataframe-column-names cities))
  (check-equal? (dataframe-column-names (dataframe-read-parquet bracketed #:glob #f))
                '("a" "b" "c"))
  (check-equal? (dataframe-column-names
                 (lazyframe-collect (lazyframe-scan-parquet bracketed #:glob #f)))
                '("a" "b" "c"))
  (check-regexp-match #rx"cannot open file: [Nn]o such file"
                      (message-of (lambda () (dataframe-read-parquet parts #:glob #f))))

  (for ([year '(2013 2014)])
    (define dir (in-scratch (format "hive/year=~a" year)))
    (make-directory* dir)
    (dataframe-write-parquet (dataframe-new (list (series-new-i64 "x" (list year))))
                             (build-path dir "p.parquet")))
  (for ([glob? '(#t #f)])
    (check-equal? (frame-values (dataframe-read-parquet (in-scratch "hive") #:glob glob?))
                  '(("x" 2013 2014) ("year" 2013 2014))
                  (format "#:glob ~a" glob?)))

  (define empty-parquet (in-scratch "empty.parquet"))
  (dataframe-write-parquet (dataframe-read-parquet numbers-parquet #:n-rows 0) empty-parquet
                           #:row-group-size 10)
  (check-equal? (frame-values (dataframe-read-parquet empty-parquet)) '(("a") ("b") ("c")))


  (for ([kvs (list '((#:columns . ("a" 0))) '((#:columns . "a")) '((#:columns . (1.5)))
                   `((#:columns ,(expt 2 63)))
                   '((#:n-rows . -1)) `((#:n-rows . ,(add1 size-max)))
                   '((#:row-index-name . a)) '((#:row-index-offset . -1))
                   `((#:row-index-offset . ,(expt 2 32)))
                   '((#:parallel . row_groups)) '((#:use-statistics . 1)) '((#:glob . "no"))
                   '((#:missing-columns . ignore)) '((#:include-file-paths . #t))
                   '((#:columns . ("a\u0000zz"))) '((#:row-index-name . "i\u0000j"))
                   '((#:include-file-paths . "f\u0000g")))])
    (check-exn (contract-violation-of 'dataframe-read-parquet)
               (lambda () (apply-keywords contracted:dataframe-read-parquet kvs
                                          numbers-parquet))
               (format "~s" kvs)))
  (check-exn (keyword-rejected? '#:cache)
             (lambda () (contracted:dataframe-read-parquet numbers-parquet #:cache #f)))
  (check-exn (keyword-rejected? '#:columns)
             (lambda () (contracted:lazyframe-scan-parquet numbers-parquet #:columns '("a"))))
  (check-exn (contract-violation-of 'lazyframe-scan-parquet)
             (lambda () (contracted:lazyframe-scan-parquet numbers-parquet #:cache 'no)))
  (for ([kvs (list '((#:compression . lzo)) '((#:compression . "zstd"))
                   '((#:compression . gzip) (#:compression-level . 10))
                   '((#:compression . gzip) (#:compression-level . -1))
                   '((#:compression . brotli) (#:compression-level . 12))
                   '((#:compression-level . 0)) '((#:compression-level . 23))
                   '((#:compression-level . 3.0)) '((#:compression-level . "3"))
                   '((#:compression . 5) (#:compression-level . 3))
                   '((#:statistics . partial)) '((#:statistics . (min bogus)))
                   '((#:statistics . (min))) '((#:statistics . (min null-count)))
                   '((#:statistics . (null-count))) '((#:statistics . (max null-count)))
                   '((#:statistics . (distinct-count null-count)))
                   '((#:statistics . (min max))) '((#:statistics . (min max distinct-count)))
                   '((#:row-group-size . -1)) '((#:data-page-size . 1.5))
                   `((#:row-group-size . ,(add1 size-max)))
                   `((#:data-page-size . ,(add1 size-max))))])
    (check-exn (contract-violation-of 'dataframe-write-parquet)
               (lambda () (apply-keywords contracted:dataframe-write-parquet kvs
                                          numbers (in-scratch "never.parquet")))
               (format "~s" kvs)))
  (check-regexp-match
   #rx"^dataframe-write-parquet: contract violation\n  #:compression-level 0 is outside zstd's levels, 1 to 22\n"
   (message-of (lambda () (contracted:dataframe-write-parquet numbers (in-scratch "never.parquet")
                                                              #:compression-level 0))))
  (check-regexp-match
   #rx"^dataframe-write-parquet: contract violation\n  #:compression-level 10 is outside gzip's levels, 0 to 9\n"
   (message-of (lambda () (contracted:dataframe-write-parquet numbers (in-scratch "never.parquet")
                                                              #:compression 'gzip
                                                              #:compression-level 10))))
  (check-false (regexp-match? #rx"unsupplied"
                              (message-of
                               (lambda ()
                                 (contracted:dataframe-write-parquet
                                  numbers (in-scratch "never.parquet") #:compression-level 0)))))
  (check-false (file-exists? (in-scratch "never.parquet")))

  (define-runtime-path produce-parquet "../scribblings/data/produce.parquet")
  (check-regexp-match
   #rx"^dataframe-read-parquet: failed to read parquet from [^:]*produce[.]parquet: column index 3 is out of range for 3 columns$"
   (message-of (lambda () (contracted:dataframe-read-parquet produce-parquet #:columns '(3)))))
  (check-exn (contract-violation-of 'lazyframe-scan-parquet)
             (lambda () (contracted:lazyframe-scan-parquet produce-parquet #:missing-columns 'ignore)))
  (check-exn (contract-violation-of 'dataframe-write-parquet)
             (lambda () (contracted:dataframe-write-parquet (dataframe-read-parquet produce-parquet)
                                                            (in-scratch "raw.parquet")
                                                            #:compression 'lzo)))
  (check-regexp-match
   #rx"^lazyframe-explain: failed to explain the query: [^\n]*\"colour\""
   (message-of (lambda ()
                 (lazyframe-explain
                  (lazyframe-select (dataframe-lazy (dataframe-read-parquet produce-parquet))
                                    (list (col "colour")))))))

  (for ([make (list (lambda () (dataframe-read-parquet numbers-parquet))
                    (lambda () (dataframe-read-parquet numbers-parquet #:columns '(0)
                                                       #:row-index-name "i"))
                    (lambda () (lazyframe-collect (lazyframe-scan-parquet parts #:n-rows 2))))])
    (check-equal? (drops-once dataframe-drop-count dataframe-drop make) 1))

  (delete-directory/files scratch))
