#lang racket/base

(require ffi/unsafe
         ffi/unsafe/alloc
         racket/match
         syntax/parse/define
         (for-syntax racket/base)
         (only-in racket/contract/base
                  and/c cons/c contract-out flat-named-contract listof or/c)
         (only-in racket/list index-of partition)
         (only-in racket/string non-empty-string?)
         (only-in polars/private/c-integer uint16-max uint16/c)
         (only-in polars/private/expr-core
                  _LazyFrame-ptr/null LazyFrame-ptr? define-compat lazyframe-drop)
         (only-in polars/private/foreign
                  ->compat-dtype _c-string _CompatDType _DataFrame-ptr _DataFrame-ptr/null
                  DataFrame-ptr?
                  call/foreign-error dataframe-column dataframe-column-name
                  dataframe-drop dataframe-height dataframe-width glob-pattern?
                  path->complete-string polars-null? series-drop series-dtype
                  series-ref zoned-datetime-dtype?)
         (only-in polars/private/generic/dtype dtype-spec? normalize-dtype)
         (only-in polars/private/io-contracts
                  column-name/c distinct-names? distinct? given positive-size/c row-index/c
                  size/c)
         (only-in polars/private/io-options define-io-options keyword-forwarder)
         (only-in polars/private/resource _str _str-list _str/null))

(provide csv-reader/c csv-scanner/c csv-writer/c csv-reader csv-scanner csv-writer
         csv-read-arguments csv-scan-arguments csv-write-arguments
         float-precision-max read-keywords scan-keywords
         (contract-out
          [dataframe-read-csv (csv-reader/c DataFrame-ptr?)]
          [lazyframe-scan-csv (csv-scanner/c LazyFrame-ptr?)]
          [dataframe-write-csv (csv-writer/c DataFrame-ptr?)]))

(define (ascii-char? v)
  (and (char? v) (< (char->integer v) 128)))

