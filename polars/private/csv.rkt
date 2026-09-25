#lang racket/base

(require ffi/unsafe
         ffi/unsafe/alloc
         racket/match
         syntax/parse/define
         (only-in racket/contract/base
                  ->* and/c cons/c contract-out flat-named-contract listof or/c)
         (only-in racket/list check-duplicates)
         (only-in racket/string non-empty-string? string-replace)
         (only-in polars/private/expr-core
                  _LazyFrame-ptr/null LazyFrame-ptr? define-compat lazyframe-drop)
         (only-in polars/private/foreign
                  ->compat-dtype _CompatDType _DataFrame-ptr/null DataFrame-ptr?
                  call/foreign-error dataframe-column dataframe-column-name
                  dataframe-drop dataframe-height dataframe-width
                  path->string-or-string polars-null? series-drop series-dtype
                  series-ref)
         (only-in polars/private/generic/dtype dtype-spec? normalize-dtype))

(provide csv-reader/c
         (contract-out
          [dataframe-read-csv (csv-reader/c DataFrame-ptr?)]
          [lazyframe-scan-csv (csv-reader/c LazyFrame-ptr?)]))

(define csv-char/c
  (flat-named-contract
   'csv-char/c
   (lambda (v)
     (and (char? v)
          (< (char->integer v) 128)
          (not (memv v '(#\newline #\return)))))))

(define csv-dtype/c
  (flat-named-contract
   'csv-dtype/c
   (lambda (v)
     (and (dtype-spec? v)
          (not (eq? v 'time))
          (not (and (pair? v) (eq? (car v) 'duration)))))))

(define schema-overrides/c
  (flat-named-contract
   'schema-overrides/c
   (and/c (listof (cons/c string? csv-dtype/c))
          (lambda (overrides) (not (check-duplicates (map car overrides)))))))

(define null-values/c
  (flat-named-contract 'null-values/c (or/c #f string? (listof string?))))

(define (csv-reader/c range/c)
  (->* (path-string?)
       (#:has-header boolean?
        #:separator csv-char/c
        #:quote-char (or/c #f csv-char/c)
        #:comment-prefix (or/c #f non-empty-string?)
        #:skip-rows exact-nonnegative-integer?
        #:n-rows (or/c #f exact-nonnegative-integer?)
        #:null-values null-values/c
        #:infer-schema-length (or/c #f exact-nonnegative-integer?)
        #:schema-overrides schema-overrides/c
        #:ignore-errors boolean?
        #:try-parse-dates boolean?
        #:encoding (or/c 'utf8 'utf8-lossy)
        #:glob boolean?)
       range/c))

(define-cstruct _CompatCsvOptions
  ([has-header _uint8]
   [separator _uint8]
   [has-quote-char _uint8]
   [quote-char _uint8]
   [ignore-errors _uint8]
   [try-parse-dates _uint8]
   [lossy-utf8 _uint8]
   [has-n-rows _uint8]
   [has-infer-schema-length _uint8]
   [glob _uint8]
   [skip-rows _size]
   [n-rows _size]
   [infer-schema-length _size]))

(define-syntax-parse-rule (define-csv-entry name:id c-id:id result:expr drop:id)
  (define-compat name
    (_fun _string/utf-8
          _CompatCsvOptions
          _string/utf-8
          (null-values : (_list i _string/utf-8))
          (_size = (length null-values))
          (names : (_list i _string/utf-8))
          (_list i _CompatDType)
          (_size = (length names))
          -> result)
    #:c-id c-id
    #:wrap (allocator drop)))

(define-csv-entry dataframe-read-csv/raw dataframe_read_csv_with_options
  _DataFrame-ptr/null dataframe-drop)

(define-csv-entry lazyframe-scan-csv/raw lazyframe_scan_csv_with_options
  _LazyFrame-ptr/null lazyframe-drop)

(struct csv-call (path options comment-prefix null-values names dtypes guard?))

(define (flag v) (if v 1 0))

(define (csv-call-of path has-header separator quote-char comment-prefix
                     skip-rows n-rows null-values infer-schema-length
                     schema-overrides ignore-errors try-parse-dates encoding glob)
  (csv-call (path->string-or-string path)
            (make-CompatCsvOptions
             (flag has-header)
             (char->integer (or separator #\,))
             (flag quote-char)
             (if quote-char (char->integer quote-char) 0)
             (flag ignore-errors)
             (flag try-parse-dates)
             (flag (eq? encoding 'utf8-lossy))
             (flag n-rows)
             (flag infer-schema-length)
             (flag glob)
             skip-rows
             (or n-rows 0)
             (or infer-schema-length 0))
            comment-prefix
            (match null-values
              [#f '()]
              [(? string? value) (list value)]
              [(? list? strings) strings])
            (map car schema-overrides)
            (map (compose1 ->compat-dtype normalize-dtype cdr) schema-overrides)
            (and has-header (not separator))))

(define (apply-csv entry call)
  (match-define (csv-call path options comment-prefix null-values names dtypes _) call)
  (entry path options comment-prefix null-values names dtypes))

(define-syntax-parse-rule (define-csv-reader (name:id path:id call:id) body:expr ...+)
  (define (name path
                #:has-header [has-header #t]
                #:separator [separator #f]
                #:quote-char [quote-char #\"]
                #:comment-prefix [comment-prefix #f]
                #:skip-rows [skip-rows 0]
                #:n-rows [n-rows #f]
                #:null-values [null-values #f]
                #:infer-schema-length [infer-schema-length 100]
                #:schema-overrides [schema-overrides '()]
                #:ignore-errors [ignore-errors #f]
                #:try-parse-dates [try-parse-dates #f]
                #:encoding [encoding 'utf8]
                #:glob [glob #t])
    (define call
      (csv-call-of path has-header separator quote-char comment-prefix
                   skip-rows n-rows null-values infer-schema-length
                   schema-overrides ignore-errors try-parse-dates encoding glob))
    body ...))

(define-csv-reader (lazyframe-scan-csv path call)
  (call/foreign-error 'lazyframe-scan-csv
                      (lambda () (apply-csv lazyframe-scan-csv/raw call))
                      "failed to scan ~a" path))

(define-csv-reader (dataframe-read-csv path call)
  (define df
    (with-racket-hints
      (lambda ()
        (call/foreign-error 'dataframe-read-csv
                            (lambda () (apply-csv dataframe-read-csv/raw call))
                            "failed to read csv from ~a" path))))
  (when (csv-call-guard? call)
    (check-separator df path))
  df)

(define racket-hints
  '(("`infer_schema_length` (e.g. `infer_schema_length=10000`)"
     . "#:infer-schema-length (e.g. #:infer-schema-length 10000, or #f for every row)")
    ("the `dtypes` argument" . "#:schema-overrides")
    ("setting `ignore_errors` to `True`" . "setting #:ignore-errors to #t")
    ("to the `null_values` list" . "to #:null-values")))

(define (with-racket-hints thunk)
  (with-handlers ([exn:fail?
                   (lambda (e)
                     (raise (exn:fail (for/fold ([message (exn-message e)])
                                                ([hint (in-list racket-hints)])
                                        (string-replace message (car hint) (cdr hint)))
                                      (exn-continuation-marks e))))])
    (thunk)))

(define likely-separators '(#\tab #\; #\|))

(define (char-count c s)
  (for/sum ([x (in-string s)]) (if (char=? x c) 1 0)))

(define (first-row-agrees? df header c n)
  (or (zero? (dataframe-height df))
      (let* ([column (dataframe-column df header)]
             [value (and (eq? (series-dtype column) 'string) (series-ref column 0))])
        (series-drop column)
        (or (polars-null? value)
            (and (string? value) (= n (char-count c value)))))))

(define (check-separator df path)
  (when (= (dataframe-width df) 1)
    (define header (dataframe-column-name df 0))
    (for ([c (in-list likely-separators)])
      (define n (char-count c header))
      (when (and (positive? n) (first-row-agrees? df header c n))
        (error 'dataframe-read-csv
               "~a reads as one column whose header splits on ~s into ~a fields; pass #:separator ~s, or #:separator #\\, to keep one column"
               path c (add1 n) c)))))

(module+ test
  (require rackunit
           racket/file
           (only-in polars/private/foreign
                    dataframe-column-names dataframe-drop-count dataframe-new
                    dataframe-shape dataframe-write-csv last-error-message
                    series-new-f64 series-new-i32 series-new-str series-sum-f64))

  (define scratch (make-temporary-directory "rkt-polars-csv-~a"))
  (define (scratch-file name . lines)
    (define path (build-path scratch name))
    (display-lines-to-file lines path #:exists 'replace)
    path)

  (define cities
    (dataframe-new
     (list (series-new-str "city" '("Boston" "New York" "Chicago"))
           (series-new-f64 "population_millions" '(0.65 8.8 2.7))
           (series-new-i32 "founded" '(1630 1624 1837)))))
  (define cities-csv (build-path scratch "cities.csv"))
  (dataframe-write-csv cities cities-csv)
  (define cities-back (dataframe-read-csv cities-csv))
  (check-equal? (call-with-values (lambda () (dataframe-shape cities-back)) list) '(3 3))
  (check-equal? (dataframe-column-names cities-back) '("city" "population_millions" "founded"))
  (check-equal? (series-dtype (dataframe-column cities-back "founded")) 'int64)
  (check-equal? (series-dtype (dataframe-column cities-back "population_millions")) 'float64)
  (check-= (series-sum-f64 (dataframe-column cities-back "population_millions")) 12.15 1e-9)

  (define missing-csv (build-path scratch "no-such-file.csv"))
  (define missing-message
    (with-handlers ([exn:fail? exn-message]) (dataframe-read-csv missing-csv)))
  (check-regexp-match
   #rx"^dataframe-read-csv: failed to read csv from .*: cannot open file: [Nn]o such file"
   missing-message)
  (check-equal? (length (regexp-match* #rx"no-such-file" missing-message)) 1)

  (define na-csv (scratch-file "na.csv" "x" "1" "NA" "3"))
  (make-directory (build-path scratch "parts"))
  (for ([name '("a" "b")] [rows '(("1" "NA") ("NA" "4"))])
    (apply scratch-file (format "parts/~a.csv" name) "x" rows))
  (define parts (build-path scratch "parts" "*.csv"))
  (check-exn #rx"cannot open file" (lambda () (dataframe-read-csv missing-csv)))
  (check-equal? (dataframe-height (dataframe-read-csv na-csv #:null-values "NA")) 3)
  (check-false (last-error-message))
  (check-exn #rx"cannot open file" (lambda () (dataframe-read-csv missing-csv)))
  (check-equal? (dataframe-height (dataframe-read-csv parts #:null-values "NA")) 4)
  (check-false (last-error-message))

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

  (check-equal? (drops-once (lambda () (dataframe-read-csv cities-csv))) 1)
  (check-equal? (drops-once (lambda () (dataframe-read-csv na-csv #:null-values "NA"))) 1)
  (check-equal? (drops-once (lambda () (dataframe-read-csv parts #:null-values "NA"))) 1)

  (let* ([wanted 20]
         [before (dataframe-drop-count)])
    (for ([_ (in-range wanted)])
      (dataframe-read-csv cities-csv))
    ;; finalizers run on their own thread, so assert a lenient fraction
    (settle!)
    (check >= (- (dataframe-drop-count) before) (quotient wanted 2)))

  (delete-directory/files scratch))
