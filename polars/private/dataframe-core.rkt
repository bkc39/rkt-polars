#lang racket/base

(require ffi/unsafe
         ffi/unsafe/alloc
         (only-in racket/contract/base [-> ->/c] contract-out listof or/c)
         (only-in racket/provide matching-identifiers-out)
         syntax/parse/define
         (only-in polars/private/c-integer size/c)
         (only-in polars/private/compat-ffi _rsstr _rsstr-list define-compat)
         (only-in polars/private/owned DataFrame-ptr? Series-ptr? _DataFrame-ptr
                  _DataFrame-ptr/null _Series-ptr _Series-ptr/null provide-row-windows)
         (only-in polars/private/reason call/foreign-error call/polars-reason)
         (only-in (submod polars/private/owned internal) dataframe-drop)
         (only-in (submod polars/private/reason internal) define-reasoned)
         (only-in polars/private/resource _str _str-list)
         (for-syntax racket/base racket/syntax syntax/parse))

(provide (except-out (all-defined-out)
                     dataframe-column-name dataframe-head dataframe-hstack dataframe-slice
                     dataframe-tail dataframe-vstack define-frame-op/reason print-dataframe
                     (matching-identifiers-out #rx"^dataframe-.*/who$" (all-defined-out)))
         (contract-out
          [dataframe-column-name (->/c DataFrame-ptr? size/c (or/c string? #f))]
          [dataframe-hstack (->/c DataFrame-ptr? (listof Series-ptr?) DataFrame-ptr?)]
          [dataframe-vstack (->/c DataFrame-ptr? DataFrame-ptr? DataFrame-ptr?)]))

(provide-row-windows DataFrame-ptr? dataframe-head dataframe-tail dataframe-slice)

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

(define-reasoned (dataframe-head df n) #:who-variant dataframe-head/who
  (_fun _DataFrame-ptr _size -> _DataFrame-ptr/null))

(define-reasoned (dataframe-tail df n) #:who-variant dataframe-tail/who
  (_fun _DataFrame-ptr _size -> _DataFrame-ptr/null))

(define-reasoned (dataframe-slice df offset len) #:who-variant dataframe-slice/who
  (_fun _DataFrame-ptr _int64 _size -> _DataFrame-ptr/null))

(define-compat dataframe-column-names
  (_fun _DataFrame-ptr -> _rsstr-list))

(define-reasoned (dataframe-select df cols) #:who-variant dataframe-select/who
  #:c-id dataframe_select_v2
  (_fun _DataFrame-ptr _str-list -> _DataFrame-ptr/null))

(define-reasoned (dataframe-drop-columns df cols) #:who-variant dataframe-drop-columns/who
  #:c-id dataframe_drop_columns_v2
  (_fun _DataFrame-ptr _str-list -> _DataFrame-ptr/null))

(define-reasoned (dataframe-rename df old new) #:who-variant dataframe-rename/who
  #:c-id dataframe_rename_v2
  (_fun _DataFrame-ptr _str _str -> _DataFrame-ptr/null))

(define-reasoned (dataframe-with-column df s) #:who-variant dataframe-with-column/who
  (_fun _DataFrame-ptr _Series-ptr -> _DataFrame-ptr/null))

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

(define-compat dataframe-column-name/raw
  (_fun _DataFrame-ptr _size -> _rsstr)
  #:c-id dataframe_column_name_v2)

(define (dataframe-column-name df i)
  (dataframe-column-name/raw df i))

(define-reasoned (dataframe-column df name) #:who-variant dataframe-column/who
  #:c-id dataframe_column_v2
  (_fun _DataFrame-ptr _str -> _Series-ptr/null))

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

(define-reasoned (dataframe-filter df mask)
  (_fun _DataFrame-ptr _Series-ptr -> _DataFrame-ptr/null))

(define-reasoned (dataframe-unique df) #:who-variant dataframe-unique/who
  (_fun _DataFrame-ptr -> _DataFrame-ptr/null))

(define-reasoned (dataframe-drop-nulls df) #:who-variant dataframe-drop-nulls/who
  (_fun _DataFrame-ptr -> _DataFrame-ptr/null))

(define-frame-op/reason (dataframe-vstack top bottom)
  (dataframe-vstack/raw top bottom)
  (define-compat dataframe-vstack/raw
    (_fun _DataFrame-ptr _DataFrame-ptr -> _DataFrame-ptr/null)
    #:c-id dataframe_vstack
    #:wrap (allocator dataframe-drop)))

(define (dataframe-vstack top bottom)
  (dataframe-vstack/who 'dataframe-vstack top bottom))

(define (display-dataframe df [out (current-output-port)])
  (display (print-dataframe 'display-dataframe df) out)
  (newline out))

(module+ internal
  (provide dataframe-column/who dataframe-drop-columns/who dataframe-drop-nulls/who
           dataframe-head dataframe-head/who dataframe-hstack dataframe-hstack/who
           dataframe-rename/who dataframe-select/who dataframe-slice dataframe-slice/who
           dataframe-tail dataframe-tail/who dataframe-unique/who dataframe-vstack
           dataframe-vstack/who dataframe-with-column/who define-frame-op/reason))
