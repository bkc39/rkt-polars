#lang racket/base

(require ffi/unsafe
         ffi/unsafe/alloc
         racket/match
         (only-in racket/contract/base
                  and/c contract-out flat-named-contract listof or/c)
         (only-in polars/private/expr-core
                  _LazyFrame-ptr/null LazyFrame-ptr? define-compat lazyframe-drop)
         (only-in polars/private/foreign
                  _DataFrame-ptr _DataFrame-ptr/null DataFrame-ptr? call/foreign-error
                  dataframe-drop path->complete-string)
         (only-in polars/private/io-contracts
                  column-index/c column-name/c given row-index/c size/c)
         (only-in polars/private/io-options define-io-options keyword-forwarder)
         (only-in polars/private/resource _string-list))

(provide parquet-reader parquet-scanner parquet-writer
         parquet-reader/c parquet-scanner/c parquet-writer/c
         parquet-read-arguments parquet-scan-arguments parquet-write-arguments
         (contract-out
          [dataframe-read-parquet (parquet-reader/c DataFrame-ptr?)]
          [lazyframe-scan-parquet (parquet-scanner/c LazyFrame-ptr?)]
          [dataframe-write-parquet (parquet-writer/c DataFrame-ptr?)]))

(module+ internal
  (provide dataframe-read-parquet dataframe-write-parquet dataframe-write-parquet/raw
           lazyframe-scan-parquet make-CompatParquetWriteOptions))

(define parallel-codes
  '((auto . 0) (columns . 1) (row-groups . 2) (prefiltered . 3) (none . 4)))

(define compression-codes
  '((uncompressed . 0) (snappy . 1) (gzip . 2) (brotli . 3) (lz4 . 4) (zstd . 5)))

(define compression-levels
  '((gzip 0 9) (brotli 0 11) (zstd 1 22)))

(define statistic-bits
  '((min . 1) (max . 2) (distinct-count . 4) (null-count . 8)))

(define (symbols/c name table)
  (flat-named-contract name (apply or/c (map car table))))

(define parquet-parallel/c (symbols/c 'parquet-parallel/c parallel-codes))
(define parquet-compression/c (symbols/c 'parquet-compression/c compression-codes))
(define parquet-statistic/c (symbols/c 'parquet-statistic/c statistic-bits))

(define (complete-statistics? names)
  (or (null? names)
      (and (memq 'min names) (memq 'max names) (memq 'null-count names) #t)))

(define parquet-statistics/c
  (flat-named-contract
   'parquet-statistics/c
   (or/c boolean? 'full (and/c (listof parquet-statistic/c) complete-statistics?))))

(define (code table v) (cdr (assq v table)))

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

(define-io-options parquet-read-options
  ([(parquet-reader/c range/c) read-keywords ([path path-string?]) range/c
    #:arguments parquet-read-arguments #:omit (#:cache)]
   [(parquet-scanner/c range/c) scan-keywords ([path path-string?]) range/c
    #:arguments parquet-scan-arguments #:omit (#:columns)])
  ([#:columns columns (or/c (listof column-name/c) (listof column-index/c) #f) #f]
   [#:n-rows n-rows (or/c size/c #f) #f]
   [#:row-index-name row-index-name (or/c column-name/c #f) #f]
   [#:row-index-offset row-index-offset row-index/c 0]
   [#:parallel parallel parquet-parallel/c 'auto]
   [#:use-statistics use-statistics boolean? #t]
   [#:glob glob boolean? #t]
   [#:rechunk rechunk boolean? #f]
   [#:low-memory low-memory boolean? #f]
   [#:include-file-paths include-file-paths (or/c column-name/c #f) #f]
   [#:missing-columns missing-columns (or/c 'raise 'insert) 'raise]
   [#:cache cache boolean? #t])
  (read-call (make-CompatParquetReadOptions
              (and n-rows #t) (code parallel-codes parallel) use-statistics low-memory
              rechunk cache glob (eq? missing-columns 'insert) row-index-offset (or n-rows 0))
             row-index-name include-file-paths columns))

(define-io-options parquet-write-options
  ([(parquet-writer/c frame/c) write-keywords ([frame frame/c] [path path-string?]) void?
    #:arguments parquet-write-arguments])
  ([#:compression compression parquet-compression/c 'zstd]
   [#:compression-level compression-level (or/c exact-integer? #f) #f]
   [#:statistics statistics parquet-statistics/c #t]
   [#:row-group-size row-group-size (or/c size/c #f) #f]
   [#:data-page-size data-page-size (or/c size/c #f) #f])
  #:pre/desc (compression compression-level) (level-problem compression compression-level)
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
        (names : _string-list)
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

(define (read-path who path options)
  (path->complete-string who path #:glob? (CompatParquetReadOptions-glob options)))

(define (columns-kind columns)
  (match columns
    [#f 0]
    [(list (? string?) ...) 1]
    [_ 2]))

(define (parquet-reader who)
  (keyword-forwarder
   who parquet-read-options read-keywords 1
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
   who parquet-read-options scan-keywords 1
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
   who parquet-write-options write-keywords 2
   (lambda (options frame path)
     (define complete (path->complete-string who path))
     (void (call/foreign-error who
                               (lambda () (dataframe-write-parquet/raw frame complete options))
                               #:ok? zero?
                               "failed to write parquet to ~a" path)))))

(define dataframe-read-parquet (parquet-reader 'dataframe-read-parquet))
(define lazyframe-scan-parquet (parquet-scanner 'lazyframe-scan-parquet))
(define dataframe-write-parquet (parquet-writer 'dataframe-write-parquet))
