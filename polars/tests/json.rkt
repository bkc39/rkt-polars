#lang racket/base

(module+ test
  (require rackunit
           racket/file
           (prefix-in contracted: polars/private/json)
           (submod polars/private/json internal)
           (only-in polars/private/expr lazyframe-collect)
           (only-in polars/private/foreign
                    dataframe-column dataframe-column-names dataframe-drop dataframe-drop-count
                    dataframe-height dataframe-new last-error-message series-dtype
                    series-new-f64 series-new-i32 series-new-i64 series-new-str
                    series-sum-f64)
           (only-in polars/tests/test-helpers
                    apply-keywords contract-violation-of drops-once scratch-file))

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
  (check-equal? (dataframe-height (dataframe-read-json-lines cities-ndjson
                                                             #:n-rows (sub1 (expt 2 64))
                                                             #:infer-schema-length (sub1 (expt 2 64))
                                                             #:batch-size (sub1 (expt 2 64))))
                3)
  (for ([kvs (in-list `(((#:n-rows . ,(expt 2 64))) ((#:n-rows . ,(+ 2 (expt 2 64))))
                        ((#:infer-schema-length . ,(expt 2 64))) ((#:batch-size . ,(expt 2 64)))
                        ((#:row-index-name . "i\u0000x")) ((#:include-file-paths . "p\u0000x"))
                        ((#:row-index-name . "p\u0000x") (#:include-file-paths . "p\u0000y"))
                        ((#:schema . (("a\u0000zzz" . i64))))))])
    (check-exn (contract-violation-of 'dataframe-read-json-lines)
               (lambda () (apply-keywords contracted:dataframe-read-json-lines kvs cities-ndjson))
               (format "~s" kvs)))
  (for ([kvs (in-list '(((#:infer-schema-length . 0)) ((#:batch-size . 0)) ((#:n-rows . -1))
                        ((#:row-index-offset . -1)) ((#:row-index-offset . 4294967296))
                        ((#:schema . (("a" . i8)))) ((#:schema-overrides . (("a" . time))))
                        ((#:schema . (("a" . (duration microseconds)))))
                        ((#:row-index-name . "i") (#:include-file-paths . "i"))))])
    (check-exn (contract-violation-of 'dataframe-read-json-lines)
               (lambda () (apply-keywords contracted:dataframe-read-json-lines kvs cities-ndjson))
               (format "~s" kvs)))
  (check-exn (contract-violation-of 'dataframe-write-json-lines)
             (lambda () (contracted:dataframe-write-json-lines cities cities-ndjson
                                                              #:check-extension 'yes)))

  (for ([read (list (lambda () (dataframe-read-json rows #:schema '(("foo" . i32))))
                    (lambda () (dataframe-read-json-lines cities-ndjson #:n-rows 1)))])
    (check-equal? (drops-once dataframe-drop-count dataframe-drop read) 1))

  (delete-directory/files scratch))
