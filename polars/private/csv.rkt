#lang racket/base

(require ffi/unsafe
         ffi/unsafe/alloc
         racket/match
         syntax/parse/define
         (for-syntax racket/base)
         (only-in racket/contract/base
                  ->i and/c cons/c contract-out flat-named-contract listof or/c
                  unsupplied-arg?)
         (only-in racket/list check-duplicates)
         (only-in racket/string non-empty-string?)
         (only-in polars/private/expr-core
                  _LazyFrame-ptr/null LazyFrame-ptr? define-compat lazyframe-drop)
         (only-in polars/private/foreign
                  ->compat-dtype _CompatDType _DataFrame-ptr/null DataFrame-ptr?
                  call/foreign-error dataframe-column dataframe-column-name
                  dataframe-drop dataframe-height dataframe-width
                  path->complete-string polars-null? series-drop series-dtype
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
          (match v
            ['time #f]
            [(cons 'duration _) #f]
            [_ #t])))))

(define (distinct-names? overrides)
  (not (check-duplicates (map car overrides))))

(define (quote-differs? separator quote-char)
  (define (given v default) (if (unsupplied-arg? v) default v))
  (not (eqv? (or (given separator #f) #\,) (given quote-char #\"))))

(define-cstruct _CompatCsvOptions
  ([has-header _stdbool]
   [separator _uint8]
   [has-quote-char _stdbool]
   [quote-char _uint8]
   [ignore-errors _stdbool]
   [try-parse-dates _stdbool]
   [lossy-utf8 _stdbool]
   [has-n-rows _stdbool]
   [has-infer-schema-length _stdbool]
   [glob _stdbool]
   [skip-rows _size]
   [n-rows _size]
   [infer-schema-length _size]))

(struct csv-call (options comment-prefix null-values names dtypes guard?))

(define-syntax-parse-rule
  (define-csv-options (options:id reader/c:id)
    ([kw:keyword name:id contract:expr default:expr] ...)
    #:pre (pre-name:id ...) pre-message:str pre-check:expr
    body:expr)
  (begin
    (define (reader/c range/c)
      (->i ([path path-string?])
           ((~@ kw [name contract]) ...)
           #:pre/name (pre-name ...) pre-message pre-check
           [result range/c]))
    (define (options (~@ kw [name default]) ...)
      body)))

(define-csv-options (csv-options csv-reader/c)
  ([#:has-header has-header boolean? #t]
   [#:separator separator (or/c #f csv-char/c) #f]
   [#:quote-char quote-char (or/c #f csv-char/c) #\"]
   [#:comment-prefix comment-prefix (or/c #f non-empty-string?) #f]
   [#:skip-rows skip-rows exact-nonnegative-integer? 0]
   [#:n-rows n-rows (or/c #f exact-nonnegative-integer?) #f]
   [#:null-values null-values (or/c #f string? (listof string?)) #f]
   [#:infer-schema-length infer-schema-length (or/c #f exact-nonnegative-integer?) 100]
   [#:schema-overrides schema-overrides
                       (and/c (listof (cons/c string? csv-dtype/c)) distinct-names?)
                       '()]
   [#:ignore-errors ignore-errors boolean? #f]
   [#:try-parse-dates try-parse-dates boolean? #f]
   [#:encoding encoding (or/c 'utf8 'utf8-lossy) 'utf8]
   [#:glob glob boolean? #t])
  #:pre (separator quote-char) "quote-char differs from the separator"
  (quote-differs? separator quote-char)
  (csv-call (make-CompatCsvOptions has-header
                                   (char->integer (or separator #\,))
                                   quote-char
                                   (if quote-char (char->integer quote-char) 0)
                                   ignore-errors
                                   try-parse-dates
                                   (eq? encoding 'utf8-lossy)
                                   n-rows
                                   infer-schema-length
                                   glob
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

(define (csv-reader who read)
  (define-values (_ option-keywords) (procedure-keywords csv-options))
  (procedure-rename
   (procedure-reduce-keyword-arity
    (make-keyword-procedure
     (lambda (keywords arguments path)
       (read path (keyword-apply csv-options keywords arguments '()))))
    1 '() option-keywords)
   who))

(define (apply-csv who entry path call)
  (match-define (csv-call options comment-prefix null-values names dtypes _) call)
  (entry (path->complete-string who path #:glob? (CompatCsvOptions-glob options))
         options comment-prefix null-values names dtypes))

(define lazyframe-scan-csv
  (csv-reader
   'lazyframe-scan-csv
   (lambda (path call)
     (call/foreign-error 'lazyframe-scan-csv
                         (lambda () (apply-csv 'lazyframe-scan-csv lazyframe-scan-csv/raw path call))
                         "failed to scan ~a" path))))

(define dataframe-read-csv
  (csv-reader
   'dataframe-read-csv
   (lambda (path call)
     (define df
       (call/foreign-error 'dataframe-read-csv
                           (lambda () (apply-csv 'dataframe-read-csv dataframe-read-csv/raw path call))
                           "failed to read csv from ~a" path))
     (when (csv-call-guard? call)
       (check-separator df path))
     df)))

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
