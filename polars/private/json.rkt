#lang racket/base

(require ffi/unsafe
         ffi/unsafe/alloc
         racket/match
         syntax/parse/define
         (only-in racket/contract/base
                  [-> ->/c] ->* ->i and/c cons/c contract-out flat-named-contract integer-in
                  listof or/c unsupplied-arg?)
         (only-in racket/list check-duplicates)
         (only-in polars/private/expr-core _LazyFrame-ptr/null LazyFrame-ptr? lazyframe-drop)
         (only-in polars/private/foreign
                  ->compat-dtype _CompatDType _DataFrame-ptr _DataFrame-ptr/null
                  DataFrame-ptr? call/foreign-error dataframe-drop define-compat
                  enum-dtype? path->complete-string)
         (only-in polars/private/generic/dtype dtype-spec? normalize-dtype))

(provide json-reader json-writer json-reader/c
         ndjson-reader ndjson-scanner ndjson-writer ndjson-reader/c ndjson-writer/c
         (contract-out
          [dataframe-read-json (json-reader/c DataFrame-ptr?)]
          [dataframe-write-json (->/c DataFrame-ptr? path-string? void?)]
          [dataframe-read-json-lines (ndjson-reader/c DataFrame-ptr?)]
          [lazyframe-scan-json-lines (ndjson-reader/c LazyFrame-ptr?)]
          [dataframe-write-json-lines (ndjson-writer/c DataFrame-ptr?)]))

(define size-max (sub1 (expt 2 64)))

