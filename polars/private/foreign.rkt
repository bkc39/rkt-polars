#lang racket/base

(require ffi/unsafe
         ffi/unsafe/alloc
         ffi/unsafe/atomic
         ffi/unsafe/define
         ffi/unsafe/define/conventions
         gregor
         gregor/period
         (only-in racket/contract/base
                  [-> ->/c] </c ->* ->i and/c any any/c contract-out flat-contract-predicate
                  flat-named-contract listof non-empty-listof not/c or/c real-in rename-contract)
         (only-in racket/contract flat-contract-with-explanation raise-blame-error)
         (only-in racket/provide matching-identifiers-out)
         racket/match
         (only-in racket/dict in-dict)
         (only-in racket/function negate)
         (only-in racket/list check-duplicates)
         (only-in racket/string non-empty-string? string-replace)
         racket/runtime-path
         syntax/parse/define
         (only-in polars/private/c-integer int32/c int64/c size/c uint32/c uint64/c uint8/c)
         (only-in polars/private/join-options
                  asof-keys asof-strategy-symbol->code asof-tolerance->parts frame-join-asof/c
                  frame-join/c join-keys join-symbol->code)
         (only-in polars/private/resource
                  _str _str-list utf-8-name/c with-raw-buffer with-release)
         (only-in (submod polars/private/resource internal) str-block->string str-block->strings)
         (only-in polars/private/temporal
                  days->date epoch->datetime epoch->moment nanoseconds->time offset-unit)
         (for-syntax racket/base racket/syntax (only-in racket/string string-replace) syntax/parse))