(define csv-char/c
  (flat-named-contract
   'csv-char/c
   (lambda (v)
     (and (ascii-char? v)
          (not (memv v '(#\newline #\return)))))))

(define eol-char/c (flat-named-contract 'eol-char/c ascii-char?))

(define float-precision-max uint16-max)

(define float-precision/c (flat-named-contract 'float-precision/c uint16/c))

(define csv-dtype/c
  (flat-named-contract
   'csv-dtype/c
   (lambda (v)
     (and (dtype-spec? v)
          (not (zoned-datetime-dtype? v))
          (match v
            [(or 'null (cons (or 'duration 'enum) _)) #f]
            [_ #t])))))

(define (char->byte c)
  (if c (char->integer c) 0))

(define (quote-differs? separator quote-char)
  (not (eqv? (or (given separator #f) #\,) (given quote-char #\"))))

(define (eol-differs? separator quote-char eol-char)
  (not (memv (given eol-char #\newline)
             (list (or (given separator #f) #\,) (given quote-char #\")))))

(define (one-skip? skip-rows skip-lines)
  (or (zero? (given skip-rows 0)) (zero? (given skip-lines 0))))

(define-cstruct _CompatCsvOptions
  ([has-header _stdbool]
   [separator _uint8]
   [has-quote-char _stdbool]
   [quote-char _uint8]
   [eol-char _uint8]
   [ignore-errors _stdbool]
   [try-parse-dates _stdbool]
   [lossy-utf8 _stdbool]
   [has-n-rows _stdbool]
   [has-infer-schema-length _stdbool]
   [glob _stdbool]
   [truncate-ragged-lines _stdbool]
   [decimal-comma _stdbool]
   [raise-if-empty _stdbool]
   [missing-utf8-is-empty-string _stdbool]
   [row-index-offset _uint32]
   [skip-rows _size]
   [skip-lines _size]
   [skip-rows-after-header _size]
   [n-rows _size]
   [infer-schema-length _size]))

(struct csv-call (options comment-prefix row-index-name null-values null-columns null-markers
                          names dtypes new-columns columns projection guard?))

(define-io-options csv-options
  ([(csv-reader/c range/c) read-keywords ([path path-string?]) range/c
    #:arguments csv-read-arguments]
   [(csv-scanner/c range/c) scan-keywords ([path path-string?]) range/c
    #:arguments csv-scan-arguments #:omit (#:columns)])
  ([#:has-header has-header boolean? #t]
   [#:columns columns
              (or/c (and/c (listof column-name/c) distinct?) (and/c (listof size/c) distinct?))
              '()]
   [#:new-columns new-columns (and/c (listof column-name/c) distinct?) '()]
   [#:separator separator (or/c csv-char/c #f) #f]
   [#:comment-prefix comment-prefix (or/c non-empty-string? #f) #f]
   [#:quote-char quote-char (or/c csv-char/c #f) #\"]
   [#:skip-rows skip-rows size/c 0]
   [#:skip-lines skip-lines size/c 0]
   [#:schema-overrides schema-overrides
                       (and/c (listof (cons/c column-name/c csv-dtype/c)) distinct-names?)
                       '()]
   [#:null-values null-values
                  (or/c string? (listof string?)
                        (and/c (listof (cons/c column-name/c string?)) distinct-names?)
                        #f)
                  #f]
   [#:missing-utf8-is-empty-string missing-utf8-is-empty-string boolean? #f]
   [#:ignore-errors ignore-errors boolean? #f]
   [#:try-parse-dates try-parse-dates boolean? #f]
   [#:infer-schema infer-schema boolean? #t]
   [#:infer-schema-length infer-schema-length (or/c size/c #f) 100]
   [#:n-rows n-rows (or/c size/c #f) #f]
   [#:encoding encoding (or/c 'utf8 'utf8-lossy) 'utf8]
   [#:skip-rows-after-header skip-rows-after-header size/c 0]
   [#:row-index-name row-index-name (or/c column-name/c #f) #f]
   [#:row-index-offset row-index-offset row-index/c 0]
   [#:eol-char eol-char eol-char/c #\newline]
   [#:raise-if-empty raise-if-empty boolean? #t]
   [#:truncate-ragged-lines truncate-ragged-lines boolean? #f]
   [#:decimal-comma decimal-comma boolean? #f]
   [#:glob glob boolean? #t])
  #:pre (separator quote-char) "quote-char must differ from the separator (#\\, when not given)"
  (quote-differs? separator quote-char)
  #:pre (separator quote-char eol-char)
  "eol-char must differ from the separator and quote-char"
  (eol-differs? separator quote-char eol-char)
  #:pre (skip-rows skip-lines) "only one of skip-rows and skip-lines may be set"
  (one-skip? skip-rows skip-lines)
  (let ([infer-length (if infer-schema infer-schema-length 0)])
    (define-values (every-null column-nulls)
      (match null-values
        [#f (values '() '())]
        [(? string? marker) (values (list marker) '())]
        [(list (? string?) ...) (values null-values '())]
        [_ (values '() null-values)]))
    (define-values (column-names column-indices) (partition string? columns))
    (csv-call (make-CompatCsvOptions has-header
                                     (char->byte (or separator #\,))
                                     quote-char
                                     (char->byte quote-char)
                                     (char->byte eol-char)
                                     ignore-errors
                                     try-parse-dates
                                     (eq? encoding 'utf8-lossy)
                                     n-rows
                                     infer-length
                                     glob
                                     truncate-ragged-lines
                                     decimal-comma
                                     raise-if-empty
                                     missing-utf8-is-empty-string
                                     row-index-offset
                                     skip-rows
                                     skip-lines
                                     skip-rows-after-header
                                     (or n-rows 0)
                                     (or infer-length 0))
              comment-prefix
              row-index-name
              every-null
              (map car column-nulls)
              (map cdr column-nulls)
              (map car schema-overrides)
              (map (compose1 ->compat-dtype normalize-dtype cdr) schema-overrides)
              new-columns
              column-names
              column-indices
              (and has-header (not separator) (null? new-columns) (null? columns)))))

(define-syntax-parse-rule (_csv-fun (~datum ->) result:expr)
  (_fun (path : _c-string)
        (options : _CompatCsvOptions)
        (comment-prefix : _str/null)
        (row-index-name : _str/null)
        (null-values : _str-list)
        (null-columns : _str-list)
        (null-markers : _str-list)
        (names : _str-list)
        (dtypes : (_list i _CompatDType))
        (_size = (length names))
        (new-columns : _str-list)
        (columns : _str-list)
        (projection : (_list i _size))
        (_size = (length projection))
        -> result))

(define-compat dataframe-read-csv/raw (_csv-fun -> _DataFrame-ptr/null)
  #:c-id dataframe_read_csv_v3
  #:wrap (allocator dataframe-drop))

(define-compat lazyframe-scan-csv/raw (_csv-fun -> _LazyFrame-ptr/null)
  #:c-id lazyframe_scan_csv_v3
  #:wrap (allocator lazyframe-drop))

(define (apply-csv who entry path call)
  (match-define (csv-call options comment-prefix row-index-name null-values null-columns
                          null-markers names dtypes new-columns columns projection _)
    call)
  (define glob? (and (CompatCsvOptions-glob options) (glob-pattern? path)))
  (set-CompatCsvOptions-glob! options glob?)
  (entry (path->complete-string who path #:glob? glob?)
         options comment-prefix row-index-name null-values null-columns null-markers
         names dtypes new-columns columns projection))

(define (csv-scanner who)
  (keyword-forwarder
   who csv-options scan-keywords 1
   (lambda (call path)
     (call/foreign-error who
                         (lambda () (apply-csv who lazyframe-scan-csv/raw path call))
                         "failed to scan ~a" path))))

(define (csv-reader who)
  (keyword-forwarder
   who csv-options read-keywords 1
   (lambda (call path)
     (define df
       (call/foreign-error who
                           (lambda () (apply-csv who dataframe-read-csv/raw path call))
                           "failed to read csv from ~a" path))
     (check-separator who df path call)
     df)))

(define dataframe-read-csv (csv-reader 'dataframe-read-csv))
(define lazyframe-scan-csv (csv-scanner 'lazyframe-scan-csv))

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

(define (check-separator who df path call)
  (define file-columns
    (for*/list ([i (in-range (dataframe-width df))]
                [name (in-value (dataframe-column-name df i))]
                #:unless (equal? name (csv-call-row-index-name call)))
      name))
  (define header
    (and (csv-call-guard? call) (= (length file-columns) 1) (car file-columns)))
  (define splitter
    (and header
         (for/first ([c (in-list likely-separators)]
                     #:when (let ([n (char-count c header)])
                              (and (positive? n) (first-row-agrees? df header c n))))
           c)))
  (when splitter
    (error who
           "~a reads as one column whose header splits on ~s into ~a fields; pass #:separator ~s, or #:separator #\\, to keep one column"
           path splitter (add1 (char-count splitter header)) splitter)))

(define-cstruct _CompatCsvWriteOptions
  ([include-header _stdbool]
   [include-bom _stdbool]
   [separator _uint8]
   [quote-char _uint8]
   [quote-style _uint8]
   [decimal-comma _stdbool]
   [has-float-scientific _stdbool]
   [float-scientific _stdbool]
   [has-float-precision _stdbool]
   [float-precision _size]
   [batch-size _size]))

(define quote-styles '(necessary always non-numeric never))

(define-compat dataframe-write-csv/raw
  (_fun _DataFrame-ptr
        _c-string
        _CompatCsvWriteOptions
        _str
        _str
        _str/null
        _str/null
        _str/null
        -> _int32)
  #:c-id dataframe_write_csv_with_options_v2)

(struct write-call (options line-terminator null-value datetime-format date-format time-format))

(define-io-options csv-write-options
  ([(csv-writer/c frame/c) write-keywords ([frame frame/c] [path path-string?]) void?
    #:arguments csv-write-arguments])
  ([#:include-bom include-bom boolean? #f]
   [#:include-header include-header boolean? #t]
   [#:separator separator csv-char/c #\,]
   [#:line-terminator line-terminator string? "\n"]
   [#:quote-char quote-char csv-char/c #\"]
   [#:batch-size batch-size positive-size/c 1024]
   [#:datetime-format datetime-format (or/c string? #f) #f]
   [#:date-format date-format (or/c string? #f) #f]
   [#:time-format time-format (or/c string? #f) #f]
   [#:float-scientific float-scientific (or/c 'auto boolean?) 'auto]
   [#:float-precision float-precision (or/c float-precision/c #f) #f]
   [#:decimal-comma decimal-comma boolean? #f]
   [#:null-value null-value string? ""]
   [#:quote-style quote-style (or/c 'necessary 'always 'non-numeric 'never) 'necessary])
  #:pre (separator quote-char) "quote-char must differ from the separator (#\\, when not given)"
  (not (eqv? (given separator #\,) (given quote-char #\")))
  (write-call (make-CompatCsvWriteOptions include-header
                                          include-bom
                                          (char->byte separator)
                                          (char->byte quote-char)
                                          (index-of quote-styles quote-style)
                                          decimal-comma
                                          (boolean? float-scientific)
                                          (eq? float-scientific #t)
                                          float-precision
                                          (or float-precision 0)
                                          batch-size)
              line-terminator null-value datetime-format date-format time-format))

(define (csv-writer who)
  (keyword-forwarder
   who csv-write-options write-keywords 2
   (lambda (call frame path)
     (match-define (write-call options line-terminator null-value
                               datetime-format date-format time-format)
       call)
     (define complete (path->complete-string who path))
     (void (call/foreign-error who
                               (lambda ()
                                 (dataframe-write-csv/raw frame complete options
                                                          line-terminator null-value
                                                          datetime-format date-format
                                                          time-format))
                               #:ok? zero?
                               "failed to write csv to ~a" path)))))

(define dataframe-write-csv (csv-writer 'dataframe-write-csv))

(module+ internal
  (provide dataframe-read-csv dataframe-write-csv lazyframe-scan-csv))
