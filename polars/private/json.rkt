#lang racket/base

(require ffi/unsafe
         ffi/unsafe/alloc
         racket/match
         syntax/parse/define
         (for-syntax racket/base)
         (only-in racket/contract/base
                  [-> ->/c] ->* and/c cons/c contract-out flat-named-contract
                  listof or/c)
         (only-in polars/private/expr-core _LazyFrame-ptr/null LazyFrame-ptr? lazyframe-drop)
         (only-in polars/private/foreign
                  ->compat-dtype _c-string _CompatDType _DataFrame-ptr _DataFrame-ptr/null
                  DataFrame-ptr? call/foreign-error dataframe-drop define-compat
                  enum-dtype? path->complete-string)
         (only-in polars/private/generic/dtype dtype-spec? normalize-dtype)
         (only-in polars/private/io-contracts
                  column-name/c distinct-names? given positive-size/c row-index/c size/c)
         (only-in polars/private/io-options define-io-options keyword-forwarder)
         (only-in polars/private/resource _str-list _str/null))

(provide json-reader json-writer json-reader/c
         ndjson-arguments ndjson-reader ndjson-scanner ndjson-writer ndjson-reader/c
         ndjson-writer/c ndjson-writer-arguments
         (contract-out
          [dataframe-read-json (json-reader/c DataFrame-ptr?)]
          [dataframe-write-json (->/c DataFrame-ptr? path-string? void?)]
          [dataframe-read-json-lines (ndjson-reader/c DataFrame-ptr?)]
          [lazyframe-scan-json-lines (ndjson-reader/c LazyFrame-ptr?)]
          [dataframe-write-json-lines (ndjson-writer/c DataFrame-ptr?)]))

(define json-dtype/c
  (flat-named-contract
   'json-dtype/c
   (lambda (v) (and (dtype-spec? v) (not (enum-dtype? v))))))

(define json-schema/c
  (flat-named-contract 'json-schema/c
                       (and/c (listof (cons/c column-name/c json-dtype/c)) distinct-names?)))