(define column-name/c
  (flat-named-contract
   'column-name/c
   (lambda (v) (and (string? v) (not (for/or ([c (in-string v)]) (char=? c #\nul)))))))

(define json-dtype/c
  (flat-named-contract
   'json-dtype/c
   (lambda (v) (and (dtype-spec? v) (not (enum-dtype? v))))))

(define (distinct-names? fields)
  (not (check-duplicates (map car fields))))

(define json-schema/c
  (and/c (listof (cons/c column-name/c json-dtype/c)) distinct-names?))

(define (json-reader/c result/c)
  (->* (path-string?)
       (#:schema (or/c #f json-schema/c)
        #:schema-overrides json-schema/c
        #:infer-schema-length (or/c #f (integer-in 1 size-max)))
       result/c))

(define-cstruct _CompatJsonOptions
  ([has-schema _stdbool]
   [has-infer-schema-length _stdbool]
   [infer-schema-length _size]
   [schema-len _size]
   [overrides-len _size]))

(define-compat dataframe-read-json/raw
  (_fun _string/utf-8
        _CompatJsonOptions
        (_list i _string/utf-8)
        (_list i _CompatDType)
        (_list i _string/utf-8)
        (_list i _CompatDType)
        -> _DataFrame-ptr/null)
  #:c-id dataframe_read_json_with_options
  #:wrap (allocator dataframe-drop))

(define-compat dataframe-write-json/raw
  (_fun _DataFrame-ptr _string/utf-8 -> _int32)
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
                 'datetime 'categorical (list* 'datetime _))
             #t]
            [_ #f])))))

(define ndjson-schema/c
  (and/c (listof (cons/c string? ndjson-dtype/c)) distinct-names?))

(define max-row-index (sub1 (expt 2 32)))

(define (distinct-columns? row-index-name include-file-paths)
  (define (given v) (and (not (unsupplied-arg? v)) v))
  (not (and (given row-index-name)
            (equal? (given row-index-name) (given include-file-paths)))))

(define (ndjson-reader/c result/c)
  (->i ([path path-string?])
       (#:schema [schema (or/c #f ndjson-schema/c)]
        #:schema-overrides [schema-overrides ndjson-schema/c]
        #:infer-schema-length [infer-schema-length (or/c #f exact-positive-integer?)]
        #:batch-size [batch-size (or/c #f exact-positive-integer?)]
        #:n-rows [n-rows (or/c #f exact-nonnegative-integer?)]
        #:low-memory [low-memory boolean?]
        #:rechunk [rechunk boolean?]
        #:row-index-name [row-index-name (or/c #f string?)]
        #:row-index-offset [row-index-offset (integer-in 0 max-row-index)]
        #:ignore-errors [ignore-errors boolean?]
        #:include-file-paths [include-file-paths (or/c #f string?)])
       #:pre/name (row-index-name include-file-paths)
       "#:row-index-name and #:include-file-paths must name different columns"
       (distinct-columns? row-index-name include-file-paths)
       [result result/c]))

(define compression-codes (hasheq 'uncompressed 0 'gzip 1 'zstd 2))

(define compression-levels (hasheq 'gzip '(0 . 9) 'zstd '(1 . 22)))

(define (level-fits? compression compression-level)
  (define (given v default) (if (unsupplied-arg? v) default v))
  (define level (given compression-level #f))
  (define bounds (hash-ref compression-levels (given compression 'uncompressed) #f))
  (cond
    [(not level) #t]
    [bounds (<= (car bounds) level (cdr bounds))]
    [else #f]))

(define (ndjson-writer/c frame/c)
  (->i ([df frame/c] [path path-string?])
       (#:compression [compression (or/c 'uncompressed 'gzip 'zstd)]
        #:compression-level [compression-level (or/c #f exact-nonnegative-integer?)]
        #:check-extension [check-extension boolean?])
       #:pre/name (compression compression-level)
       "#:compression-level needs #:compression 'gzip (a level from 0 to 9) or 'zstd (1 to 22)"
       (level-fits? compression compression-level)
       [result void?]))

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

(define-syntax-parse-rule (define-ndjson-entry name:id c-id:id result:expr drop:id)
  (define-compat name
    (_fun _string/utf-8
          _CompatNdjsonOptions
          (_list i _string/utf-8)
          (_list i _CompatDType)
          (_list i _string/utf-8)
          (_list i _CompatDType)
          _string/utf-8
          _string/utf-8
          -> result)
    #:c-id c-id
    #:wrap (allocator drop)))

(define-ndjson-entry dataframe-read-ndjson/raw dataframe_read_ndjson_with_options
  _DataFrame-ptr/null dataframe-drop)

(define-ndjson-entry lazyframe-scan-ndjson/raw lazyframe_scan_ndjson_with_options
  _LazyFrame-ptr/null lazyframe-drop)

(define-compat dataframe-write-ndjson/raw
  (_fun _DataFrame-ptr _string/utf-8 _uint8 _stdbool _uint32 _stdbool -> _int32)
  #:c-id dataframe_write_ndjson_with_options)

(struct ndjson-call (options schema-names schema-dtypes override-names override-dtypes
                             row-index-name include-file-paths))

(define (ndjson-options #:schema [schema #f]
                        #:schema-overrides [schema-overrides '()]
                        #:infer-schema-length [infer-schema-length 100]
                        #:batch-size [batch-size 1024]
                        #:n-rows [n-rows #f]
                        #:low-memory [low-memory #f]
                        #:rechunk [rechunk #f]
                        #:row-index-name [row-index-name #f]
                        #:row-index-offset [row-index-offset 0]
                        #:ignore-errors [ignore-errors #f]
                        #:include-file-paths [include-file-paths #f])
  (define fields (or schema '()))
  (ndjson-call (make-CompatNdjsonOptions (and schema #t)
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
               include-file-paths))

(define (ndjson-procedure who entry message)
  (define-values (_ option-keywords) (procedure-keywords ndjson-options))
  (procedure-rename
   (procedure-reduce-keyword-arity
    (make-keyword-procedure
     (lambda (keywords arguments path)
       (match-define (ndjson-call options schema-names schema-dtypes override-names
                                  override-dtypes row-index-name include-file-paths)
         (keyword-apply ndjson-options keywords arguments '()))
       (define p (path->complete-string who path #:glob? #t))
       (call/foreign-error who
                           (lambda ()
                             (entry p options schema-names schema-dtypes override-names
                                    override-dtypes row-index-name include-file-paths))
                           message path)))
    1 '() option-keywords)
   who))

(define (ndjson-reader who)
  (ndjson-procedure who dataframe-read-ndjson/raw "failed to read ndjson from ~a"))

(define (ndjson-scanner who)
  (ndjson-procedure who lazyframe-scan-ndjson/raw "failed to scan ~a"))

(define (ndjson-writer who)
  (procedure-rename
   (lambda (df path
            #:compression [compression 'uncompressed]
            #:compression-level [compression-level #f]
            #:check-extension [check-extension #t])
     (define p (path->complete-string who path))
     (void (call/foreign-error who
                               (lambda ()
                                 (dataframe-write-ndjson/raw df p
                                                             (hash-ref compression-codes compression)
                                                             (and compression-level #t)
                                                             (or compression-level 0)
                                                             check-extension))
                               #:ok? zero?
                               "failed to write ndjson to ~a" path)))
   who))

(define dataframe-read-json-lines (ndjson-reader 'dataframe-read-json-lines))
(define lazyframe-scan-json-lines (ndjson-scanner 'lazyframe-scan-json-lines))
(define dataframe-write-json-lines (ndjson-writer 'dataframe-write-json-lines))

(module+ test
  (require rackunit
           racket/file
           (prefix-in contracted: (submod ".."))
           (only-in polars/private/expr lazyframe-collect)
           (only-in polars/private/foreign
                    dataframe-column dataframe-column-names dataframe-drop-count
                    dataframe-height dataframe-new last-error-message series-dtype
                    series-new-f64 series-new-i32 series-new-i64 series-new-str
                    series-sum-f64))

  (define scratch (make-temporary-directory "rkt-polars-json-~a"))
  (define (scratch-file name text)
    (define path (build-path scratch name))
    (call-with-output-file path #:exists 'replace (lambda (out) (write-string text out)))
    path)

  (define rows (scratch-file "rows.json" "[{\"foo\":1,\"bar\":6},{\"foo\":2,\"bar\":7.5}]"))
  (define frame (dataframe-read-json rows))
  (check-equal? (dataframe-column-names frame) '("foo" "bar"))
  (check-equal? (series-dtype (dataframe-column frame "bar")) 'float64)
  (check-false (last-error-message))

  (define written (build-path scratch "written.json"))
  (dataframe-write-json
   (dataframe-new (list (series-new-i64 "x" '(1 2)) (series-new-str "s" '("a" "b"))))
   written)
  (check-equal? (file->string written) "[{\"x\":1,\"s\":\"a\"},{\"x\":2,\"s\":\"b\"}]")

  (check-exn #rx"^dataframe-read-json: failed to read json from [^:]*nope.json: cannot open file: "
             (lambda () (dataframe-read-json (build-path scratch "nope.json"))))
  (check-exn #rx"^dataframe-write-json: failed to write json to [^:]*out.json: cannot create file: "
             (lambda () (dataframe-write-json frame (build-path scratch "no" "out.json"))))
  (check-equal? (dataframe-column-names (dataframe-read-json rows)) '("foo" "bar"))
  (check-false (last-error-message))
  (check-exn exn:fail? (lambda () (dataframe-read-json (build-path scratch "nope.json"))))
  (dataframe-write-json frame written)
  (check-false (last-error-message))
  (check-exn #rx"^dataframe-read-json: contract violation"
             (lambda () (contracted:dataframe-read-json rows #:infer-schema-length 0)))
  (check-exn #rx"^dataframe-read-json: contract violation"
             (lambda () (contracted:dataframe-read-json rows #:schema '(("a" . (enum x y))))))
  (check-exn #rx"^dataframe-read-json: contract violation"
             (lambda () (contracted:dataframe-read-json rows
                                                        #:schema-overrides '(("a" . i32) ("a" . f64)))))
  (check-exn #rx"^dataframe-write-json: contract violation"
             (lambda () (contracted:dataframe-write-json 'frame written)))
  (check-equal? (dataframe-column-names
                 (contracted:dataframe-read-json rows #:infer-schema-length (sub1 (expt 2 64))))
                '("foo" "bar"))
  (for ([kvs (in-list `(((#:infer-schema-length . ,(expt 2 64)))
                        ((#:infer-schema-length . ,(add1 (expt 2 64))))
                        ((#:schema . (("a\u0000zzz" . i64))))
                        ((#:schema-overrides . (("foo\u0000x" . str))))))])
    (check-exn #rx"^dataframe-read-json: contract violation"
               (lambda () (keyword-apply contracted:dataframe-read-json (map car kvs) (map cdr kvs)
                                         (list rows)))
               (format "~s" kvs)))

  (define cities
    (dataframe-new
     (list (series-new-str "city" '("Boston" "New York" "Chicago"))
           (series-new-f64 "population_millions" '(0.65 8.8 2.7))
           (series-new-i32 "founded" '(1630 1624 1837)))))
  (define cities-ndjson (build-path scratch "cities.ndjson"))
  (dataframe-write-json-lines cities cities-ndjson)
  (define cities-back (dataframe-read-json-lines cities-ndjson))
  (check-equal? (dataframe-column-names cities-back) '("city" "population_millions" "founded"))
  (check-equal? (series-dtype (dataframe-column cities-back "founded")) 'int64)
  (check-= (series-sum-f64 (dataframe-column cities-back "population_millions")) 12.15 1e-9)
  (check-false (last-error-message))
  (check-equal? (dataframe-height (lazyframe-collect (lazyframe-scan-json-lines cities-ndjson
                                                                                #:n-rows 2)))
                2)
  (check-exn #rx"^dataframe-read-json-lines: failed to read ndjson from [^:]*nope.ndjson: cannot open file: "
             (lambda () (dataframe-read-json-lines (build-path scratch "nope.ndjson"))))
  (check-exn #rx"^dataframe-write-json-lines: failed to write ndjson to [^:]*out.ndjson: "
             (lambda () (dataframe-write-json-lines cities (build-path scratch "no" "out.ndjson"))))
  (check-exn #rx"^lazyframe-scan-json-lines: failed to scan [^:]*cities.ndjson: schema overrides name a column not in the file: \"zzz\"$"
             (lambda () (lazyframe-scan-json-lines cities-ndjson #:schema-overrides '(("zzz" . str)))))
  (for ([kvs (in-list '(((#:infer-schema-length . 0)) ((#:batch-size . 0)) ((#:n-rows . -1))
                        ((#:row-index-offset . -1)) ((#:row-index-offset . 4294967296))
                        ((#:schema . (("a" . i8)))) ((#:schema-overrides . (("a" . time))))
                        ((#:schema . (("a" . (duration microseconds)))))
                        ((#:row-index-name . "i") (#:include-file-paths . "i"))))])
    (define sorted (sort kvs keyword<? #:key car))
    (check-exn #rx"^dataframe-read-json-lines: contract violation"
               (lambda () (keyword-apply contracted:dataframe-read-json-lines
                                         (map car sorted) (map cdr sorted) (list cities-ndjson)))
               (format "~s" kvs)))
  (check-exn #rx"^dataframe-write-json-lines: contract violation"
             (lambda () (contracted:dataframe-write-json-lines cities cities-ndjson
                                                              #:check-extension 'yes)))

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
  (check-equal? (drops-once (lambda () (dataframe-read-json rows #:schema '(("foo" . i32))))) 1)
  (check-equal? (drops-once (lambda () (dataframe-read-json-lines cities-ndjson #:n-rows 1))) 1)

  (delete-directory/files scratch))
