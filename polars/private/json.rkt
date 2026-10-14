#lang racket/base

(require ffi/unsafe
         ffi/unsafe/alloc
         (only-in racket/contract/base
                  [-> ->/c] ->* and/c cons/c contract-out flat-named-contract listof or/c)
         (only-in racket/list check-duplicates)
         (only-in polars/private/foreign
                  ->compat-dtype _CompatDType _DataFrame-ptr _DataFrame-ptr/null
                  DataFrame-ptr? call/foreign-error dataframe-drop define-compat
                  enum-dtype? path->complete-string)
         (only-in polars/private/generic/dtype dtype-spec? normalize-dtype)
         (only-in polars/private/io-contracts column-name/c positive-size/c)
         (only-in polars/private/resource _string-list))

(provide json-reader json-writer json-reader/c
         (contract-out
          [dataframe-read-json (json-reader/c DataFrame-ptr?)]
          [dataframe-write-json (->/c DataFrame-ptr? path-string? void?)]))

(define json-dtype/c
  (flat-named-contract
   'json-dtype/c
   (lambda (v) (and (dtype-spec? v) (not (enum-dtype? v))))))

(define (distinct-names? fields)
  (not (check-duplicates (map car fields))))

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
  (_fun _string/utf-8
        _CompatJsonOptions
        _string-list
        (_list i _CompatDType)
        _string-list
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

(module+ test
  (require rackunit
           racket/file
           (prefix-in contracted: (submod ".."))
           (only-in polars/private/foreign
                    dataframe-column dataframe-column-names dataframe-drop-count
                    dataframe-new last-error-message series-dtype series-new-i64
                    series-new-str)
           (only-in polars/private/generic/test-fixtures
                    apply-keywords contract-violation-of scratch-file))

  (define scratch (make-temporary-directory "rkt-polars-json-~a"))

  (define rows (scratch-file scratch "rows.json" "[{\"foo\":1,\"bar\":6},{\"foo\":2,\"bar\":7.5}]"))
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
  (check-equal? (dataframe-column-names
                 (contracted:dataframe-read-json rows #:infer-schema-length (sub1 (expt 2 64))))
                '("foo" "bar"))
  (check-exn (contract-violation-of 'dataframe-write-json)
             (lambda () (contracted:dataframe-write-json 'frame written)))
  (for ([kvs (in-list `(((#:infer-schema-length . 0))
                        ((#:infer-schema-length . ,(expt 2 64)))
                        ((#:infer-schema-length . ,(add1 (expt 2 64))))
                        ((#:schema . (("a" . (enum x y)))))
                        ((#:schema . (("a\u0000zzz" . i64))))
                        ((#:schema-overrides . (("a" . i32) ("a" . f64))))
                        ((#:schema-overrides . (("foo\u0000x" . str))))))])
    (check-exn (contract-violation-of 'dataframe-read-json)
               (lambda () (apply-keywords contracted:dataframe-read-json kvs rows))
               (format "~s" kvs)))

  (define (settle!)
    (for ([_ (in-range 4)])
      (collect-garbage)
      (sleep 0.1)))
  (settle!)
  (define before (dataframe-drop-count))
  (dataframe-drop (dataframe-read-json rows #:schema '(("foo" . i32))))
  (settle!)
  (check-equal? (- (dataframe-drop-count) before) 1)

  (delete-directory/files scratch))
