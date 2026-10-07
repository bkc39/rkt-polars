#lang racket/base

(require ffi/unsafe
         ffi/unsafe/alloc
         racket/match
         syntax/parse/define
         (for-syntax racket/base syntax/strip-context)
         (only-in racket/contract/base
                  ->i and/c contract-out flat-named-contract integer-in listof or/c
                  rename-contract unsupplied-arg?)
         (only-in polars/private/expr-core
                  _LazyFrame-ptr/null LazyFrame-ptr? define-compat lazyframe-drop)
         (only-in polars/private/foreign
                  _DataFrame-ptr _DataFrame-ptr/null DataFrame-ptr? call/foreign-error
                  dataframe-drop path->complete-string))

(provide parquet-reader parquet-scanner parquet-writer
         parquet-reader/c parquet-scanner/c parquet-writer/c
         (contract-out
          [dataframe-read-parquet (parquet-reader/c DataFrame-ptr?)]
          [lazyframe-scan-parquet (parquet-scanner/c LazyFrame-ptr?)]
          [dataframe-write-parquet (parquet-writer/c DataFrame-ptr?)]))

(define parallel-codes
  '((auto . 0) (columns . 1) (row-groups . 2) (prefiltered . 3) (none . 4)))

(define compression-codes
  '((uncompressed . 0) (snappy . 1) (gzip . 2) (brotli . 3) (lz4 . 4) (zstd . 5)))

(define compression-levels
  '((gzip 0 9) (brotli 0 11) (zstd 1 22)))

(define statistic-bits
  '((min . 1) (max . 2) (distinct-count . 4) (null-count . 8)))

(define (symbols/c name table)
  (rename-contract (apply or/c (map car table)) name))

(define parallel/c (symbols/c 'parquet-parallel/c parallel-codes))
(define compression/c (symbols/c 'parquet-compression/c compression-codes))
(define statistic/c (symbols/c 'parquet-statistic/c statistic-bits))
(define (complete-statistics? names)
  (or (null? names)
      (and (memq 'min names) (memq 'max names) (memq 'null-count names) #t)))
(define statistics/c
  (rename-contract
   (or/c boolean? 'full (and/c (listof statistic/c) complete-statistics?))
   'parquet-statistics/c))
(define name/c
  (flat-named-contract 'nul-free-string?
                       (lambda (v) (and (string? v) (not (memv #\nul (string->list v)))))))
(define column-index/c
  (rename-contract (integer-in (- (expt 2 63)) (sub1 (expt 2 63))) 'column-index/c))
(define row-index-offset/c (integer-in 0 (sub1 (expt 2 32))))
(define size/c (or/c #f (integer-in 0 (sub1 (expt 2 64)))))

(define (code table v) (cdr (assq v table)))

(define (given v default) (if (unsupplied-arg? v) default v))

(define (level-range compression)
  (match (assq compression compression-levels)
    [(list _ low high) (cons low high)]
    [#f #f]))

(define (level-problem compression level)
  (define codec (given compression 'zstd))
  (match* ((level-range codec) (given level #f))
    [((cons low high) (? exact-integer? level))
     (or (<= low level high)
         (format "#:compression-level ~a is outside ~s's levels, ~a to ~a" level codec low high))]
    [(_ _) #t]))

(define (statistics->bits statistics)
  (match statistics
    [#t (bitwise-ior 1 2 8)]
    [#f 0]
    ['full (bitwise-ior 1 2 4 8)]
    [names (for/fold ([bits 0]) ([name (in-list names)])
             (bitwise-ior bits (code statistic-bits name)))]))

(define-cstruct _CompatParquetReadOptions
  ([has-n-rows _stdbool]
   [parallel _uint8]
   [use-statistics _stdbool]
   [low-memory _stdbool]
   [rechunk _stdbool]
   [cache _stdbool]
   [glob _stdbool]
   [allow-missing-columns _stdbool]
   [row-index-offset _uint32]
   [n-rows _size]))

(define-cstruct _CompatParquetWriteOptions
  ([compression _uint8]
   [has-compression-level _stdbool]
   [statistics _uint8]
   [has-row-group-size _stdbool]
   [has-data-page-size _stdbool]
   [compression-level _int32]
   [row-group-size _size]
   [data-page-size _size]))

(struct read-call (options row-index-name include-file-paths columns))

(define-syntax-parse-rule
  (define-parquet-options (options:id io/c:id param:id)
    ([arg:id arg/c:expr] ...) range/c:expr
    ([kw:keyword name:id contract:expr default:expr] ...)
    (~optional (~seq #:pre (pre-name:id ...) pre-check:expr))
    body:expr)
  (begin
    (define (io/c param)
      (->i ([arg arg/c] ...)
           ((~@ kw [name contract]) ...)
           (~? (~@ #:pre/desc (pre-name ...) pre-check))
           [result range/c]))
    (define (options (~@ kw [name default]) ...)
      body)))

(begin-for-syntax
  (define scan-keywords
    (quote-syntax
     ([#:n-rows n-rows size/c #f]
      [#:row-index-name row-index-name (or/c #f name/c) #f]
      [#:row-index-offset row-index-offset row-index-offset/c 0]
      [#:parallel parallel parallel/c 'auto]
      [#:use-statistics use-statistics boolean? #t]
      [#:glob glob boolean? #t]
      [#:rechunk rechunk boolean? #f]
      [#:low-memory low-memory boolean? #f]
      [#:include-file-paths include-file-paths (or/c #f name/c) #f]
      [#:missing-columns missing-columns (or/c 'raise 'insert) 'raise]))))

(define-syntax-parse-rule
  (define-parquet-reader-options (options:id io/c:id)
    ([kw:keyword name:id contract:expr default:expr] ...)
    body:expr)
  #:with (shared ...) (replace-context #'options scan-keywords)
  (define-parquet-options (options io/c result/c) ([path path-string?]) result/c
    ([kw name contract default] ... shared ...)
    body))

(define-parquet-reader-options (read-options parquet-reader/c)
  ([#:columns columns (or/c #f (listof name/c) (listof column-index/c)) #f])
  (read-call (make-CompatParquetReadOptions
              (and n-rows #t) (code parallel-codes parallel) use-statistics low-memory
              rechunk #f glob (eq? missing-columns 'insert) row-index-offset (or n-rows 0))
             row-index-name include-file-paths columns))

(define-parquet-reader-options (scan-options parquet-scanner/c)
  ([#:cache cache boolean? #t])
  (read-call (make-CompatParquetReadOptions
              (and n-rows #t) (code parallel-codes parallel) use-statistics low-memory
              rechunk cache glob (eq? missing-columns 'insert) row-index-offset (or n-rows 0))
             row-index-name include-file-paths #f))

(define-parquet-options (write-options parquet-writer/c frame/c)
  ([d frame/c] [path path-string?]) void?
  ([#:compression compression compression/c 'zstd]
   [#:compression-level compression-level (or/c #f exact-integer?) #f]
   [#:statistics statistics statistics/c #t]
   [#:row-group-size row-group-size size/c #f]
   [#:data-page-size data-page-size size/c #f])
  #:pre (compression compression-level)
  (level-problem compression compression-level)
  (let ([level (and (level-range compression) compression-level)])
    (make-CompatParquetWriteOptions (code compression-codes compression)
                                    (and level #t)
                                    (statistics->bits statistics)
                                    (and row-group-size #t)
                                    (and data-page-size #t)
                                    (or level 0)
                                    (or row-group-size 0)
                                    (or data-page-size 0))))

(define-compat dataframe-read-parquet/raw
  (_fun _string/utf-8
        _CompatParquetReadOptions
        _string/utf-8
        _string/utf-8
        _uint8
        (names : (_list i _string/utf-8))
        (indices : (_list i _int64))
        (_size = (+ (length names) (length indices)))
        -> _DataFrame-ptr/null)
  #:c-id dataframe_read_parquet_with_options
  #:wrap (allocator dataframe-drop))

(define-compat lazyframe-scan-parquet/raw
  (_fun _string/utf-8 _CompatParquetReadOptions _string/utf-8 _string/utf-8
        -> _LazyFrame-ptr/null)
  #:c-id lazyframe_scan_parquet_with_options
  #:wrap (allocator lazyframe-drop))

(define-compat dataframe-write-parquet/raw
  (_fun _DataFrame-ptr _string/utf-8 _CompatParquetWriteOptions -> _int32)
  #:c-id dataframe_write_parquet_with_options)

(define (keyword-forwarder who options arity call)
  (define-values (_ option-keywords) (procedure-keywords options))
  (procedure-rename
   (procedure-reduce-keyword-arity
    (make-keyword-procedure
     (lambda (keywords arguments . positional)
       (apply call (keyword-apply options keywords arguments '()) positional)))
    arity '() option-keywords)
   who))

(define (read-path who path options)
  (path->complete-string who path #:glob? (CompatParquetReadOptions-glob options)))

(define (columns-kind columns)
  (match columns
    [#f 0]
    [(list (? string?) ...) 1]
    [_ 2]))

(define (parquet-reader who)
  (keyword-forwarder
   who read-options 1
   (lambda (call path)
     (match-define (read-call options row-index-name include-file-paths columns) call)
     (define kind (columns-kind columns))
     (call/foreign-error
      who
      (lambda ()
        (dataframe-read-parquet/raw (read-path who path options) options
                                    row-index-name include-file-paths kind
                                    (if (= kind 1) columns '())
                                    (if (= kind 2) columns '())))
      "failed to read parquet from ~a" path))))

(define (parquet-scanner who)
  (keyword-forwarder
   who scan-options 1
   (lambda (call path)
     (match-define (read-call options row-index-name include-file-paths _) call)
     (call/foreign-error
      who
      (lambda ()
        (lazyframe-scan-parquet/raw (read-path who path options) options
                                    row-index-name include-file-paths))
      "failed to scan ~a" path))))

(define (parquet-writer who)
  (keyword-forwarder
   who write-options 2
   (lambda (options d path)
     (define p (path->complete-string who path))
     (void (call/foreign-error who
                               (lambda () (dataframe-write-parquet/raw d p options))
                               #:ok? zero?
                               "failed to write parquet to ~a" path)))))

(define dataframe-read-parquet (parquet-reader 'dataframe-read-parquet))
(define lazyframe-scan-parquet (parquet-scanner 'lazyframe-scan-parquet))
(define dataframe-write-parquet (parquet-writer 'dataframe-write-parquet))

(module+ test
  (require rackunit
           racket/file
           racket/runtime-path
           (only-in racket/contract exn:fail:contract:blame?)
           (only-in racket/list make-list)
           (only-in racket/string string-contains?)
           (only-in polars/private/expr
                    col dataframe-lazy expr-gt lazyframe-collect lazyframe-explain
                    lazyframe-filter lazyframe-select)
           (only-in polars/private/foreign
                    dataframe-column dataframe-column-names dataframe-drop-count
                    dataframe-drop dataframe-height dataframe-new dataframe-shape
                    polars-null series-dtype series-new-f64 series-new-i32 series-new-i64
                    series-new-str series-ref series-sum-f64)
           (prefix-in contracted: (submod "..")))

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
  (define cities-back (contracted:dataframe-read-parquet cities-parquet))
  (check-equal? (call-with-values (lambda () (dataframe-shape cities-back)) list) '(3 3))
  (check-equal? (dataframe-column-names cities-back) '("city" "population_millions" "founded"))
  (check-equal? (series-dtype (dataframe-column cities-back "founded")) 'int32)
  (check-= (series-sum-f64 (dataframe-column cities-back "population_millions")) 12.15 1e-9)

  (define-values (_ read-keywords) (procedure-keywords contracted:dataframe-read-parquet))
  (check-equal? read-keywords
                '(#:columns #:glob #:include-file-paths #:low-memory #:missing-columns
                  #:n-rows #:parallel #:rechunk #:row-index-name #:row-index-offset
                  #:use-statistics))
  (define-values (__ scan-keywords) (procedure-keywords contracted:lazyframe-scan-parquet))
  (check-equal? scan-keywords
                '(#:cache #:glob #:include-file-paths #:low-memory #:missing-columns
                  #:n-rows #:parallel #:rechunk #:row-index-name #:row-index-offset
                  #:use-statistics))
  (define-values (___ write-keywords) (procedure-keywords contracted:dataframe-write-parquet))
  (check-equal? write-keywords
                '(#:compression #:compression-level #:data-page-size #:row-group-size
                  #:statistics))

  (define numbers
    (dataframe-new
     (list (series-new-i64 "a" '(1 2 3 4))
           (series-new-str "b" '("x" "y" "z" "w"))
           (series-new-f64 "c" '(1.5 2.5 3.0 4.0)))))
  (define numbers-parquet (in-scratch "numbers.parquet"))
  (dataframe-write-parquet numbers numbers-parquet)
  (define (read-numbers . kvs)
    (frame-values (keyword-apply/sorted dataframe-read-parquet kvs numbers-parquet)))
  (define (keyword-apply/sorted f kvs . args)
    (define sorted (sort kvs keyword<? #:key car))
    (keyword-apply f (map car sorted) (map cdr sorted) args))

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
    (frame-values (lazyframe-collect (keyword-apply/sorted lazyframe-scan-parquet kvs
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

  (define filtered-scan
    (lazyframe-filter (lazyframe-scan-parquet numbers-parquet) (expr-gt (col "a") 2)))
  (define explained (lazyframe-explain filtered-scan))
  (check-regexp-match #rx"Parquet SCAN [[][^]]*numbers[.]parquet[]]" explained)
  (check-true (string-contains? explained "SELECTION: col(\"a\") > 2"))
  (check-false (string-contains? (lazyframe-explain filtered-scan #:optimized #f) "SELECTION"))
  (check-true (string-contains? (lazyframe-explain (lazyframe-scan-parquet numbers-parquet
                                                                           #:n-rows 2))
                                "SLICE"))

  (define (message-of thunk)
    (with-handlers ([exn:fail? exn-message]) (thunk) #f))
  (check-regexp-match
   #rx"^dataframe-read-parquet: failed to read parquet from [^:]*numbers.parquet: columns not in the file: \"zz\", \"yy\"$"
   (message-of (lambda () (dataframe-read-parquet numbers-parquet #:columns '("a" "zz" "yy")))))
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

  (check-regexp-match
   #rx"^dataframe-read-parquet: failed to read parquet from [^:]*: polars panicked: "
   (message-of (lambda () (dataframe-read-parquet numbers-parquet #:row-index-name "i"
                                                  #:row-index-offset (sub1 (expt 2 32))))))

  (define unwritable (build-path "/" "rkt-polars-no-such-directory-45" "out.parquet"))
  (check-exn #rx"^dataframe-write-parquet: failed to write parquet to .*: cannot create file: "
             (lambda () (dataframe-write-parquet cities unwritable)))

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
  (define junk (in-scratch "junk.bin"))
  (call-with-output-file junk
    (lambda (out) (void (write-string "this is not parquet" out)))
    #:exists 'replace)
  (check-exn #rx"^dataframe-read-parquet: failed to read parquet from .*: .*PAR1"
             (lambda () (dataframe-read-parquet junk)))
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

  (define compressible
    (dataframe-new (list (series-new-i64 "n" (for/list ([i (in-range 20000)]) (modulo i 7)))
                         (series-new-str "s" (for/list ([i (in-range 20000)])
                                               (if (even? i) "even" "odd"))))))
  (define (written-size . kvs)
    (define path (in-scratch "sized.parquet"))
    (keyword-apply/sorted dataframe-write-parquet kvs compressible path)
    (check-equal? (frame-values (dataframe-read-parquet path)) (frame-values compressible)
                  (format "~s" kvs))
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

  (define ((blamed? who) e)
    (and (exn:fail:contract:blame? e)
         (regexp-match? (regexp (format "^~a: contract violation" who)) (exn-message e))))
  (for ([kvs (list '((#:columns . ("a" 0))) '((#:columns . "a")) '((#:columns . (1.5)))
                   `((#:columns ,(expt 2 63)))
                   '((#:n-rows . -1)) `((#:n-rows . ,(expt 2 64)))
                   '((#:row-index-name . a)) '((#:row-index-offset . -1))
                   `((#:row-index-offset . ,(expt 2 32)))
                   '((#:parallel . row_groups)) '((#:use-statistics . 1)) '((#:glob . "no"))
                   '((#:missing-columns . ignore)) '((#:include-file-paths . #t))
                   '((#:columns . ("a\u0000zz"))) '((#:row-index-name . "i\u0000j"))
                   '((#:include-file-paths . "f\u0000g")))])
    (check-exn (blamed? 'dataframe-read-parquet)
               (lambda () (keyword-apply/sorted contracted:dataframe-read-parquet kvs
                                                numbers-parquet))
               (format "~s" kvs)))
  (define (unexpected? keyword who)
    (regexp (format "^application: procedure does not expect an argument with given keyword\n  procedure: ~a\n  given keyword: ~a"
                    who keyword)))
  (check-exn (unexpected? '#:cache 'dataframe-read-parquet)
             (lambda () (contracted:dataframe-read-parquet numbers-parquet #:cache #f)))
  (check-exn (unexpected? '#:columns 'lazyframe-scan-parquet)
             (lambda () (contracted:lazyframe-scan-parquet numbers-parquet #:columns '("a"))))
  (check-exn (blamed? 'lazyframe-scan-parquet)
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
                   `((#:row-group-size . ,(expt 2 64))) `((#:data-page-size . ,(expt 2 64))))])
    (check-exn (blamed? 'dataframe-write-parquet)
               (lambda () (keyword-apply/sorted contracted:dataframe-write-parquet kvs
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
  (check-exn (blamed? 'lazyframe-scan-parquet)
             (lambda () (contracted:lazyframe-scan-parquet produce-parquet #:missing-columns 'ignore)))
  (check-exn (blamed? 'dataframe-write-parquet)
             (lambda () (contracted:dataframe-write-parquet (dataframe-read-parquet produce-parquet)
                                                            (in-scratch "raw.parquet")
                                                            #:compression 'lzo)))
  (check-regexp-match
   #rx"^lazyframe-explain: failed to explain the query: [^\n]*\"colour\""
   (message-of (lambda ()
                 (lazyframe-explain
                  (lazyframe-select (dataframe-lazy (dataframe-read-parquet produce-parquet))
                                    (list (col "colour")))))))

  (define (settle!)
    (for ([_ (in-range 4)])
      (collect-garbage)
      (sleep 0.1)))
  (define (drops-once thunk)
    (settle!)
    (define before (dataframe-drop-count))
    (dataframe-drop (thunk))
    (settle!)
    (- (dataframe-drop-count) before))
  (check-equal? (drops-once (lambda () (dataframe-read-parquet numbers-parquet))) 1)
  (check-equal? (drops-once (lambda () (dataframe-read-parquet numbers-parquet #:columns '(0)
                                                               #:row-index-name "i")))
                1)
  (check-equal? (drops-once (lambda () (lazyframe-collect (lazyframe-scan-parquet parts
                                                                                  #:n-rows 2))))
                1)

  (delete-directory/files scratch))