(define (json-reader/c result/c)
  (->* (path-string?)
       (#:schema (or/c #f json-schema/c)
        #:schema-overrides json-schema/c
        #:infer-schema-length (or/c #f positive-size/c))
       result/c))

(define-cstruct _CompatJsonOptions
  ([has-schema _stdbool]
   [has-infer-schema-length _stdbool]
   [infer-schema-length _size]
   [schema-len _size]
   [overrides-len _size]))

(define-compat dataframe-read-json/raw
  (_fun _c-string
        _CompatJsonOptions
        _str-list
        (_list i _CompatDType)
        _str-list
        (_list i _CompatDType)
        -> _DataFrame-ptr/null)
  #:c-id dataframe_read_json_with_options_v2
  #:wrap (allocator dataframe-drop))

(define-compat dataframe-write-json/raw
  (_fun _DataFrame-ptr _c-string -> _int32)
  #:c-id dataframe_write_json)

(define (field-dtypes fields)
  (map (compose1 ->compat-dtype normalize-dtype cdr) fields))

(define (json-reader who)
  (procedure-rename
   (lambda (path
            #:schema [schema #f]
            #:schema-overrides [schema-overrides '()]
            #:infer-schema-length [infer-schema-length 100])
     (define fields (or schema '()))
     (define options
       (make-CompatJsonOptions (and schema #t)
                               (and infer-schema-length #t)
                               (or infer-schema-length 0)
                               (length fields)
                               (length schema-overrides)))
     (define p (path->complete-string who path))
     (call/foreign-error who
                         (lambda ()
                           (dataframe-read-json/raw p options
                                                    (map car fields) (field-dtypes fields)
                                                    (map car schema-overrides)
                                                    (field-dtypes schema-overrides)))
                         "failed to read json from ~a" path))
   who))

(define (json-writer who)
  (procedure-rename
   (lambda (df path)
     (define p (path->complete-string who path))
     (void (call/foreign-error who
                               (lambda () (dataframe-write-json/raw df p))
                               #:ok? zero?
                               "failed to write json to ~a" path)))
   who))

(define dataframe-read-json (json-reader 'dataframe-read-json))
(define dataframe-write-json (json-writer 'dataframe-write-json))

(define ndjson-dtype/c
  (flat-named-contract
   'ndjson-dtype/c
   (lambda (v)
     (and (dtype-spec? v)
          (match (normalize-dtype v)
            [(or 'boolean 'int32 'int64 'uint32 'uint64 'float32 'float64 'string 'date
                 'datetime 'categorical 'null (list* 'datetime _))
             #t]
            [_ #f])))))

(define ndjson-schema/c
  (flat-named-contract 'ndjson-schema/c
                       (and/c (listof (cons/c column-name/c ndjson-dtype/c)) distinct-names?)))

(define (distinct-columns? row-index-name include-file-paths)
  (define name (given row-index-name #f))
  (not (and name (equal? name (given include-file-paths #f)))))

(define compression-codes (hasheq 'uncompressed 0 'gzip 1 'zstd 2))

(define compression-levels (hasheq 'gzip '(0 . 9) 'zstd '(1 . 22)))

(define (level-fits? compression compression-level)
  (define level (given compression-level #f))
  (define bounds (hash-ref compression-levels (given compression 'uncompressed) #f))
  (cond
    [(not level) #t]
    [bounds (<= (car bounds) level (cdr bounds))]
    [else #f]))

(define-cstruct _CompatNdjsonOptions
  ([has-schema _stdbool]
   [has-infer-schema-length _stdbool]
   [has-batch-size _stdbool]
   [has-n-rows _stdbool]
   [low-memory _stdbool]
   [rechunk _stdbool]
   [ignore-errors _stdbool]
   [infer-schema-length _size]
   [batch-size _size]
   [n-rows _size]
   [row-index-offset _size]
   [schema-len _size]
   [overrides-len _size]))

(define-syntax-parse-rule (_ndjson-fun (~literal ->) result:expr)
  (_fun _c-string _CompatNdjsonOptions
        _str-list (_list i _CompatDType)
        _str-list (_list i _CompatDType)
        _str/null _str/null
        -> result))

(define-compat dataframe-read-ndjson/raw (_ndjson-fun -> _DataFrame-ptr/null)
  #:c-id dataframe_read_ndjson_with_options_v2
  #:wrap (allocator dataframe-drop))

(define-compat lazyframe-scan-ndjson/raw (_ndjson-fun -> _LazyFrame-ptr/null)
  #:c-id lazyframe_scan_ndjson_with_options_v2
  #:wrap (allocator lazyframe-drop))

(define-compat dataframe-write-ndjson/raw
  (_fun _DataFrame-ptr _c-string _uint8 _stdbool _uint32 _stdbool -> _int32)
  #:c-id dataframe_write_ndjson_with_options)

(define-io-options ndjson-options
  ([(ndjson-reader/c result/c) ndjson-keywords ([path path-string?]) result/c
    #:arguments ndjson-arguments])
  ([#:schema schema (or/c ndjson-schema/c #f) #f]
   [#:schema-overrides schema-overrides ndjson-schema/c '()]
   [#:infer-schema-length infer-schema-length (or/c positive-size/c #f) 100]
   [#:batch-size batch-size (or/c positive-size/c #f) 1024]
   [#:n-rows n-rows (or/c size/c #f) #f]
   [#:low-memory low-memory boolean? #f]
   [#:rechunk rechunk boolean? #f]
   [#:row-index-name row-index-name (or/c column-name/c #f) #f]
   [#:row-index-offset row-index-offset row-index/c 0]
   [#:ignore-errors ignore-errors boolean? #f]
   [#:include-file-paths include-file-paths (or/c column-name/c #f) #f])
  #:pre (row-index-name include-file-paths)
  "#:row-index-name and #:include-file-paths must name different columns"
  (distinct-columns? row-index-name include-file-paths)
  (let ([fields (or schema '())])
    (list (make-CompatNdjsonOptions (and schema #t)
                                    (and infer-schema-length #t)
                                    (and batch-size #t)
                                    (and n-rows #t)
                                    low-memory
                                    rechunk
                                    ignore-errors
                                    (or infer-schema-length 0)
                                    (or batch-size 0)
                                    (or n-rows 0)
                                    row-index-offset
                                    (length fields)
                                    (length schema-overrides))
          (map car fields)
          (field-dtypes fields)
          (map car schema-overrides)
          (field-dtypes schema-overrides)
          row-index-name
          include-file-paths)))

(define (ndjson-procedure who entry message)
  (keyword-forwarder
   who ndjson-options ndjson-keywords 1
   (lambda (arguments path)
     (define p (path->complete-string who path #:glob? #t))
     (call/foreign-error who (lambda () (apply entry p arguments)) message path))))

(define (ndjson-reader who)
  (ndjson-procedure who dataframe-read-ndjson/raw "failed to read ndjson from ~a"))

(define (ndjson-scanner who)
  (ndjson-procedure who lazyframe-scan-ndjson/raw "failed to scan ~a"))

(define-io-options ndjson-write-options
  ([(ndjson-writer/c frame/c) ndjson-write-keywords ([frame frame/c] [path path-string?]) void?
    #:arguments ndjson-writer-arguments])
  ([#:compression compression (or/c 'uncompressed 'gzip 'zstd) 'uncompressed]
   [#:compression-level compression-level (or/c exact-nonnegative-integer? #f) #f]
   [#:check-extension check-extension boolean? #t])
  #:pre (compression compression-level)
  "#:compression-level needs #:compression 'gzip (a level from 0 to 9) or 'zstd (1 to 22)"
  (level-fits? compression compression-level)
  (list (hash-ref compression-codes compression)
        (and compression-level #t)
        (or compression-level 0)
        check-extension))

(define (ndjson-writer who)
  (keyword-forwarder
   who ndjson-write-options ndjson-write-keywords 2
   (lambda (arguments frame path)
     (define p (path->complete-string who path))
     (void (call/foreign-error who
                               (lambda () (apply dataframe-write-ndjson/raw frame p arguments))
                               #:ok? zero?
                               "failed to write ndjson to ~a" path)))))

(define dataframe-read-json-lines (ndjson-reader 'dataframe-read-json-lines))
(define lazyframe-scan-json-lines (ndjson-scanner 'lazyframe-scan-json-lines))
(define dataframe-write-json-lines (ndjson-writer 'dataframe-write-json-lines))

(module+ internal
  (provide dataframe-read-json dataframe-read-json-lines dataframe-write-json
           dataframe-write-json-lines lazyframe-scan-json-lines))
