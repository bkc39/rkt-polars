#lang racket/base

(require ffi/unsafe
         ffi/unsafe/alloc
         ffi/unsafe/atomic
         (only-in racket/dict in-dict)
         syntax/parse/define
         (only-in polars/private/compat-ffi _rsstr define-compat)
         (only-in polars/private/enum-misses enum-cast-reason enum-misses-reason)
         (only-in polars/private/owned _DataFrame-ptr/null _Series-ptr/null)
         (only-in (submod polars/private/owned internal) dataframe-drop series-drop)
         (for-syntax racket/base racket/syntax (only-in racket/string string-replace) syntax/parse))

(provide (except-out (all-defined-out)
                     call/reason define-reasoned expanded-reason no-problem spelling-rules))

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
     . "")
    ("setting `strict=False` to set values that cannot be converted to `null`"
     . "passing #:strict #f to set values that cannot be converted to null")
    ("using `str.strptime`, `str.to_date`, or `str.to_datetime` and providing a format string"
     . "passing str->date or str->datetime a #:format string")
    (" passed to `LazyFrame.with_columns` is duplicate" . " is duplicate")
    ("The predicate passed to 'LazyFrame.filter' expanded" . "The predicate expanded")
    ("Try to combine the predicates with the 'all_horizontal' or `any_horizontal' expression."
     . "Combine them into one predicate with and or or.")
    (#rx", hint: (?:specify this field in the schema, or )?pass cast_options=pl\\.ScanCastOptions\\([^)]*\\)"
     . "")))

(define empty-expansion
  #rx"^failed to retrieve [^:]*: expanded paths were empty \\(path expansion input: .*\\)\\.")

(define spelling-rules
  (for/list ([(python racket) (in-dict racket-spellings)])
    (cons (if (regexp? python) python (regexp (regexp-quote python)))
          (regexp-replace-quote racket))))

(define (expanded-reason reason)
  (if (or (regexp-match? empty-expansion reason)
          (equal? reason "no paths specified for this reader"))
      "no files match the pattern"
      reason))

(define (respell reason)
  (for/fold ([reason (expanded-reason reason)])
            ([rule (in-list spelling-rules)])
    (regexp-replace* (car rule) reason (cdr rule))))

;; only for entry points that call clear_last_error; elsewhere the slot is stale
(define (call/reason thunk ok?)
  (call-as-atomic
   (lambda ()
     (define result (thunk))
     (values result (and (not (ok? result)) (last-error-message))))))

(define (call/foreign-error who thunk #:ok? [ok? values] #:problem [problem no-problem]
                            #:cause [cause values] [fmt #f] . args)
  (define-values (result reason) (call/reason thunk ok?))
  (define (cause-of reason) (cause (respell reason)))
  (cond
    [(ok? result) result]
    [(problem) => (lambda (message) (raise-arguments-error who message))]
    [(and reason (or (enum-misses-reason reason) (enum-cast-reason reason)))
     => (lambda (message) (error who "~a" message))]
    [(and reason fmt)
     (apply error who (string-append fmt ": ~a") (append args (list (cause-of reason))))]
    [reason (error who "~a" (cause-of reason))]
    [fmt (apply error who fmt args)]
    [else (error who "no reason recorded")]))

(define (call/polars-reason who thunk)
  (call/foreign-error who thunk))

(begin-for-syntax
  (define-syntax-class reasoned-formal
    #:attributes (arg [formal 1] [actual 1])
    (pattern arg:id
             #:with (formal ...) #'(arg)
             #:with (actual ...) #'(arg))
    (pattern [kw:keyword arg:id default:expr]
             #:with (formal ...) #'(kw [arg default])
             #:with (actual ...) #'(kw arg)))

  (define-syntax-class owned-result
    #:attributes (drop)
    (pattern (~literal _Series-ptr/null) #:with drop #'series-drop)
    (pattern (~literal _DataFrame-ptr/null) #:with drop #'dataframe-drop))

  (define-splicing-syntax-class (reasoned-binding name)
    #:attributes (compat raw)
    (pattern (~seq (~and compat ((~datum define-compat) raw:id _ ...))))
    (pattern (~seq (~optional (~seq #:c-id c-id:id)
                              #:defaults ([c-id (format-id #'here "~a"
                                                           (string-replace
                                                            (symbol->string (syntax-e name))
                                                            "-" "_"))]))
                   (~and fun ((~literal _fun) _ ... (~datum ->) result:owned-result)))
             #:with raw (format-id #'here "~a/raw" name)
             #:with compat #'(define-compat raw
                               fun
                               #:c-id c-id
                               #:wrap (allocator result.drop)))))

(define (no-problem) #f)

(define-syntax-parse-rule (define-reasoned (name:id f:reasoned-formal ...)
                            (~optional (~seq #:who-variant name/who:id)
                                       #:defaults ([name/who (generate-temporary #'name)]))
                            (~optional (~seq #:ok? ok?:expr) #:defaults ([ok? #'values]))
                            (~optional (~seq #:result result:expr) #:defaults ([result #'values]))
                            (~var binding (reasoned-binding #'name)))
  #:with (ok-proc result-proc) (generate-temporaries '(ok result))
  (begin
    binding.compat
    (define ok-proc ok?)
    (define result-proc result)
    (define (name/who who f.formal ... ... #:problem [problem no-problem])
      (result-proc (call/foreign-error who (lambda () (binding.raw f.arg ...))
                                       #:ok? ok-proc #:problem problem)))
    (define (name f.formal ... ...)
      (name/who 'name f.actual ... ...))))

(define (printed-or-placeholder what render)
  (define-values (text reason) (call/reason render values))
  (or text (format "#<~a: cannot print: ~a>" what (or reason "no reason recorded"))))

(module+ internal
  (provide call/reason define-reasoned))