(provide (except-out (all-defined-out)
                     series-sort dataframe-sort series-ref-cat series-ref-str series-ref-string
                     series-strings
                     strings->series series-drop
                     dataframe-drop call/reason define-copies define-series-refs print-dataframe
                     series-cast series-date-ref series-index/c series-ref-bytes
                     dataframe-hstack dataframe-join dataframe-join-asof dataframe-vstack
                     define-frame-op/reason define-reasoned block-reader c-string-argument
                     c-string/null-argument named result-only series-str-op
                     series-std series-var series-new-null series-n-unique series-n-unique/raw
                     series-std/raw series-var/raw series-quantile series-quantile/raw
                     define-typed-reduction define-typed-reductions
                     series-head series-tail series-slice
                     dataframe-head dataframe-tail dataframe-slice
                     series-add-i32 series-sub-i32 series-mul-i32 series-div-i32 series-mod-i32
                     series-add-i64 series-sub-i64 series-mul-i64 series-div-i64 series-mod-i64
                     series-add-u32 series-sub-u32 series-mul-u32 series-div-u32 series-mod-u32
                     series-add-u64 series-sub-u64 series-mul-u64 series-div-u64 series-mod-u64
                     series-lt-i32 series-le-i32 series-gt-i32 series-ge-i32 series-eq-i32
                     series-ne-i32
                     series-add-f64 series-sub-f64 series-mul-f64 series-div-f64 series-mod-f64
                     series-lt-f64 series-le-f64 series-gt-f64 series-ge-f64 series-eq-f64
                     series-ne-f64
                     (matching-identifiers-out #rx"^series-ref-.*/raw$" (all-defined-out))
                     (matching-identifiers-out
                      #rx"^series-new-(?:[iu](?:8|16|32|64)|f32|f64|bool|str)(?:/vec)?$"
                      (all-defined-out))
                     (matching-identifiers-out #rx"^dataframe-.*/who$" (all-defined-out)))
         (contract-out
          [dataframe-hstack (->/c DataFrame-ptr? (listof Series-ptr?) DataFrame-ptr?)]
          [dataframe-vstack (->/c DataFrame-ptr? DataFrame-ptr? DataFrame-ptr?)]
          [dataframe-join (frame-join/c DataFrame-ptr? (lambda (_) DataFrame-ptr?)
                                        (lambda (_) DataFrame-ptr?) 'dataframe-join/c)]
          [dataframe-join-asof (frame-join-asof/c DataFrame-ptr? 'dataframe-join-asof/c)]
          [series-drop (->/c Series-ptr? void?)]
          [series-ref-bytes
           (->i ([who symbol?]
                 [s Series-ptr?]
                 [index (s) (and/c exact-nonnegative-integer? (</c (series-len s)))]
                 [limit size/c])
                any)]
          [dataframe-drop (->/c DataFrame-ptr? void?)]
          [series-sort (->* (Series-ptr?) (#:descending boolean? #:nulls-last boolean?)
                            Series-ptr?)]
          [dataframe-sort (frame-sort/c DataFrame-ptr? 'dataframe-sort/c)]
          [series-std (->* (Series-ptr?) (#:ddof uint8/c) (or/c flonum? #f))]
          [series-var (->* (Series-ptr?) (#:ddof uint8/c) (or/c flonum? #f))]
          [series-n-unique (->/c Series-ptr? exact-nonnegative-integer?)]
          [series-quantile
           (->* (Series-ptr? (real-in 0 1))
                (#:interpolation (or/c 'nearest 'linear 'lower 'higher 'midpoint))
                (or/c flonum? #f))]
          [series-new-null (->/c utf-8-name/c size/c Series-ptr?)]
          [series-ref-str series-index/c]
          [series-cast (->/c any/c datetime-zone/c Series-ptr?)]))

(define-syntax-parse-rule (provide-series-constructors [from-list:id from-vector:id] ...)
  (provide (contract-out [from-list (->/c utf-8-name/c list? Series-ptr?)] ...
                         [from-vector (->/c utf-8-name/c vector? Series-ptr?)] ...)))

(provide-series-constructors [series-new-i8 series-new-i8/vec] [series-new-i16 series-new-i16/vec]
                             [series-new-i32 series-new-i32/vec] [series-new-i64 series-new-i64/vec]
                             [series-new-u8 series-new-u8/vec] [series-new-u16 series-new-u16/vec]
                             [series-new-u32 series-new-u32/vec] [series-new-u64 series-new-u64/vec]
                             [series-new-f32 series-new-f32/vec] [series-new-f64 series-new-f64/vec]
                             [series-new-bool series-new-bool/vec]
                             [series-new-str series-new-str/vec])

(define-syntax-parse-rule (provide-row-windows frame?:id head:id tail:id slice:id)
  (provide (contract-out [head (->/c frame? size/c frame?)]
                         [tail (->/c frame? size/c frame?)]
                         [slice (->/c frame? int64/c size/c frame?)])))

(provide-row-windows Series-ptr? series-head series-tail series-slice)
(provide-row-windows DataFrame-ptr? dataframe-head dataframe-tail dataframe-slice)

(define-runtime-path native-libs-dir "../native-libs")

(define-ffi-definer define-compat
  (ffi-lib (build-path native-libs-dir "libcompat"))
  #:make-c-id convention:hyphen->underscore)

(define-compat str-block-drop
  (_fun _pointer -> _void))

(define-compat str-block-drop-count
  (_fun -> _size))

(define ((result-only who) v)
  (raise-argument-error who "a result, never an argument" v))

;; Atomic, so a thread killed in the conversion, which skips with-release's
;; post thunk, is killed only after the drop.
(define ((block-reader read) p)
  (call-as-atomic
   (lambda () (with-release ([block p str-block-drop]) (and block (read block))))))

(define _rsstr
  (make-ctype _pointer (result-only '_rsstr) (block-reader str-block->string)))

(define _rsstr-list
  (make-ctype _pointer (result-only '_rsstr-list) (block-reader str-block->strings)))

(define (c-string-argument v)
  (match v
    [(and (? string?) (not (regexp #rx"\0"))) v]
    [_ (raise-argument-error '_c-string "a string without a NUL" v)]))

(define (c-string/null-argument v)
  (and v (c-string-argument v)))

(define _c-string (make-ctype _string/utf-8 c-string-argument #f))

(define _c-string/null (make-ctype _string/utf-8 c-string/null-argument #f))

(define-compat last-error-message
  (_fun -> _rsstr)
  #:c-id last_error_message_v2)

(define racket-spellings
  `(("`infer_schema_length` (e.g. `infer_schema_length=10000`)"
     . "#:infer-schema-length (e.g. #:infer-schema-length 10000, or #f for every row)")
    ("the `schema_overrides` argument" . "#:schema-overrides")
    ("setting `ignore_errors` to `True`" . "setting #:ignore-errors to #t")
    ("to the `null_values` list" . "to #:null-values")
    ("'truncate_ragged_lines=true'" . "#:truncate-ragged-lines #t")
    ("Try increasing `infer_schema_length` or specifying a schema."
     . "Try increasing #:infer-schema-length or passing #:schema.")
    ("consider increasing infer_schema_length, or manually specifying the full schema"
     . "consider increasing #:infer-schema-length, or passing the full #:schema")
    ("use the compression parameter to control compression, or set `check_extension` to `False` if you want to suffix an uncompressed filename with an ending intended for compression"
     . "pass #:check-extension #f to give an uncompressed file a compressed file's suffix")
    ("set `check_extension` to `False`" . "pass #:check-extension #f")
    ("`missing_columns='insert'`" . "#:missing-columns 'insert")
    ("hint: specify this column in the schema, or pass extra_columns='ignore' in scan options. "
     . "")
    ("Please use `ambiguous` to tell" . "Please use #:ambiguous to tell")
    ("use `non_existent='null'`" . "use dt-replace-time-zone's #:non-existent 'null")
    ("with `.alias(\"new_name\")`" . "with `(alias expr \"new-name\")`")
    (,(string-append "\n\nIf you would like to forcibly disable timezone validation,"
                     " set POLARS_IGNORE_TIMEZONE_PARSE_ERROR=1.")
     . "")))

(define empty-expansion
  #rx"^failed to retrieve [^:]*: expanded paths were empty \\(path expansion input: .*\\)\\.")

(define (respell reason)
  (for/fold ([reason (cond
                       [(or (regexp-match? empty-expansion reason)
                            (equal? reason "no paths specified for this reader"))
                        "no files match the pattern"]
                       [else reason])])
            ([(python racket) (in-dict racket-spellings)])
    (string-replace reason python racket)))

;; only for entry points that call clear_last_error; elsewhere the slot is stale
(define (call/reason thunk ok?)
  (call-as-atomic
   (lambda ()
     (define result (thunk))
     (values result (and (not (ok? result)) (last-error-message))))))

(define (call/foreign-error who thunk #:ok? [ok? values] #:explain [explain (lambda () #f)]
                            #:cause [cause values] [fmt #f] . args)
  (define-values (result reason) (call/reason thunk ok?))
  (define (cause-of reason) (cause (respell reason)))
  (cond
    [(ok? result) result]
    [(explain) => (lambda (message) (error who "~a" message))]
    [(and reason fmt)
     (apply error who (string-append fmt ": ~a") (append args (list (cause-of reason))))]
    [reason (error who "~a" (cause-of reason))]
    [fmt (apply error who fmt args)]
    [else (error who "no reason recorded")]))

(define (call/polars-reason who thunk)
  (call/foreign-error who thunk))

(define (call/refusal who thunk problem)
  (define-values (result reason) (call/reason thunk values))
  (or result
      (raise-arguments-error who (or (problem)
                                     (and reason (respell reason))
                                     "no reason recorded"))))

(begin-for-syntax
  (define-syntax-class reasoned-formal
    #:attributes (arg [formal 1] [actual 1])
    (pattern arg:id
             #:with (formal ...) #'(arg)
             #:with (actual ...) #'(arg))
    (pattern [kw:keyword arg:id default:expr]
             #:with (formal ...) #'(kw [arg default])
             #:with (actual ...) #'(kw arg))))

(define-syntax-parse-rule (define-reasoned (name:id f:reasoned-formal ...)
                            (~optional (~seq #:who-variant name/who:id)
                                       #:defaults ([name/who (generate-temporary #'name)]))
                            (~optional (~seq #:ok? ok?:expr) #:defaults ([ok? #'values]))
                            (~optional (~seq #:result result:expr) #:defaults ([result #'values]))
                            (~and compat ((~datum define-compat) raw:id _ ...)))
  #:with (ok-proc result-proc) (generate-temporaries '(ok result))
  (begin
    compat
    (define ok-proc ok?)
    (define result-proc result)
    (define (name/who who f.formal ... ...)
      (result-proc (call/foreign-error who (lambda () (raw f.arg ...)) #:ok? ok-proc)))
    (define (name f.formal ... ...)
      (name/who 'name f.actual ... ...))))

(define (printed-or-placeholder what render)
  (define-values (text reason) (call/reason render values))
  (or text (format "#<~a: cannot print: ~a>" what (or reason "no reason recorded"))))

;; only for entry points that record no reason; the others go through call/foreign-error
(define ((allocator/or-fail drop who) proc)
  (define allocate ((allocator drop) proc))
  (procedure-reduce-arity-mask
   (lambda args (or (apply allocate args) (error who "operation failed")))
   (procedure-arity-mask allocate)
   who))

(struct polars-null-sentinel ()
  #:property prop:custom-write
  (lambda (_ out mode)
    (write-string "polars-null" out)))

(define polars-null (polars-null-sentinel))

(define (polars-null? v)
  (eq? v polars-null))

(define compat-dtype-tag/unknown 0)
(define compat-dtype-tag/boolean 1)
(define compat-dtype-tag/uint8 2)
(define compat-dtype-tag/uint16 3)
(define compat-dtype-tag/uint32 4)
(define compat-dtype-tag/uint64 5)
(define compat-dtype-tag/int8 6)
(define compat-dtype-tag/int16 7)
(define compat-dtype-tag/int32 8)
(define compat-dtype-tag/int64 9)
(define compat-dtype-tag/float32 10)
(define compat-dtype-tag/float64 11)
(define compat-dtype-tag/string 12)
(define compat-dtype-tag/binary 13)
(define compat-dtype-tag/binary-offset 14)
(define compat-dtype-tag/date 15)
(define compat-dtype-tag/datetime 16)
(define compat-dtype-tag/duration 17)
(define compat-dtype-tag/time 18)
(define compat-dtype-tag/null 19)
(define compat-dtype-tag/list 20)
(define compat-dtype-tag/array 21)
(define compat-dtype-tag/struct 22)
(define compat-dtype-tag/categorical 23)
(define compat-dtype-tag/enum 24)
(define compat-dtype-tag/decimal 25)
(define compat-dtype-tag/object 26)

(define compat-time-unit/none 0)
(define compat-time-unit/nanoseconds 1)
(define compat-time-unit/microseconds 2)
(define compat-time-unit/milliseconds 3)

(define compat-dtype-flag/has-timezone #x1)

(define-cstruct _CompatDType
  ([dtype-tag _int32]
   [dtype-time-unit _int32]
   [dtype-flags _uint32]
   [dtype-array-width _size]))

(define (compat-time-unit->datum time-unit)
  (case time-unit
    [(1) 'nanoseconds]
    [(2) 'microseconds]
    [(3) 'milliseconds]
    [else #f]))

(define (compat-dtype->datum dtype)
  (define tag (CompatDType-dtype-tag dtype))
  (define time-unit (compat-time-unit->datum (CompatDType-dtype-time-unit dtype)))
  (define flags (CompatDType-dtype-flags dtype))
  (define array-width (CompatDType-dtype-array-width dtype))
  (case tag
    [(1) 'boolean]
    [(2) 'uint8]
    [(3) 'uint16]
    [(4) 'uint32]
    [(5) 'uint64]
    [(6) 'int8]
    [(7) 'int16]
    [(8) 'int32]
    [(9) 'int64]
    [(10) 'float32]
    [(11) 'float64]
    [(12) 'string]
    [(13) 'binary]
    [(14) 'binary-offset]
    [(15) 'date]
    [(16) (list 'datetime
                time-unit
                (and (positive? (bitwise-and flags compat-dtype-flag/has-timezone))
                     'zoned))]
    [(17) (list 'duration time-unit)]
    [(18) 'time]
    [(19) 'null]
    [(20) '(todo nested-dtype-support list)]
    [(21) (list 'todo 'nested-dtype-support 'array array-width)]
    [(22) '(todo nested-dtype-support struct)]
    [(23) 'categorical]
    [(24) 'enum]
    [(25) (list 'decimal array-width (CompatDType-dtype-time-unit dtype))]
    [(26) '(todo parameterized-dtype-support object)]
    [else 'unknown]))

(define (enum-dtype? v)
  (match v
    [(cons 'enum (and (list (? symbol?) ...) categories)) (not (check-duplicates categories))]
    [_ #f]))

(define (decimal-dtype? v)
  (match v
    [(list 'decimal (? exact-positive-integer?) (? exact-nonnegative-integer?)) #t]
    [_ #f]))

(define time-zone-name/c
  (flat-named-contract 'time-zone-name/c (and/c non-empty-string? (not/c #rx"\0"))))

(define datetime-zone/c
  (flat-contract-with-explanation
   (lambda (v)
     (match v
       [(list 'datetime _ (and (? string?) (not (? (flat-contract-predicate time-zone-name/c)))
                               zone))
        (lambda (blame)
          (raise-blame-error blame zone '(expected: "time-zone-name/c" given: "~e") zone))]
       [_ #t]))
   #:name 'datetime-zone/c))

(define (zoned-datetime-dtype? v)
  (match v
    [(list 'datetime (or 'nanoseconds 'microseconds 'milliseconds) (? string? zone))
     (positive? (string-length zone))]
    [_ #f]))

(define-cstruct _CompatOptI32
  ([valid _int32]
   [value _int32]))

(define-cstruct _CompatOptI8
  ([valid _int32]
   [value _int8]))

(define-cstruct _CompatOptI16
  ([valid _int32]
   [value _int16]))

(define-cstruct _CompatOptF64
  ([valid _int32]
   [value _double]))

(define-cstruct _CompatOptF32
  ([valid _int32]
   [value _float]))

(define-cstruct _CompatOptI64
  ([valid _int32]
   [value _int64]))

(define-cstruct _CompatOptU8
  ([valid _int32]
   [value _uint8]))

(define-cstruct _CompatOptU16
  ([valid _int32]
   [value _uint16]))

(define-cstruct _CompatOptU32
  ([valid _int32]
   [value _uint32]))

(define-cstruct _CompatOptU64
  ([valid _int32]
   [value _uint64]))

(define-cstruct _CompatOptBool
  ([valid _int32]
   [value _int32]))

(define-cstruct _YMD
  ([ymd-year _int32]
   [ymd-month _uint32]
   [ymd-day _uint32]))

(define-cstruct _CompatOptYMD
  ([valid _int32]
   [value _YMD]))

(define (compat-opt-i32->datum o)
  (and (not (zero? (CompatOptI32-valid o)))
       (CompatOptI32-value o)))

(define (compat-opt-i8->datum o)
  (and (not (zero? (CompatOptI8-valid o)))
       (CompatOptI8-value o)))

(define (compat-opt-i16->datum o)
  (and (not (zero? (CompatOptI16-valid o)))
       (CompatOptI16-value o)))

(define (compat-opt-f64->datum o)
  (and (not (zero? (CompatOptF64-valid o)))
       (CompatOptF64-value o)))

(define (compat-opt-f32->datum o)
  (and (not (zero? (CompatOptF32-valid o)))
       (CompatOptF32-value o)))

(define (compat-opt-i64->datum o)
  (and (not (zero? (CompatOptI64-valid o)))
       (CompatOptI64-value o)))

(define (compat-opt-u8->datum o)
  (and (not (zero? (CompatOptU8-valid o)))
       (CompatOptU8-value o)))

(define (compat-opt-u16->datum o)
  (and (not (zero? (CompatOptU16-valid o)))
       (CompatOptU16-value o)))

(define (compat-opt-u32->datum o)
  (and (not (zero? (CompatOptU32-valid o)))
       (CompatOptU32-value o)))

(define (compat-opt-u64->datum o)
  (and (not (zero? (CompatOptU64-valid o)))
       (CompatOptU64-value o)))

(define (compat-opt-bool->datum o)
  (and (not (zero? (CompatOptBool-valid o)))
       (not (zero? (CompatOptBool-value o)))))

(define (ymd->date value)
  (date (YMD-ymd-year value)
        (YMD-ymd-month value)
        (YMD-ymd-day value)))

(define (compat-opt-ymd->datum o)
  (and (not (zero? (CompatOptYMD-valid o)))
       (ymd->date (CompatOptYMD-value o))))

;; allocator registers the release on the pointer a wrapper holds, not on the wrapper
(define-values (prop:owned-pointer owned-pointer? owned-pointer-accessor)
  (make-struct-type-property
   'owned-pointer
   (lambda (index info)
     (define field-ref (list-ref info 3))
     (lambda (v) (field-ref v index)))))

(define (owned-pointer-arg args)
  (let unwrap ([v (car args)])
    (if (owned-pointer? v) (unwrap ((owned-pointer-accessor v) v)) v)))

(define (raise-dropped who noun)
  (raise-arguments-error who (format "~a has been dropped" noun)))

(define (dropped? v dropped)
  (and (cpointer? v) (cpointer-has-tag? v dropped)))

(define ((write-owned kind dropped show) v port mode)
  (write-string (if (dropped? v dropped) (format "#<~a: dropped>" kind) (show v)) port))

(define (owned-cpointer-types tag kind noun dropped wrap)
  (define (refuse p)
    (cond
      [(dropped? p dropped) (raise-dropped kind noun)]
      [else (raise-arguments-error (string->symbol (format "~a->C" tag))
                                   (format "argument is not non-null `~a' pointer" tag)
                                   "argument" p)]))
  (define (->c p)
    (cond
      [(and (cpointer? p) (cpointer-has-tag? p tag)) p]
      [else (refuse p)]))
  (define (->racket p)
    (cond
      [p (cpointer-push-tag! p tag)
         (wrap p)]
      [else (refuse p)]))
  (define ((or-null convert) p)
    (and p (convert p)))
  (values (make-ctype _pointer ->c ->racket)
          (make-ctype _pointer (or-null ->c) (or-null ->racket))))

(define (release-owned who noun dropped drop/raw v)
  (call-as-atomic
   (lambda ()
     (define p (owned-pointer-arg (list v)))
     (cond
       [(dropped? p dropped) (raise-dropped who noun)]
       [else (drop/raw p)
             (set-cpointer-tag! p dropped)]))))

(define-syntax-parse-rule (define-owned-cpointer-type
                           type:id
                           kind:id
                           (~alt (~optional
                                  (~seq #:noun noun:str)
                                  #:defaults
                                  ([noun (datum->syntax #'kind (symbol->string (syntax-e #'kind)))]))
                                 (~optional (~seq #:wrap wrap:expr) #:defaults ([wrap #'values]))) ...
                           (~and release ((~datum define-compat) drop/raw:id _ ...)))
  #:do [(define tag (substring (symbol->string (syntax-e #'type)) 1))]
  #:with type/null (format-id #'type "~a/null" #'type)
  #:with type? (format-id #'type "~a?" tag)
  #:with type-tag (format-id #'type "~a-tag" tag)
  #:with tag-name (datum->syntax #'type (string->symbol tag))
  #:with dropped (format-id #'kind "~a-dropped" #'kind)
  #:with drop (format-id #'kind "~a-drop" #'kind)
  (begin
    (define type-tag 'tag-name)
    (define dropped (gensym 'dropped))
    (define (type? v)
      (and (cpointer? v) (or (cpointer-has-tag? v type-tag) (cpointer-has-tag? v dropped))))
    (define-values (type type/null) (owned-cpointer-types type-tag 'kind noun dropped wrap))
    release
    (define (drop v)
      (release-owned 'drop noun dropped drop/raw v))))

(define-owned-cpointer-type _Series-ptr series
  (define-compat series-drop/raw
    (_fun _Series-ptr -> _void)
    #:c-id series_drop
    #:wrap (deallocator)))

(define-compat series-drop-count
  (_fun -> _size))

(define-compat series-empty
  (_fun -> _Series-ptr)
  #:wrap (allocator series-drop))

(define-compat series-name
  (_fun _Series-ptr -> _rsstr)
  #:c-id series_name_v2)

(define-compat series-dtype/raw
  (_fun _Series-ptr -> _CompatDType)
  #:c-id series_dtype)

(define-compat series-enum-categories/raw
  (_fun _Series-ptr -> _Series-ptr/null)
  #:c-id series_enum_categories
  #:wrap (allocator/or-fail series-drop 'series-enum-categories))

(define (series-enum-categories s)
  (with-release ([names (series-enum-categories/raw s) series-drop])
    (map string->symbol (series-strings names 0 (series-len names)))))

(define-compat series-time-zone
  (_fun _Series-ptr -> _rsstr)
  #:c-id series_time_zone_v2)

(define (series-dtype series)
  (match (compat-dtype->datum (series-dtype/raw series))
    ['enum (cons 'enum (series-enum-categories series))]
    [(list 'datetime unit 'zoned) (list 'datetime unit (series-time-zone series))]
    [dtype dtype]))

(define (time-unit-symbol->code tu)
  (case tu
    [(#f none) compat-time-unit/none]
    [(nanoseconds) compat-time-unit/nanoseconds]
    [(microseconds) compat-time-unit/microseconds]
    [(milliseconds) compat-time-unit/milliseconds]
    [else (error '->compat-dtype "unknown time unit ~v" tu)]))

(define (simple-dtype-tag sym)
  (case sym
    [(boolean)   compat-dtype-tag/boolean]
    [(uint8)     compat-dtype-tag/uint8]
    [(uint16)    compat-dtype-tag/uint16]
    [(uint32)    compat-dtype-tag/uint32]
    [(uint64)    compat-dtype-tag/uint64]
    [(int8)      compat-dtype-tag/int8]
    [(int16)     compat-dtype-tag/int16]
    [(int32)     compat-dtype-tag/int32]
    [(int64)     compat-dtype-tag/int64]
    [(float32)   compat-dtype-tag/float32]
    [(float64)   compat-dtype-tag/float64]
    [(string)    compat-dtype-tag/string]
    [(binary)    compat-dtype-tag/binary]
    [(date)      compat-dtype-tag/date]
    [(time)      compat-dtype-tag/time]
    [(null)      compat-dtype-tag/null]
    [(categorical) compat-dtype-tag/categorical]
    [else        #f]))

(define dtype-short-names
  (hash 'i8 'int8   'i16 'int16   'i32 'int32   'i64 'int64
        'u8 'uint8  'u16 'uint16  'u32 'uint32  'u64 'uint64
        'f32 'float32 'f64 'float64 'bool 'boolean 'str 'string))

;; a naive datetime only: a zoned one crosses through the _datetime_tz entry
;; points, which take its zone's name
(define (->compat-dtype dtype)
  (match dtype
    [(? symbol?)
     (define canonical (hash-ref dtype-short-names dtype dtype))
     (define tag (simple-dtype-tag canonical))
     (case canonical
       [(datetime)
        (make-CompatDType compat-dtype-tag/datetime
                          compat-time-unit/microseconds 0 0)]
       [(duration)
        (make-CompatDType compat-dtype-tag/duration
                          compat-time-unit/microseconds 0 0)]
       [else
        (unless tag
          (error '->compat-dtype "unsupported cast target ~v" dtype))
        (make-CompatDType tag compat-time-unit/none 0 0)])]
    [(list* 'datetime unit (or '() (list #f)))
     (make-CompatDType compat-dtype-tag/datetime (time-unit-symbol->code unit) 0 0)]
    [(cons 'duration (cons unit _))
     (make-CompatDType compat-dtype-tag/duration (time-unit-symbol->code unit) 0 0)]
    [_ (error '->compat-dtype "unsupported cast target ~v" dtype)]))

(define-compat series-rename/raw
  (_fun _Series-ptr _str -> _int32)
  #:c-id series_rename_v2)

(define (series-rename/who who s name)
  (call/foreign-error who (lambda () (series-rename/raw s name)) #:ok? zero?)
  (void))

(define (series-rename s name)
  (series-rename/who 'series-rename s name))

(define ((named who name) s)
  (series-rename/who who s name)
  s)

(define-compat series-len
  (_fun _Series-ptr -> _size))

(define-compat series-null-count
  (_fun _Series-ptr -> _size))

(begin-for-syntax
  (define-syntax-class reduction-dtype
    #:attributes (opt-type valid opt->datum)
    (pattern t:id
             #:fail-unless (memq (syntax-e #'t) '(i8 i16 i32 i64 u8 u16 u32 u64 f32 f64))
             "a numeric dtype suffix"
             #:do [(define upper (string-upcase (symbol->string (syntax-e #'t))))]
             #:with opt-type (format-id #'t "_CompatOpt~a" upper)
             #:with valid (format-id #'t "CompatOpt~a-valid" upper)
             #:with opt->datum (format-id #'t "compat-opt-~a->datum" #'t))))

(define-syntax-parse-rule (define-typed-reduction op:id t:id opt-type:id valid:id opt->datum:id)
  #:with name (format-id #'t "series-~a-~a" #'op #'t)
  #:with raw (format-id #'here "~a/raw" #'name)
  #:with c-id (format-id #'here "series_~a_~a_v2" #'op #'t)
  (define-reasoned (name s)
    #:ok? (compose1 (negate negative?) valid)
    #:result opt->datum
    (define-compat raw
      (_fun _Series-ptr -> opt-type)
      #:c-id c-id)))

(define-syntax-parse-rule (define-typed-reductions t:reduction-dtype ...)
  (begin
    (begin
      (define-typed-reduction sum t t.opt-type t.valid t.opt->datum)
      (define-typed-reduction min t t.opt-type t.valid t.opt->datum)
      (define-typed-reduction max t t.opt-type t.valid t.opt->datum)
      (define-typed-reduction mean t _CompatOptF64 CompatOptF64-valid compat-opt-f64->datum))
    ...))

(define-typed-reductions i8 i16 i32 i64 u8 u16 u32 u64 f32 f64)

(define-reasoned (series-n-unique s)
  #:ok? (negate negative?)
  (define-compat series-n-unique/raw
    (_fun _Series-ptr -> _int64)
    #:c-id series_n_unique_v2))

(define-reasoned (series-head s n)
  (define-compat series-head/raw
    (_fun _Series-ptr _size -> _Series-ptr/null)
    #:c-id series_head
    #:wrap (allocator series-drop)))

(define-reasoned (series-tail s n)
  (define-compat series-tail/raw
    (_fun _Series-ptr _size -> _Series-ptr/null)
    #:c-id series_tail
    #:wrap (allocator series-drop)))

(define-reasoned (series-slice s offset length)
  (define-compat series-slice/raw
    (_fun _Series-ptr _int64 _size -> _Series-ptr/null)
    #:c-id series_slice
    #:wrap (allocator series-drop)))

(define-reasoned (series-reverse s)
  (define-compat series-reverse/raw
    (_fun _Series-ptr -> _Series-ptr/null)
    #:c-id series_reverse
    #:wrap (allocator series-drop)))

(define-reasoned (series-drop-nulls s)
  (define-compat series-drop-nulls/raw
    (_fun _Series-ptr -> _Series-ptr/null)
    #:c-id series_drop_nulls
    #:wrap (allocator series-drop)))

(define-reasoned (series-unique s)
  (define-compat series-unique/raw
    (_fun _Series-ptr -> _Series-ptr/null)
    #:c-id series_unique
    #:wrap (allocator series-drop)))

(define-compat series-sort/raw
  (_fun _Series-ptr _stdbool _stdbool -> _Series-ptr/null)
  #:c-id series_sort_with_options
  #:wrap (allocator series-drop))

(define (series-sort s #:descending [descending #f] #:nulls-last [nulls-last #f])
  (call/foreign-error 'series-sort
                      (lambda () (series-sort/raw s descending nulls-last))
                      "failed to sort the series"))

(define (values+valid input-values default-value)
  (for/lists (clean-values valid)
             ([value input-values])
    (if (polars-null? value)
        (values default-value 0)
        (values value 1))))

(define (contains-polars-null? values)
  (ormap polars-null? values))

(define-syntax-parse-rule (define-series-constructors rs-type:id ctype:id default-value:expr)
  #:with list-constructor-name (format-id #'rs-type "series-new-~a" #'rs-type)
  #:with vector-constructor-name (format-id #'rs-type
                                            "series-new-~a/vec"
                                            #'rs-type)
  #:with list-constructor-raw-name (format-id #'rs-type "series-new-~a/raw" #'rs-type)
  #:with vector-constructor-raw-name (format-id #'rs-type
                                                "series-new-~a/vec/raw"
                                                #'rs-type)
  #:with opt-constructor-name (format-id #'rs-type "series-new-~a/opt/raw" #'rs-type)
  #:with rust-id (format-id #'rs-type "series_new_~a" #'rs-type)
  #:with rust-opt-id (format-id #'rs-type "series_new_opt_~a" #'rs-type)
  (begin
    (define-compat list-constructor-raw-name
      (_fun (_c-string = "")
            (v : (_list i ctype))
            (_size = (length v))
            -> _Series-ptr/null)
      #:c-id rust-id
      #:wrap (allocator/or-fail series-drop 'list-constructor-name))
    (define-compat vector-constructor-raw-name
      (_fun (_c-string = "")
            (v : (_vector i ctype))
            (_size = (vector-length v))
            -> _Series-ptr/null)
      #:c-id rust-id
      #:wrap (allocator/or-fail series-drop 'vector-constructor-name))
    (define-compat opt-constructor-name
      (_fun (_c-string = "")
            (v : (_list i ctype))
            (valid : (_list i _uint8))
            (_size = (length v))
            -> _Series-ptr/null)
      #:c-id rust-opt-id
      #:wrap (allocator/or-fail series-drop 'list-constructor-name))
    (define (list-constructor-name name values)
      ((named 'list-constructor-name name)
       (if (contains-polars-null? values)
           (let-values ([(clean-values valid) (values+valid values default-value)])
             (opt-constructor-name clean-values valid))
           (list-constructor-raw-name values))))
    (define (vector-constructor-name name values)
      ((named 'vector-constructor-name name)
       (if (for/or ([value (in-vector values)])
             (polars-null? value))
           (let-values ([(clean-values valid)
                         (values+valid (vector->list values) default-value)])
             (opt-constructor-name clean-values valid))
           (vector-constructor-raw-name values))))))

(define-series-constructors i32 _int32 0)

(define-series-constructors i8 _int8 0)
(define-series-constructors i16 _int16 0)

(define-series-constructors f64 _double 0.0)

(define-series-constructors f32 _float 0.0)

(define-series-constructors i64 _int64 0)

(define-series-constructors u32 _uint32 0)

(define-series-constructors u8 _uint8 0)
(define-series-constructors u16 _uint16 0)

(define-series-constructors u64 _uint64 0)

;; Bools cross the boundary as u8 (0/1).  Racket-side wrappers translate
;; #f/#t to 0/1.
(define-compat series-new-bool/raw
  (_fun (_c-string = "")
        (v : (_list i _uint8))
        (_size = (length v))
        -> _Series-ptr/null)
  #:c-id series_new_bool
  #:wrap (allocator/or-fail series-drop 'series-new-bool))

(define-compat series-new-bool/vec/raw
  (_fun (_c-string = "")
        (v : (_vector i _uint8))
        (_size = (vector-length v))
        -> _Series-ptr/null)
  #:c-id series_new_bool
  #:wrap (allocator/or-fail series-drop 'series-new-bool/vec))

(define-compat series-new-bool/opt/raw
  (_fun (_c-string = "")
        (v : (_list i _uint8))
        (valid : (_list i _uint8))
        (_size = (length v))
        -> _Series-ptr/null)
  #:c-id series_new_opt_bool
  #:wrap (allocator/or-fail series-drop 'series-new-bool))

(define (bool->u8 b) (if b 1 0))

(define (series-new-bool name bools)
  ((named 'series-new-bool name)
   (cond
     [(contains-polars-null? bools)
      (define-values (clean-values valid) (values+valid bools #f))
      (series-new-bool/opt/raw (map bool->u8 clean-values) valid)]
     [else (series-new-bool/raw (map bool->u8 bools))])))

(define (series-new-bool/vec name bools)
  ((named 'series-new-bool/vec name)
   (cond
     [(for/or ([value (in-vector bools)])
        (polars-null? value))
      (define-values (clean-values valid) (values+valid (vector->list bools) #f))
      (series-new-bool/opt/raw (map bool->u8 clean-values) valid)]
     [else
      (series-new-bool/vec/raw (for/vector #:length (vector-length bools)
                                           ([b (in-vector bools)])
                                 (bool->u8 b)))])))

(define-compat series-new-null/raw
  (_fun (_c-string = "") _size -> _Series-ptr/null)
  #:c-id series_new_null
  #:wrap (allocator/or-fail series-drop 'series-new-null))

(define (series-new-null name length)
  ((named 'series-new-null name) (series-new-null/raw length)))

;; The buffer and validity are GC memory the collector may move: never #:blocking?.
(define-compat series-new-str/raw
  (_fun (_c-string = "") _bytes _size _pointer _size _bytes _size -> _Series-ptr/null)
  #:c-id series_new_str_packed
  #:wrap (allocator series-drop))

;; One UTF-8 buffer and row offsets, not a list of C strings: the collector
;; moves strings while such a list is filled (#143).
(define (strings->series who name strings)
  (define count (length strings))
  (define valid (and (contains-polars-null? strings) (make-bytes count 1)))
  (with-raw-buffer ([offsets (add1 count) _int64])
    (ptr-set! offsets _int64 0 0)
    (define size
      (for/fold ([end 0]) ([s (in-list strings)] [row (in-naturals)])
        (define next
          (cond
            [(string? s) (+ end (string-utf-8-length s))]
            [(polars-null? s) (bytes-set! valid row 0) end]
            [else (raise-argument-error who "(or/c string? polars-null?)" s)]))
        (ptr-set! offsets _int64 (add1 row) next)
        next))
    (define buf (make-bytes size))
    (for/fold ([end 0]) ([s (in-list strings)] #:when (string? s))
      (define utf-8 (string->bytes/utf-8 s))
      (bytes-copy! buf end utf-8)
      (+ end (bytes-length utf-8)))
    ((named who name)
     (call/foreign-error
      who
      (lambda () (series-new-str/raw buf size offsets (add1 count) valid (if valid count 0)))
      "operation failed"))))

(define (series-new-str name strings)
  (strings->series 'series-new-str name strings))

(define (series-new-str/vec name strings)
  (strings->series 'series-new-str/vec name (vector->list strings)))

;; Year, Month, Day, Hour, Minute, Second
(define-cstruct _YMDHMS
  ([year _int]
   [month _uint32]
   [day _uint32]
   [hour _uint32]
   [minute _uint32]
   [sescond _uint32]))

(define default-ymdhms (make-YMDHMS 1970 1 1 0 0 0))

(define-series-constructors ymdhms _YMDHMS default-ymdhms)

(define-compat series-ref-is-null
  (_fun _Series-ptr _size -> _int32))

(define series-index/c
  (->i ([s Series-ptr?]
        [index (s) (and/c exact-nonnegative-integer? (</c (series-len s)))])
       any))

(define-syntax-parse-rule (define-series-refs [type:id result:expr] ...)
  #:with ((name c-id) ...)
  (for/list ([t (in-list (syntax->list #'(type ...)))])
    (list (format-id t "series-ref-~a/raw" t)
          (format-id t "series_ref_~a" t)))
  (begin
    (define-compat name
      (_fun _Series-ptr _size -> result)
      #:c-id c-id)
    ...
    (provide (contract-out [name series-index/c] ...))))

(define-series-refs
  [i8 _CompatOptI8]
  [i16 _CompatOptI16]
  [i32 _CompatOptI32]
  [i64 _CompatOptI64]
  [u8 _CompatOptU8]
  [u16 _CompatOptU16]
  [u32 _CompatOptU32]
  [u64 _CompatOptU64]
  [f32 _CompatOptF32]
  [f64 _CompatOptF64]
  [bool _CompatOptBool]
  [date _CompatOptYMD]
  [duration _CompatOptI64]
  [time _CompatOptI64])

(define (series-ref-unsupported who dtype)
  (error who "unsupported dtype ~v" dtype))

(define (require-ref-value who dtype value)
  (or value (error who "could not read non-null value for dtype ~v" dtype)))

(define (duration-value->period dtype value)
  (match dtype
    [`(duration nanoseconds) (nanoseconds value)]
    [`(duration microseconds) (microseconds value)]
    [`(duration milliseconds) (milliseconds value)]
    [`(duration ,_) (microseconds value)]
    [_ (error 'series-ref "expected duration dtype, got ~v" dtype)]))

(define-compat series-copy-decimal
  (_fun _Series-ptr _size _size _pointer _size _bytes _size -> _int64))

(define-compat series-str-byte-len
  (_fun _Series-ptr _size _size -> _int64))

;; The buffers are GC memory the collector may move: never #:blocking?.
(define-compat series-copy-str
  (_fun _Series-ptr _size _size _bytes _size _pointer _size _bytes _size -> _int64))

;; By length, not as a C string, which would end at a NUL a value holds. A
;; null row reads as ""; a series that is not a String one as #f.
(define (series-strings s start count)
  (define size (series-str-byte-len s start count))
  (cond
    [(negative? size) #f]
    [else
     (define buf (make-bytes size))
     (with-raw-buffer ([offsets (add1 count) _int64])
       (and (not (negative? (series-copy-str s start count buf size offsets (add1 count) #f 0)))
            (for/list ([i (in-range count)])
              (bytes->string/utf-8 buf #f
                                   (ptr-ref offsets _int64 i)
                                   (ptr-ref offsets _int64 (add1 i))))))]))

(define (series-ref-string s index)
  (match (series-strings s index 1)
    [(list value) value]
    [#f #f]))

(define-compat series-ref-cat
  (_fun _Series-ptr _size -> _rsstr))

(define (series-ref-str s index)
  (match (and (eqv? (series-ref-is-null s index) 0) (compat-dtype->datum (series-dtype/raw s)))
    ['string (series-ref-string s index)]
    [(or 'categorical 'enum) (series-ref-cat s index)]
    [_ #f]))

(define-compat series-binary-byte-len
  (_fun _Series-ptr _size _size _size -> _int64))

;; The buffers are GC memory the collector may move: never #:blocking?.
(define-compat series-copy-binary
  (_fun _Series-ptr _size _size _size _bytes _size _pointer _size _pointer _size _bytes _size
        -> _int64))

(define (series-ref-bytes who s index limit)
  (define size (series-binary-byte-len s index 1 limit))
  (define buf (make-bytes (max size 0)))
  (define valid (make-bytes 1))
  (define copied
    (and (not (negative? size))
         (with-raw-buffer ([offsets 2 _int64])
           (series-copy-binary s index 1 limit buf size offsets 2 #f 0 valid 1))))
  (cond
    [(or (not copied) (negative? copied))
     (error who "cannot read a binary value at index ~a" index)]
    [(zero? (bytes-ref valid 0)) polars-null]
    [else buf]))

;; The validity buffers are GC memory the collector may move: never #:blocking?.
(define-syntax-parse-rule (define-copies name:id ...)
  (begin
    (define-compat name
      (_fun _Series-ptr _size _size _pointer _size _bytes _size -> _int64))
    ...))

(define-copies
  series-copy-i8 series-copy-i16 series-copy-i32 series-copy-i64
  series-copy-u8 series-copy-u16 series-copy-u32 series-copy-u64
  series-copy-f32 series-copy-f64 series-copy-bool)

(define ((unreadable-datetime who zone) reason)
  (error who "cannot read a datetime in ~s: ~a" zone (respell reason)))

;; `count` rows of a zoned column from `start`: each UTC instant into
;; `instants`, and into `walls` its wall clock in (offset-unit unit).
(define (copy-zoned-datetimes who s dtype start count instants walls valid
                              #:unreadable [unreadable (unreadable-datetime who (caddr dtype))])
  (match-define (list _ unit zone) dtype)
  (define (copied status)
    (when (negative? status)
      (error who "could not copy a series of dtype ~v (status ~a)" dtype status)))
  (with-release ([rows (series-slice s start count) series-drop]
                 [view (series-cast-datetime-tz who rows (list 'datetime (offset-unit unit) zone))
                       series-drop])
    (define-values (clocks reason)
      (call/reason (lambda () (series-dt-replace-time-zone/raw view #f "raise" "raise")) values))
    (cond
      [clocks
       (with-release ([walls-of clocks series-drop])
         (copied (series-copy-i64 rows 0 count instants count valid
                                  (if valid (bytes-length valid) 0)))
         (copied (series-copy-i64 walls-of 0 count walls count #f 0)))]
      [else (unreadable (or reason "no reason recorded"))])))

(define (series-ref-datetime who s index unit zone unreadable)
  (with-raw-buffer ([value 2 _int64])
    (cond
      [(not zone)
       (and (zero? (series-copy-i64 s index 1 value 1 #f 0))
            (epoch->datetime unit (ptr-ref value _int64 0)))]
      [else
       (let/ec return
         (copy-zoned-datetimes who s (list 'datetime unit zone) index 1
                               value (ptr-add value 1 _int64) #f
                               #:unreadable (if unreadable
                                                (lambda (reason) (return (unreadable reason)))
                                                (unreadable-datetime who zone)))
         (epoch->moment unit (ptr-ref value _int64 0) (ptr-ref value _int64 1) zone))])))

(define (series-date-ref s index)
  (with-raw-buffer ([days 1 _int32])
    (and (zero? (series-copy-i32 s index 1 days 1 #f 0))
         (days->date (ptr-ref days _int32 0)))))

(define (decimal-ref words i scale)
  (/ (+ (ptr-ref words _uint64 (* 2 i))
        (arithmetic-shift (ptr-ref words _int64 (add1 (* 2 i))) 64))
     (expt 10 scale)))

(define (series-ref-decimal s index scale)
  (with-raw-buffer ([words 2 _uint64])
    (and (zero? (series-copy-decimal s index 1 words 2 #f 0))
         (decimal-ref words 0 scale))))

(define (series-ref s index)
  (series-value 'series-ref s index))

(define (series-value who s index #:unreadable [unreadable #f])
  (unless (exact-nonnegative-integer? index)
    (error who "index must be an exact nonnegative integer, got ~v" index))
  (define len (series-len s))
  (unless (< index len)
    (error who "index ~a out of bounds for series of length ~a" index len))
  (case (series-ref-is-null s index)
    [(1) polars-null]
    [(0)
     (define dtype (compat-dtype->datum (series-dtype/raw s)))
     (case dtype
       [(int8) (require-ref-value who dtype (compat-opt-i8->datum (series-ref-i8/raw s index)))]
       [(int16) (require-ref-value who dtype (compat-opt-i16->datum (series-ref-i16/raw s index)))]
       [(int32) (require-ref-value who dtype (compat-opt-i32->datum (series-ref-i32/raw s index)))]
       [(int64) (require-ref-value who dtype (compat-opt-i64->datum (series-ref-i64/raw s index)))]
       [(uint8) (require-ref-value who dtype (compat-opt-u8->datum (series-ref-u8/raw s index)))]
       [(uint16) (require-ref-value who dtype (compat-opt-u16->datum (series-ref-u16/raw s index)))]
       [(uint32) (require-ref-value who dtype (compat-opt-u32->datum (series-ref-u32/raw s index)))]
       [(uint64) (require-ref-value who dtype (compat-opt-u64->datum (series-ref-u64/raw s index)))]
       [(float32) (require-ref-value who dtype (compat-opt-f32->datum (series-ref-f32/raw s index)))]
       [(float64) (require-ref-value who dtype (compat-opt-f64->datum (series-ref-f64/raw s index)))]
       [(boolean)
        (define value (series-ref-bool/raw s index))
        (when (zero? (CompatOptBool-valid value))
          (error who "could not read non-null value for dtype ~v" dtype))
        (compat-opt-bool->datum value)]
       [(string) (require-ref-value who dtype (series-ref-string s index))]
       [(categorical enum)
        (string->symbol (require-ref-value who dtype (series-ref-cat s index)))]
       [(date) (require-ref-value who dtype (series-date-ref s index))]
       [(time)
        (define raw (compat-opt-i64->datum (series-ref-time/raw s index)))
        (require-ref-value who dtype (and raw (nanoseconds->time raw)))]
       [else
        (match dtype
          [`(duration ,_)
           (define raw (compat-opt-i64->datum (series-ref-duration/raw s index)))
           (require-ref-value who dtype (and raw (duration-value->period dtype raw)))]
          [`(datetime ,unit ,zoned)
           (require-ref-value who dtype
                              (series-ref-datetime who s index unit (and zoned (series-time-zone s))
                                                  unreadable))]
          [`(decimal ,_ ,scale) (require-ref-value who dtype (series-ref-decimal s index scale))]
          [_ (series-ref-unsupported who dtype)])])]
    [else (error who "could not read null state at index ~a" index)]))

(define-compat series-cast/c
  (_fun _Series-ptr _CompatDType -> _Series-ptr/null)
  #:c-id series_cast
  #:wrap (allocator series-drop))

(define-compat series-cast-enum/raw
  (_fun _Series-ptr _str-list -> _Series-ptr/null)
  #:c-id series_cast_enum_v2
  #:wrap (allocator series-drop))

(module enum-misses racket/base
  (require (only-in racket/string string-join))
  (provide enum-misses-message enum-misses-shown)

  (define enum-misses-shown 10)

  (define (spell value)
    (cond
      [(for/or ([c (in-string value)]) (char-iso-control? c)) (format "~s" value)]
      [else (format "~s" (string->symbol value))]))

  (define (enum-misses-message dtype missing total named distinct)
    (define noun (if (= total 1) "value" "values"))
    (define verb (if (= missing 1) "is" "are"))
    (define listed (string-join (map spell named)))
    (define more (- distinct (length named)))
    (define tail (if (positive? more) (format "~a, and ~a more" listed more) listed))
    (format "~a of ~a ~a ~a not in ~v: ~a" missing total noun verb dtype tail)))

(require 'enum-misses)

(define (series-cast-enum who s dtype)
  (define categories (map symbol->string (cdr dtype)))
  (define (misses)
    (match (series-dtype s)
      [(or 'string 'categorical (cons 'enum _))
       (with-release ([strings (series-cast-to who s 'string) series-drop]
                      [present (series-drop-nulls strings) series-drop])
         (series-rename present "value")
         (with-release ([known (strings->series who "value" categories) series-drop]
                        [left (dataframe-new (list present)) dataframe-drop]
                        [right (dataframe-new (list known)) dataframe-drop]
                        [missed (dataframe-join left right #:on '("value") #:how 'anti)
                                dataframe-drop]
                        [column (dataframe-column missed "value") series-drop]
                        [distinct (series-unique column) series-drop]
                        [sorted (series-sort distinct) series-drop]
                        [shown (series-head sorted enum-misses-shown) series-drop])
           (define named
             (for/list ([i (in-range (series-len shown))])
               (series-ref-string shown i)))
           (cond
             [(zero? (dataframe-height missed)) #f]
             [(memv #f named) #f]
             [else (enum-misses-message dtype (dataframe-height missed) (series-len present)
                                        named (series-len distinct))])))]
      [_ #f]))
  (call/foreign-error who
                      (lambda () (series-cast-enum/raw s categories))
                      #:explain misses
                      "cannot convert to ~v" dtype))

(define-compat series-cast-datetime-tz/raw
  (_fun _Series-ptr _int32 _c-string -> _Series-ptr/null)
  #:c-id series_cast_datetime_tz
  #:wrap (allocator series-drop))

(define (series-cast-datetime-tz who s dtype)
  (match-define (list _ unit zone) dtype)
  (call/foreign-error who
                      (lambda ()
                        (series-cast-datetime-tz/raw s (time-unit-symbol->code unit) zone))
                      "cannot convert to ~v" dtype))

(define (series-cast-to who s dtype)
  (cond
    [(enum-dtype? dtype) (series-cast-enum who s dtype)]
    [(zoned-datetime-dtype? dtype) (series-cast-datetime-tz who s dtype)]
    [else (call/foreign-error who (lambda () (series-cast/c s (->compat-dtype dtype)))
                              "cannot cast to ~s" dtype)]))

(define (series-cast s dtype)
  (series-cast-to 'series-cast s dtype))

(define-compat series-dt-convert-time-zone/raw
  (_fun _Series-ptr _c-string -> _Series-ptr/null)
  #:c-id series_dt_convert_time_zone
  #:wrap (allocator series-drop))

(define (series-dt-convert-time-zone who s zone)
  (call/foreign-error who
                      (lambda () (series-dt-convert-time-zone/raw s zone))
                      "cannot convert to the time zone ~s" zone))

(define-compat series-dt-replace-time-zone/raw
  (_fun _Series-ptr _c-string/null _c-string _c-string -> _Series-ptr/null)
  #:c-id series_dt_replace_time_zone
  #:wrap (allocator series-drop))

(define (series-dt-replace-time-zone who s zone ambiguous non-existent)
  (call/foreign-error who
                      (lambda ()
                        (series-dt-replace-time-zone/raw s zone (symbol->string ambiguous)
                                                         (symbol->string non-existent)))
                      "~a" (replace-zone-failure zone)))

(define (replace-zone-failure zone)
  (if zone
      (format "cannot replace the time zone with ~s" zone)
      "cannot unset the time zone"))

(define-reasoned (series-std s [#:ddof ddof 1])
  #:ok? (compose1 (negate negative?) CompatOptF64-valid)
  #:result compat-opt-f64->datum
  (define-compat series-std/raw
    (_fun _Series-ptr _uint8 -> _CompatOptF64)
    #:c-id series_std_v2))

(define-reasoned (series-var s [#:ddof ddof 1])
  #:ok? (compose1 (negate negative?) CompatOptF64-valid)
  #:result compat-opt-f64->datum
  (define-compat series-var/raw
    (_fun _Series-ptr _uint8 -> _CompatOptF64)
    #:c-id series_var_v2))

(define-reasoned (series-quantile s quantile [#:interpolation interpolation 'nearest])
  #:ok? (compose1 (negate negative?) CompatOptF64-valid)
  #:result compat-opt-f64->datum
  (define-compat series-quantile/raw
    (_fun _Series-ptr _double* (_enum '(nearest linear lower higher midpoint) _uint8)
          -> _CompatOptF64)
    #:c-id series_quantile_v2))

(define-syntax-parse-rule (define-series-series-op name:id name/who:id raw-name:id rust-id:id)
  (define-reasoned (name a b) #:who-variant name/who
    (define-compat raw-name
      (_fun _Series-ptr _Series-ptr -> _Series-ptr/null)
      #:c-id rust-id
      #:wrap (allocator series-drop))))

(define-series-series-op series-eq series-eq/who series-eq/raw series_eq)
(define-series-series-op series-ne series-ne/who series-ne/raw series_ne)
(define-series-series-op series-gt series-gt/who series-gt/raw series_gt)
(define-series-series-op series-ge series-ge/who series-ge/raw series_ge)
(define-series-series-op series-lt series-lt/who series-lt/raw series_lt)
(define-series-series-op series-le series-le/who series-le/raw series_le)

(define-series-series-op series-add series-add/who series-add/raw series_add)
(define-series-series-op series-sub series-sub/who series-sub/raw series_sub)
(define-series-series-op series-mul series-mul/who series-mul/raw series_mul)
(define-series-series-op series-div series-div/who series-div/raw series_div)
(define-series-series-op series-mod series-mod/who series-mod/raw series_mod)

(begin-for-syntax
  (define-syntax-class scalar-ctype
    #:attributes (range)
    (pattern (~literal _int32) #:with range #'int32/c)
    (pattern (~literal _int64) #:with range #'int64/c)
    (pattern (~literal _uint32) #:with range #'uint32/c)
    (pattern (~literal _uint64) #:with range #'uint64/c)
    (pattern (~literal _double*) #:with range #'real?)))

(define-syntax-parse-rule (define-series-scalar-op name:id ctype:scalar-ctype)
  #:with raw (format-id #'here "~a/raw" #'name)
  #:with name/who (format-id #'here "~a/who" #'name)
  #:with c-id (format-id #'name "~a" (string-replace (symbol->string (syntax-e #'name)) "-" "_"))
  (begin
    (define-reasoned (name s v) #:who-variant name/who
      (define-compat raw
        (_fun _Series-ptr ctype -> _Series-ptr/null)
        #:c-id c-id
        #:wrap (allocator series-drop)))
    (provide (contract-out [name (->/c Series-ptr? ctype.range Series-ptr?)]))))

(define-series-scalar-op series-add-i32 _int32)
(define-series-scalar-op series-sub-i32 _int32)
(define-series-scalar-op series-mul-i32 _int32)
(define-series-scalar-op series-div-i32 _int32)
(define-series-scalar-op series-mod-i32 _int32)

(define-series-scalar-op series-add-i64 _int64)
(define-series-scalar-op series-sub-i64 _int64)
(define-series-scalar-op series-mul-i64 _int64)
(define-series-scalar-op series-div-i64 _int64)
(define-series-scalar-op series-mod-i64 _int64)

(define-series-scalar-op series-add-u32 _uint32)
(define-series-scalar-op series-sub-u32 _uint32)
(define-series-scalar-op series-mul-u32 _uint32)
(define-series-scalar-op series-div-u32 _uint32)
(define-series-scalar-op series-mod-u32 _uint32)

(define-series-scalar-op series-add-u64 _uint64)
(define-series-scalar-op series-sub-u64 _uint64)
(define-series-scalar-op series-mul-u64 _uint64)
(define-series-scalar-op series-div-u64 _uint64)
(define-series-scalar-op series-mod-u64 _uint64)

(define-series-scalar-op series-add-f64 _double*)
(define-series-scalar-op series-sub-f64 _double*)
(define-series-scalar-op series-mul-f64 _double*)
(define-series-scalar-op series-div-f64 _double*)
(define-series-scalar-op series-mod-f64 _double*)

(define-owned-cpointer-type _DataFrame-ptr dataframe
  (define-compat dataframe-drop/raw
    (_fun _DataFrame-ptr -> _void)
    #:c-id dataframe_drop
    #:wrap (deallocator)))

(define-compat dataframe-drop-count
  (_fun -> _size))

(define-compat dataframe-make
  (_fun -> _DataFrame-ptr)
  #:wrap (allocator dataframe-drop))

(define-compat dataframe-empty
  (_fun -> _DataFrame-ptr)
  #:wrap (allocator dataframe-drop))

(define-cstruct _Shape
  ([rows _size]
   [cols _size]))

(define-compat dataframe-shape
  (_fun _DataFrame-ptr
        -> (s : _Shape)
        -> (values (Shape-rows s) (Shape-cols s))))

(define-compat dataframe-height
  (_fun _DataFrame-ptr -> _size))

(define-compat dataframe-width
  (_fun _DataFrame-ptr -> _size))

(define-reasoned (dataframe-head df n)
  (define-compat dataframe-head/raw
    (_fun _DataFrame-ptr _size -> _DataFrame-ptr/null)
    #:c-id dataframe_head
    #:wrap (allocator dataframe-drop)))

(define-reasoned (dataframe-tail df n)
  (define-compat dataframe-tail/raw
    (_fun _DataFrame-ptr _size -> _DataFrame-ptr/null)
    #:c-id dataframe_tail
    #:wrap (allocator dataframe-drop)))

(define-reasoned (dataframe-slice df offset length)
  (define-compat dataframe-slice/raw
    (_fun _DataFrame-ptr _int64 _size -> _DataFrame-ptr/null)
    #:c-id dataframe_slice
    #:wrap (allocator dataframe-drop)))

(define-compat dataframe-column-names
  (_fun _DataFrame-ptr -> _rsstr-list))

(define-compat dataframe-select/c
  (_fun _DataFrame-ptr _str-list -> _DataFrame-ptr/null)
  #:c-id dataframe_select_v2
  #:wrap (allocator dataframe-drop))

(define (dataframe-select df cols)
  (call/polars-reason 'dataframe-select (lambda () (dataframe-select/c df cols))))

(define-compat dataframe-drop-columns/c
  (_fun _DataFrame-ptr _str-list -> _DataFrame-ptr/null)
  #:c-id dataframe_drop_columns_v2
  #:wrap (allocator dataframe-drop))

(define (dataframe-drop-columns df cols)
  (call/polars-reason 'dataframe-drop-columns (lambda () (dataframe-drop-columns/c df cols))))

(define-compat dataframe-rename/raw
  (_fun _DataFrame-ptr _str _str -> _DataFrame-ptr/null)
  #:c-id dataframe_rename_v2
  #:wrap (allocator dataframe-drop))

(define (dataframe-rename df old new)
  (call/polars-reason 'dataframe-rename (lambda () (dataframe-rename/raw df old new))))

(define-compat dataframe-with-column/raw
  (_fun _DataFrame-ptr _Series-ptr -> _DataFrame-ptr/null)
  #:c-id dataframe_with_column
  #:wrap (allocator dataframe-drop))

(define (dataframe-with-column df s)
  (call/polars-reason 'dataframe-with-column (lambda () (dataframe-with-column/raw df s))))

(define-syntax-parse-rule (define-frame-op/reason (name:id arg:id ...) call:expr compat:expr)
  #:with name/who (format-id #'name "~a/who" #'name)
  (begin
    compat
    (define (name/who who arg ...) (call/polars-reason who (lambda () call)))))

(define-frame-op/reason (dataframe-hstack d columns)
  (dataframe-hstack/raw d columns)
  (define-compat dataframe-hstack/raw
    (_fun _DataFrame-ptr
          (v : (_list i _Series-ptr))
          (_size = (length v))
          -> _DataFrame-ptr/null)
    #:c-id dataframe_hstack
    #:wrap (allocator dataframe-drop)))

(define (dataframe-hstack d columns)
  (dataframe-hstack/who 'dataframe-hstack d columns))

(define-compat dataframe-new/raw
  (_fun (v : (_list i _Series-ptr))
        (_size = (length v))
        -> _DataFrame-ptr/null)
  #:c-id dataframe_new
  #:wrap (allocator dataframe-drop))

(define (dataframe-new series-list)
  (or (dataframe-new/raw series-list) (error 'dataframe-new "operation failed")))

(define-compat dataframe-column-name
  (_fun _DataFrame-ptr _size -> _rsstr)
  #:c-id dataframe_column_name_v2)

(define-compat dataframe-column/raw
  (_fun _DataFrame-ptr _str -> _Series-ptr/null)
  #:c-id dataframe_column_v2
  #:wrap (allocator series-drop))

(define (dataframe-column df name)
  (or (dataframe-column/raw df name)
      (error 'dataframe-column "no column named ~s" name)))

(define-compat dataframe->string/raw
  (_fun _DataFrame-ptr -> _rsstr)
  #:c-id dataframe_to_string_v2)

(define (print-dataframe who df)
  (call/foreign-error who (lambda () (dataframe->string/raw df)) "cannot print the dataframe"))

(define (dataframe->string df)
  (print-dataframe 'dataframe->string df))

(define (glob-pattern? p)
  (regexp-match? #rx"[*?[]" (if (path? p) (path->string p) p)))

(define (path->complete-string who p #:glob? [glob? #f])
  (unless (path-string? p)
    (raise-argument-error who "path-string?" p))
  (define full (path->string (path->complete-path p)))
  (if (and glob? (relative-path? p) (not (directory-exists? full)))
      (path->string
       (build-path (regexp-replace* #rx"[][*?]" (path->string (current-directory)) "[&]") p))
      full))

(define-series-scalar-op series-lt-i32 _int32)
(define-series-scalar-op series-le-i32 _int32)
(define-series-scalar-op series-gt-i32 _int32)
(define-series-scalar-op series-ge-i32 _int32)
(define-series-scalar-op series-eq-i32 _int32)
(define-series-scalar-op series-ne-i32 _int32)

(define-series-scalar-op series-lt-f64 _double*)
(define-series-scalar-op series-le-f64 _double*)
(define-series-scalar-op series-gt-f64 _double*)
(define-series-scalar-op series-ge-f64 _double*)
(define-series-scalar-op series-eq-f64 _double*)
(define-series-scalar-op series-ne-f64 _double*)

(define ((series-str-op op/who who) s v)
  (with-release ([rhs (strings->series who "" (list v)) series-drop])
    (op/who who s rhs)))

(define series-eq-str (series-str-op series-eq/who 'series-eq-str))
(define series-ne-str (series-str-op series-ne/who 'series-ne-str))

(define-reasoned (series-is-null s)
  (define-compat series-is-null/raw
    (_fun _Series-ptr -> _Series-ptr/null)
    #:c-id series_is_null
    #:wrap (allocator series-drop)))

(define-reasoned (series-is-not-null s)
  (define-compat series-is-not-null/raw
    (_fun _Series-ptr -> _Series-ptr/null)
    #:c-id series_is_not_null
    #:wrap (allocator series-drop)))

(define-series-series-op series-and series-and/who series-and/raw series_and)
(define-series-series-op series-or series-or/who series-or/raw series_or)
(define-series-series-op series-xor series-xor/who series-xor/raw series_xor)

(define-reasoned (series-not s) #:who-variant series-not/who
  (define-compat series-not/raw
    (_fun _Series-ptr -> _Series-ptr/null)
    #:c-id series_not
    #:wrap (allocator series-drop)))

(define-reasoned (dataframe-filter df mask)
  (define-compat dataframe-filter/raw
    (_fun _DataFrame-ptr _Series-ptr -> _DataFrame-ptr/null)
    #:c-id dataframe_filter
    #:wrap (allocator dataframe-drop)))

(define-compat dataframe-sort/raw
  (_fun _DataFrame-ptr
        (names : _str-list)
        (descending : (_list i _stdbool))
        (nulls-last : (_list i _stdbool))
        (_size = (length names))
        (maintain-order : _stdbool)
        -> _DataFrame-ptr/null)
  #:c-id dataframe_sort_with_options_v2
  #:wrap (allocator dataframe-drop))

(define sort-flags/c
  (flat-named-contract 'sort-flags/c (or/c boolean? (listof boolean?))))

(define (sort-flags-mismatch keys descending nulls-last)
  (define n (if (list? keys) (length keys) 1))
  (or (for/first ([flags (in-list (list descending nulls-last))]
                  [keyword (in-list '("#:descending" "#:nulls-last"))]
                  #:when (and (list? flags) (not (= (length flags) n))))
        (format "the length of ~a (~a) does not match the number of sort keys (~a)"
                keyword (length flags) n))
      #t))

(define (frame-sort/c frame? name)
  (rename-contract
   (->i ([frame frame?] [names (non-empty-listof string?)])
        (#:descending [descending sort-flags/c]
         #:nulls-last [nulls-last sort-flags/c]
         #:maintain-order [maintain-order boolean?])
        #:pre/desc (names descending nulls-last)
        (sort-flags-mismatch names descending nulls-last)
        [result frame?])
   name))

;; the raw bindings read (length names) flags from each list: never pass a shorter one
(define (sort-flags who keyword flags keys)
  (cond
    [(boolean? flags) (for/list ([_ (in-list keys)]) flags)]
    [(= (length flags) (length keys)) flags]
    [else (raise-arguments-error who (format "~a needs one flag per sort key" keyword)
                                 keyword flags
                                 "keys" keys)]))

(define (dataframe-sort/who who df names descending nulls-last maintain-order)
  (define flags (sort-flags who "#:descending" descending names))
  (define nulls (sort-flags who "#:nulls-last" nulls-last names))
  (call/polars-reason who (lambda () (dataframe-sort/raw df names flags nulls maintain-order))))

(define (dataframe-sort df names
                        #:descending [descending #f]
                        #:nulls-last [nulls-last #f]
                        #:maintain-order [maintain-order #f])
  (dataframe-sort/who 'dataframe-sort df names descending nulls-last maintain-order))

(define-syntax-parse-rule (define-group-by-agg agg:id)
  #:with name (format-id #'agg "dataframe-group-by-~a" #'agg)
  #:with raw (format-id #'agg "dataframe-group-by-~a/c" #'agg)
  #:with rust-id (format-id #'agg "dataframe_group_by_~a_v2" #'agg)
  (begin
    (define-compat raw
      (_fun _DataFrame-ptr _str-list _str-list -> _DataFrame-ptr/null)
      #:c-id rust-id
      #:wrap (allocator dataframe-drop))
    (define (name df #:by by #:agg agg)
      (call/polars-reason 'name (lambda () (raw df by agg))))))

(define-group-by-agg sum)
(define-group-by-agg mean)
(define-group-by-agg min)
(define-group-by-agg max)
(define-group-by-agg count)

(define-reasoned (dataframe-unique df)
  (define-compat dataframe-unique/raw
    (_fun _DataFrame-ptr -> _DataFrame-ptr/null)
    #:c-id dataframe_unique
    #:wrap (allocator dataframe-drop)))

(define-reasoned (dataframe-drop-nulls df)
  (define-compat dataframe-drop-nulls/raw
    (_fun _DataFrame-ptr -> _DataFrame-ptr/null)
    #:c-id dataframe_drop_nulls
    #:wrap (allocator dataframe-drop)))

(define-frame-op/reason (dataframe-join left right left-on right-on how)
  (dataframe-join/c left right left-on right-on (join-symbol->code how))
  (define-compat dataframe-join/c
    (_fun _DataFrame-ptr _DataFrame-ptr _str-list _str-list _int32 -> _DataFrame-ptr/null)
    #:c-id dataframe_join_v2
    #:wrap (allocator dataframe-drop)))

(define (dataframe-join left right
                        #:on [on #f]
                        #:left-on [left-on #f]
                        #:right-on [right-on #f]
                        #:how [how 'inner])
  (define-values (lon ron) (join-keys how on left-on right-on))
  (dataframe-join/who 'dataframe-join left right lon ron how))

(define-compat dataframe-join-asof/raw
  (_fun _DataFrame-ptr _DataFrame-ptr _str _str _int32 -> _DataFrame-ptr/null)
  #:c-id dataframe_join_asof_v2
  #:wrap (allocator dataframe-drop))

(define-frame-op/reason (dataframe-join-asof left right left-on right-on left-by right-by
                                             strategy tolerance)
  (let-values ([(kind integer float) (asof-tolerance->parts tolerance)])
    (dataframe-join-asof-options/raw left right left-on right-on
                                     (asof-strategy-symbol->code strategy)
                                     left-by right-by kind integer float))
  (define-compat dataframe-join-asof-options/raw
    (_fun _DataFrame-ptr _DataFrame-ptr _str _str _int32 _str-list _str-list _int32 _int64 _double
          -> _DataFrame-ptr/null)
    #:c-id dataframe_join_asof_options_v2
    #:wrap (allocator dataframe-drop)))

(define (dataframe-join-asof left right
                             #:on [on #f]
                             #:left-on [left-on #f]
                             #:right-on [right-on #f]
                             #:by [by #f]
                             #:left-by [left-by #f]
                             #:right-by [right-by #f]
                             #:strategy [strategy 'backward]
                             #:tolerance [tolerance #f])
  (define-values (lon ron lby rby) (asof-keys on left-on right-on by left-by right-by))
  (dataframe-join-asof/who 'dataframe-join-asof left right lon ron lby rby strategy tolerance))

(define-frame-op/reason (dataframe-vstack top bottom)
  (dataframe-vstack/raw top bottom)
  (define-compat dataframe-vstack/raw
    (_fun _DataFrame-ptr _DataFrame-ptr -> _DataFrame-ptr/null)
    #:c-id dataframe_vstack
    #:wrap (allocator dataframe-drop)))

(define (dataframe-vstack top bottom)
  (dataframe-vstack/who 'dataframe-vstack top bottom))

(define compat-pivot-agg/none  0)
(define compat-pivot-agg/first 1)
(define compat-pivot-agg/sum   2)
(define compat-pivot-agg/min   3)
(define compat-pivot-agg/max   4)
(define compat-pivot-agg/mean  5)
(define compat-pivot-agg/count 6)

(define (pivot-agg-symbol->code sym)
  (case sym
    [(none #f) compat-pivot-agg/none]
    [(first)   compat-pivot-agg/first]
    [(sum)     compat-pivot-agg/sum]
    [(min)     compat-pivot-agg/min]
    [(max)     compat-pivot-agg/max]
    [(mean)    compat-pivot-agg/mean]
    [(count)   compat-pivot-agg/count]
    [else (error 'dataframe-pivot
                 "unknown pivot aggregation ~v (expected #f 'first 'sum 'min 'max 'mean 'count)"
                 sym)]))

(define-compat dataframe-pivot/raw
  (_fun _DataFrame-ptr _str-list _str-list _str-list _int32 -> _DataFrame-ptr/null)
  #:c-id dataframe_pivot_v2
  #:wrap (allocator dataframe-drop))

(define (pivot-frame who df on index values agg)
  (call/foreign-error who
                      (lambda () (dataframe-pivot/raw df on index values (pivot-agg-symbol->code agg)))
                      "cannot pivot the dataframe"))

(define (dataframe-pivot df #:on on #:index index #:values values
                         #:agg [agg 'first])
  (pivot-frame 'dataframe-pivot df on index values agg))

(define-compat dataframe-unpivot/raw
  (_fun _DataFrame-ptr _str-list _str-list -> _DataFrame-ptr/null)
  #:c-id dataframe_unpivot_v2
  #:wrap (allocator dataframe-drop))

(define (unpivot-frame who df on index)
  (call/foreign-error who (lambda () (dataframe-unpivot/raw df on index))
                      "cannot unpivot the dataframe"))

(define (dataframe-unpivot df #:on on #:index index)
  (unpivot-frame 'dataframe-unpivot df on index))

(define (display-dataframe df [out (current-output-port)])
  (display (print-dataframe 'display-dataframe df) out)
  (newline out))

(module+ internal
  (provide block-reader dataframe-drop dataframe-head dataframe-hstack dataframe-hstack/who dataframe-join
           dataframe-join-asof dataframe-join-asof/who dataframe-join/who dataframe-slice
           dataframe-sort dataframe-sort/who dataframe-tail dataframe-vstack
           dataframe-vstack/who series-add-i32 series-add-i64 series-add-u32 series-add-u64
           series-div-i32 series-div-i64 series-div-u32 series-div-u64 series-drop series-eq-i32
           series-ge-i32 series-gt-i32 series-head series-le-i32 series-lt-i32 series-mod-i32
           series-mod-i64 series-mod-u32 series-mod-u64 series-mul-i32 series-mul-i64
           series-mul-u32 series-mul-u64 series-ne-i32 series-new-null series-ref-bytes
           series-ref-cat series-slice series-sort series-std series-strings series-sub-i32
           series-sub-i64 series-sub-u32 series-sub-u64 series-tail series-var))
