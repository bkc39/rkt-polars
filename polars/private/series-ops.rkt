#lang racket/base

(require ffi/unsafe
         ffi/unsafe/alloc
         (only-in racket/contract/base [-> ->/c] ->* contract-out or/c real-in)
         (only-in racket/function negate)
         (only-in racket/provide matching-identifiers-out)
         (only-in racket/string string-replace)
         syntax/parse/define
         (only-in polars/private/c-integer int32/c int64/c uint32/c uint64/c uint8/c)
         polars/private/compat-opt
         (only-in polars/private/compat-ffi define-compat)
         (only-in polars/private/owned Series-ptr? _Series-ptr _Series-ptr/null provide-row-windows)
         (only-in polars/private/reason call/foreign-error)
         (only-in (submod polars/private/owned internal) series-drop)
         (only-in (submod polars/private/reason internal) define-reasoned)
         (only-in (submod polars/private/series-new internal) strings->series)
         (only-in polars/private/resource with-release)
         (for-syntax racket/base racket/syntax (only-in racket/string string-replace) syntax/parse))

(provide (except-out (all-defined-out)
                     define-typed-reduction define-typed-reductions series-head series-n-unique
                     series-n-unique/raw series-quantile series-quantile/raw series-slice
                     series-sort series-sort/who series-std series-std/raw series-str-op
                     series-tail series-var series-var/raw typed-reductions
                     series-add-i32 series-sub-i32 series-mul-i32 series-div-i32 series-mod-i32
                     series-add-i64 series-sub-i64 series-mul-i64 series-div-i64 series-mod-i64
                     series-add-u32 series-sub-u32 series-mul-u32 series-div-u32 series-mod-u32
                     series-add-u64 series-sub-u64 series-mul-u64 series-div-u64 series-mod-u64
                     series-lt-i32 series-le-i32 series-gt-i32 series-ge-i32 series-eq-i32
                     series-ne-i32
                     series-add-f64 series-sub-f64 series-mul-f64 series-div-f64 series-mod-f64
                     series-lt-f64 series-le-f64 series-gt-f64 series-ge-f64 series-eq-f64
                     series-ne-f64
                     (matching-identifiers-out
                      #rx"^series-(?:(?:sum|min|max|mean)-[iuf][0-9]+|head|tail|slice|reverse|drop-nulls|unique|n-unique|std|var)/who$"
                      (all-defined-out)))
         (contract-out
          [series-sort (->* (Series-ptr?) (#:descending boolean? #:nulls-last boolean?)
                            Series-ptr?)]
          [series-std (->* (Series-ptr?) (#:ddof uint8/c) (or/c flonum? #f))]
          [series-var (->* (Series-ptr?) (#:ddof uint8/c) (or/c flonum? #f))]
          [series-n-unique (->/c Series-ptr? exact-nonnegative-integer?)]
          [series-quantile
           (->* (Series-ptr? (real-in 0 1))
                (#:interpolation (or/c 'nearest 'linear 'lower 'higher 'midpoint))
                (or/c flonum? #f))]))

(provide-row-windows Series-ptr? series-head series-tail series-slice)

(begin-for-syntax
  (define-syntax-class reduction-dtype
    #:attributes (opt-type valid opt->datum dtype)
    (pattern t:id
             #:fail-unless (memq (syntax-e #'t) '(i8 i16 i32 i64 u8 u16 u32 u64 f32 f64))
             "a numeric dtype suffix"
             #:do [(define suffix (symbol->string (syntax-e #'t)))
                   (define upper (string-upcase suffix))
                   (define kind (hash-ref #hash(("i" . "int") ("u" . "uint") ("f" . "float"))
                                          (substring suffix 0 1)))]
             #:with dtype (string->symbol (string-append kind (substring suffix 1)))
             #:with opt-type (format-id #'t "_CompatOpt~a" upper)
             #:with valid (format-id #'t "CompatOpt~a-valid" upper)
             #:with opt->datum (format-id #'t "compat-opt-~a->datum" #'t))))

(define-syntax-parse-rule (define-typed-reduction op:id t:id opt-type:id valid:id opt->datum:id)
  #:with name (format-id #'t "series-~a-~a" #'op #'t)
  #:with name/who (format-id #'name "~a/who" #'name)
  #:with raw (format-id #'here "~a/raw" #'name)
  #:with c-id (format-id #'here "series_~a_~a_v2" #'op #'t)
  (define-reasoned (name s) #:who-variant name/who
    #:ok? (compose1 (negate negative?) valid)
    #:result opt->datum
    (define-compat raw
      (_fun _Series-ptr -> opt-type)
      #:c-id c-id)))

(define-syntax-parse-rule (define-typed-reductions table:id t:reduction-dtype ...)
  #:with (op ...) #'(sum min max mean)
  #:with ((op/who ...) ...) (for/list ([op (in-list (syntax->list #'(op ...)))])
                              (for/list ([t (in-list (syntax->list #'(t ...)))])
                                (format-id t "series-~a-~a/who" op t)))
  (begin
    (begin
      (define-typed-reduction sum t t.opt-type t.valid t.opt->datum)
      (define-typed-reduction min t t.opt-type t.valid t.opt->datum)
      (define-typed-reduction max t t.opt-type t.valid t.opt->datum)
      (define-typed-reduction mean t _CompatOptF64 CompatOptF64-valid compat-opt-f64->datum))
    ...
    (define table
      (hash (~@ 'op (hash (~@ 't.dtype op/who) ...)) ...))))

(define-typed-reductions typed-reductions i8 i16 i32 i64 u8 u16 u32 u64 f32 f64)

(define-reasoned (series-n-unique s) #:who-variant series-n-unique/who
  #:ok? (negate negative?)
  (define-compat series-n-unique/raw
    (_fun _Series-ptr -> _int64)
    #:c-id series_n_unique_v2))

(define-reasoned (series-head s n) #:who-variant series-head/who
  (_fun _Series-ptr _size -> _Series-ptr/null))

(define-reasoned (series-tail s n) #:who-variant series-tail/who
  (_fun _Series-ptr _size -> _Series-ptr/null))

(define-reasoned (series-slice s offset len) #:who-variant series-slice/who
  (_fun _Series-ptr _int64 _size -> _Series-ptr/null))

(define-reasoned (series-reverse s) #:who-variant series-reverse/who
  (_fun _Series-ptr -> _Series-ptr/null))

(define-reasoned (series-drop-nulls s) #:who-variant series-drop-nulls/who
  (_fun _Series-ptr -> _Series-ptr/null))

(define-reasoned (series-unique s) #:who-variant series-unique/who
  (_fun _Series-ptr -> _Series-ptr/null))

(define-compat series-sort/raw
  (_fun _Series-ptr _stdbool _stdbool -> _Series-ptr/null)
  #:c-id series_sort_with_options
  #:wrap (allocator series-drop))

(define (series-sort/who who s descending nulls-last)
  (call/foreign-error who
                      (lambda () (series-sort/raw s descending nulls-last))
                      "failed to sort the series"))

(define (series-sort s #:descending [descending #f] #:nulls-last [nulls-last #f])
  (series-sort/who 'series-sort s descending nulls-last))

(define-reasoned (series-std s [#:ddof ddof 1]) #:who-variant series-std/who
  #:ok? (compose1 (negate negative?) CompatOptF64-valid)
  #:result compat-opt-f64->datum
  (define-compat series-std/raw
    (_fun _Series-ptr _uint8 -> _CompatOptF64)
    #:c-id series_std_v2))

(define-reasoned (series-var s [#:ddof ddof 1]) #:who-variant series-var/who
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
  #:with c-id (format-id #'name "~a" (string-replace (symbol->string (syntax-e #'name)) "-" "_"))
  (begin
    (define-reasoned (name s v)
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
  (_fun _Series-ptr -> _Series-ptr/null))

(define-reasoned (series-is-not-null s)
  (_fun _Series-ptr -> _Series-ptr/null))

(define-series-series-op series-and series-and/who series-and/raw series_and)
(define-series-series-op series-or series-or/who series-or/raw series_or)
(define-series-series-op series-xor series-xor/who series-xor/raw series_xor)

(define-reasoned (series-not s) #:who-variant series-not/who
  (define-compat series-not/raw
    (_fun _Series-ptr -> _Series-ptr/null)
    #:c-id series_not
    #:wrap (allocator series-drop)))

(module+ internal
  (provide series-drop-nulls/who series-head/who series-n-unique/who series-reverse/who
           series-slice/who series-sort/who series-std/who series-tail/who series-unique/who
           series-var/who typed-reductions
           series-add-i32 series-add-i64 series-add-u32 series-add-u64
           series-div-i32 series-div-i64 series-div-u32 series-div-u64 series-eq-i32
           series-ge-i32 series-gt-i32 series-head series-le-i32 series-lt-i32 series-mod-i32
           series-mod-i64 series-mod-u32 series-mod-u64 series-mul-i32 series-mul-i64
           series-mul-u32 series-mul-u64 series-ne-i32 series-slice series-sort series-std
           series-sub-i32 series-sub-i64 series-sub-u32 series-sub-u64 series-tail series-var))
