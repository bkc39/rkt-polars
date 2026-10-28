#lang racket/base

;; Expr / LazyFrame DSL — Phase A1.
;;
;; Sits on top of polars/private/foreign for DataFrame/Series interop and
;; polars/private/expr-core for Expr/LazyFrame FFI plumbing.

(require ffi/unsafe
         ffi/unsafe/alloc
         (only-in racket/contract flat-contract-with-explanation raise-blame-error)
         (only-in racket/contract/base
                  [-> ->/c] ->* and/c any/c contract-name contract-out listof or/c)
         (only-in racket/list filter-not index-of)
         (only-in racket/match match match-define)
         (only-in polars/private/c-integer int32/c int64/c size/c uint32/c uint64/c uint8/c)
         polars/private/expr-core
         polars/private/expr-dt
         polars/private/expr-str
         (only-in polars/private/foreign
                  allocator/or-fail
                  call/foreign-error
                  call/polars-reason
                  _DataFrame-ptr
                  _DataFrame-ptr/null
                  DataFrame-ptr?
                  _Series-ptr
                  Series-ptr?
                  _rsstr
                  _rsstr-list
                  polars-null?
                  series-new-i64 series-new-u64 series-new-f64 series-new-str series-new-bool
                  series-new-null
                  dataframe-drop
                  frame-sort/c provide-row-windows sort-flags
                  _c-string _CompatDType ->compat-dtype check-time-zone-name enum-dtype?
                  time-unit-symbol->code zoned-datetime-dtype?)
         (only-in polars/private/join-options
                  frame-join/c join-keys join-symbol->code)
         (only-in polars/private/resource _str-list with-release)
         (only-in polars/private/series series-new-temporal)
         (only-in polars/private/temporal
                  temporal-value-dtype temporal-values-dtype zone-conflict)
         syntax/parse/define
         (for-syntax racket/base racket/syntax))

(provide _Expr-ptr Expr-ptr?
         _LazyFrame-ptr LazyFrame-ptr?
         expr-drop lazyframe-drop
         expr-col expr-lit-i32 expr-lit-i64 expr-lit-u64 expr-lit-f64 expr-lit-bool expr-lit-str
         expr-alias
         expr->string
         lit lit/who col ->expr ->expr/who ->key-expr
         expr-all expr-exclude expr-dtype-col multi-column-expr? dtype-spec?
         expr-add expr-sub expr-mul expr-div expr-mod
         expr-gt expr-lt expr-ge expr-le expr-eq expr-ne
         expr-and expr-or expr-xor
         expr-str-contains expr-str-starts-with expr-str-ends-with
         expr-str-to-lowercase expr-str-to-uppercase
         expr-str-replace expr-str-replace-all expr-str-extract
         expr-str-strip-chars expr-str-strip-chars-start expr-str-strip-chars-end
         expr-str-strip-prefix expr-str-strip-suffix
         expr-str-len-bytes expr-str-len-chars
         expr-str-slice expr-str-head expr-str-tail
         expr-str-find expr-str-find-literal expr-str-count-matches
         expr-str->date expr-str->datetime expr-str->time
         expr-dt-year expr-dt-month expr-dt-day
         expr-dt-hour expr-dt-minute expr-dt-second
         expr-dt-iso-year expr-dt-quarter expr-dt-week
         expr-dt-weekday expr-dt-ordinal-day expr-dt-is-leap-year
         expr-dt-date expr-dt-time
         expr-dt-millisecond expr-dt-microsecond expr-dt-nanosecond
         expr-dt-timestamp expr-dt-strftime expr-dt-truncate
         expr-not expr-neg expr-name-keep expr-is-null expr-is-not-null
         expr-drop-nulls expr-drop-nans
         expr-is-nan expr-is-not-nan expr-is-finite expr-is-infinite
         expr-fill-null expr-fill-nan
         expr-abs expr-sign expr-floor expr-ceil expr-sqrt expr-exp expr-log1p
         expr-log expr-pow expr-clip
         expr-lit-series expr-is-between
         expr-is-unique expr-is-duplicated
         expr-is-first-distinct expr-is-last-distinct
         expr-cum-sum expr-cum-prod expr-cum-min expr-cum-max expr-cum-count
         expr-reverse expr-filter
         index-list/c membership-list/c
         expr-sum expr-mean expr-min expr-max
         expr-count expr-n-unique expr-first expr-last expr-median
         expr-over
         expr-when
         null-behavior/c rank-method/c
         dataframe-lazy
         lazyframe-with-columns lazyframe-collect lazyframe-collect/raw
         lazyframe-filter lazyframe-select
         lazyframe-group-by-agg
         lazyframe-unique lazyframe-drop-nulls
         (contract-out
          [expr-forward-fill (->* (Expr-ptr?) (#:limit (or/c #f uint32/c)) Expr-ptr?)]
          [expr-backward-fill (->* (Expr-ptr?) (#:limit (or/c #f uint32/c)) Expr-ptr?)]
          [expr-round (->* (Expr-ptr?) (#:decimals uint32/c) Expr-ptr?)]
          [expr-shift (->* (Expr-ptr?) (#:n int64/c #:fill-value any/c) Expr-ptr?)]
          [expr-diff (->* (Expr-ptr?) (#:n int64/c #:null-behavior null-behavior/c) Expr-ptr?)]
          [expr-rank (->* (Expr-ptr?)
                          (#:method rank-method/c #:descending boolean? #:seed (or/c #f uint64/c))
                          Expr-ptr?)]
          [expr-head (->* (Expr-ptr?) (#:n (or/c #f size/c)) Expr-ptr?)]
          [expr-tail (->* (Expr-ptr?) (#:n (or/c #f size/c)) Expr-ptr?)]
          [expr-slice (->/c Expr-ptr? int64/c size/c Expr-ptr?)]
          [expr-is-in (->* (Expr-ptr? (and/c (or/c Expr-ptr? Series-ptr? list?) membership-list/c))
                           (#:who symbol?)
                           Expr-ptr?)]
          [expr-gather (->/c Expr-ptr? (or/c Expr-ptr? Series-ptr? index-list/c) Expr-ptr?)]
          [expr-std (->* (Expr-ptr?) (#:ddof uint8/c) Expr-ptr?)]
          [expr-var (->* (Expr-ptr?) (#:ddof uint8/c) Expr-ptr?)]
          [lazyframe-explain (explain/c LazyFrame-ptr?)]
          [lazyframe-join (frame-join/c LazyFrame-ptr? (lambda (_) LazyFrame-ptr?)
                                        (lambda (_) LazyFrame-ptr?) 'lazyframe-join/c)])
         expr-cast expr-cast-to
         dataframe-with-columns dataframe-select-exprs dataframe-filter-expr
         dataframe-group-by-agg
         expr-meta-output-name expr-meta-output-name/raw expr-meta-root-names expr-meta-eq?
         (contract-out
          [expr-sort (->* (Expr-ptr?) (#:descending boolean? #:nulls-last boolean?) Expr-ptr?)]
          [expr-sort-by (sort-by/c Expr-ptr? 'expr-sort-by/c)]
          [lazyframe-sort (frame-sort/c LazyFrame-ptr? 'lazyframe-sort/c)]
          [dataframe-sort-exprs (frame-sort/c DataFrame-ptr? 'dataframe-sort-exprs/c)]))

(define-compat expr-meta-output-name/raw
  (_fun _Expr-ptr -> _rsstr)
  #:c-id expr_meta_output_name_v2)

(define (expr-meta-output-name e)
  (or (expr-meta-output-name/raw e)
      (error 'expr-meta-output-name
             "cannot determine the output name of ~a" e)))

(define-compat expr-meta-root-names
  (_fun _Expr-ptr -> _rsstr-list)
  #:c-id expr_meta_root_names)

(define-compat expr-meta-eq/raw
  (_fun _Expr-ptr _Expr-ptr -> _uint8)
  #:c-id expr_meta_eq)

(define (expr-meta-eq? a b) (= 1 (expr-meta-eq/raw a b)))

(define-compat dataframe-lazy
  (_fun _DataFrame-ptr -> _LazyFrame-ptr)
  #:wrap (allocator lazyframe-drop))

(define lazyframe-explain (lazyframe-explainer 'lazyframe-explain))

(define-compat lazyframe-with-columns/c
  (_fun _LazyFrame-ptr
        (exprs : (_list i _Expr-ptr))
        (_size = (length exprs))
        -> _LazyFrame-ptr)
  #:c-id lazyframe_with_columns
  #:wrap (allocator lazyframe-drop))

(define (lazyframe-with-columns lf exprs)
  (lazyframe-with-columns/c lf exprs))

(define-compat lazyframe-collect/raw
  (_fun _LazyFrame-ptr -> _DataFrame-ptr/null)
  #:c-id lazyframe_collect
  #:wrap (allocator dataframe-drop))

(define (lazyframe-collect/who who lf)
  (call/polars-reason who (lambda () (lazyframe-collect/raw lf))))

(define (lazyframe-collect lf)
  (lazyframe-collect/who 'lazyframe-collect lf))

(define (call-with-plan df extend proc)
  (with-release ([source (dataframe-lazy df) lazyframe-drop]
                 [plan (extend source) lazyframe-drop])
    (proc plan)))

(define (collect-plan/who who df extend)
  (call-with-plan df extend (lambda (plan) (lazyframe-collect/who who plan))))

;; --- Phase A2: Expr operations ---

(define-syntax-parse-rule (define-expr-binop name:id c-id:id)
  #:with raw (format-id #'name "~a/raw" #'name)
  (begin
    (define-compat raw
      (_fun _Expr-ptr _Expr-ptr -> _Expr-ptr)
      #:c-id c-id
      #:wrap (allocator expr-drop))
    (define (name a b) (raw (->expr/who 'name a) (->expr/who 'name b)))))

(define-expr-binop expr-add expr_add)
(define-expr-binop expr-sub expr_sub)
(define-expr-binop expr-mul expr_mul)
(define-expr-binop expr-div expr_div)
(define-expr-binop expr-mod expr_mod)
(define-expr-binop expr-gt expr_gt)
(define-expr-binop expr-lt expr_lt)
(define-expr-binop expr-ge expr_ge)
(define-expr-binop expr-le expr_le)
(define-expr-binop expr-eq expr_eq)
(define-expr-binop expr-ne expr_ne)
(define-expr-binop expr-and expr_and)
(define-expr-binop expr-or expr_or)
(define-expr-binop expr-xor expr_xor)

(define-compat expr-not
  (_fun _Expr-ptr -> _Expr-ptr)
  #:wrap (allocator expr-drop))

(define-compat expr-neg
  (_fun _Expr-ptr -> _Expr-ptr)
  #:wrap (allocator expr-drop))

(define-compat expr-name-keep
  (_fun _Expr-ptr -> _Expr-ptr)
  #:c-id expr_name_keep
  #:wrap (allocator expr-drop))

(define-compat expr-is-null
  (_fun _Expr-ptr -> _Expr-ptr)
  #:wrap (allocator expr-drop))

(define-compat expr-is-not-null
  (_fun _Expr-ptr -> _Expr-ptr)
  #:wrap (allocator expr-drop))

;; --- Null / NaN handling ---

(define-compat expr-drop-nulls
  (_fun _Expr-ptr -> _Expr-ptr)
  #:wrap (allocator expr-drop))

(define-compat expr-drop-nans
  (_fun _Expr-ptr -> _Expr-ptr)
  #:wrap (allocator expr-drop))

(define-compat expr-is-nan
  (_fun _Expr-ptr -> _Expr-ptr)
  #:wrap (allocator expr-drop))

(define-compat expr-is-not-nan
  (_fun _Expr-ptr -> _Expr-ptr)
  #:wrap (allocator expr-drop))

(define-compat expr-is-finite
  (_fun _Expr-ptr -> _Expr-ptr)
  #:wrap (allocator expr-drop))

(define-compat expr-is-infinite
  (_fun _Expr-ptr -> _Expr-ptr)
  #:wrap (allocator expr-drop))

(define-compat expr-fill-null/raw
  (_fun _Expr-ptr _Expr-ptr -> _Expr-ptr)
  #:c-id expr_fill_null
  #:wrap (allocator expr-drop))

(define (expr-fill-null e value) (expr-fill-null/raw e (->expr value)))

(define-compat expr-fill-nan/raw
  (_fun _Expr-ptr _Expr-ptr -> _Expr-ptr)
  #:c-id expr_fill_nan
  #:wrap (allocator expr-drop))

(define (expr-fill-nan e value) (expr-fill-nan/raw e (->expr value)))

(define-compat expr-forward-fill/raw
  (_fun _Expr-ptr _uint8 _uint32 -> _Expr-ptr)
  #:c-id expr_forward_fill
  #:wrap (allocator expr-drop))

(define-compat expr-backward-fill/raw
  (_fun _Expr-ptr _uint8 _uint32 -> _Expr-ptr)
  #:c-id expr_backward_fill
  #:wrap (allocator expr-drop))

(define (expr-forward-fill e #:limit [limit #f])
  (expr-forward-fill/raw e (if limit 1 0) (or limit 0)))

(define (expr-backward-fill e #:limit [limit #f])
  (expr-backward-fill/raw e (if limit 1 0) (or limit 0)))

;; --- Element-wise math ---

(define-compat expr-abs (_fun _Expr-ptr -> _Expr-ptr) #:wrap (allocator expr-drop))
(define-compat expr-sign (_fun _Expr-ptr -> _Expr-ptr) #:wrap (allocator expr-drop))
(define-compat expr-floor (_fun _Expr-ptr -> _Expr-ptr) #:wrap (allocator expr-drop))
(define-compat expr-ceil (_fun _Expr-ptr -> _Expr-ptr) #:wrap (allocator expr-drop))
(define-compat expr-sqrt (_fun _Expr-ptr -> _Expr-ptr) #:wrap (allocator expr-drop))
(define-compat expr-exp (_fun _Expr-ptr -> _Expr-ptr) #:wrap (allocator expr-drop))
(define-compat expr-log1p (_fun _Expr-ptr -> _Expr-ptr) #:wrap (allocator expr-drop))

(define-compat expr-round/raw
  (_fun _Expr-ptr _uint32 -> _Expr-ptr)
  #:c-id expr_round
  #:wrap (allocator expr-drop))

(define (expr-round e #:decimals [decimals 0])
  (expr-round/raw e decimals))

(define-compat expr-log/raw
  (_fun _Expr-ptr _double -> _Expr-ptr)
  #:c-id expr_log
  #:wrap (allocator expr-drop))

(define (expr-log e #:base [base (exp 1)])
  (expr-log/raw e (exact->inexact base)))

(define-compat expr-pow/raw
  (_fun _Expr-ptr _Expr-ptr -> _Expr-ptr)
  #:c-id expr_pow
  #:wrap (allocator expr-drop))

(define (expr-pow e exponent) (expr-pow/raw e (->expr exponent)))

(define-compat expr-clip/raw
  (_fun _Expr-ptr _uint8 _Expr-ptr/null _uint8 _Expr-ptr/null -> _Expr-ptr)
  #:c-id expr_clip
  #:wrap (allocator expr-drop))

(define (expr-clip e #:lower [lower #f] #:upper [upper #f])
  (expr-clip/raw e
                 (if lower 1 0) (and lower (->expr lower))
                 (if upper 1 0) (and upper (->expr upper))))

;; --- Membership / distinct predicates ---

(define-compat expr-lit-series
  (_fun _Series-ptr -> _Expr-ptr)
  #:wrap (allocator expr-drop))

(define-compat expr-is-unique
  (_fun _Expr-ptr -> _Expr-ptr) #:wrap (allocator expr-drop))
(define-compat expr-is-duplicated
  (_fun _Expr-ptr -> _Expr-ptr) #:wrap (allocator expr-drop))
(define-compat expr-is-first-distinct
  (_fun _Expr-ptr -> _Expr-ptr) #:wrap (allocator expr-drop))
(define-compat expr-is-last-distinct
  (_fun _Expr-ptr -> _Expr-ptr) #:wrap (allocator expr-drop))

(define-compat expr-is-in/raw
  (_fun _Expr-ptr _Expr-ptr -> _Expr-ptr)
  #:c-id expr_is_in
  #:wrap (allocator expr-drop))

;; The right-hand side may be an Expr, a Series, or a Racket list of
;; homogeneous scalars (ints / reals / strings / symbols / booleans / gregor values).
(define (->membership-expr who rhs)
  (cond
    [(Expr-ptr? rhs) rhs]
    [(Series-ptr? rhs) (expr-lit-series rhs)]
    [else
     (define vals (filter-not polars-null? rhs))
     (define s
       (cond
         [(null? vals) (series-new-null "" (length rhs))]
         [(andmap int64/c vals) (series-new-i64 "" rhs)]
         [(andmap uint64/c vals) (series-new-u64 "" rhs)]
         [(andmap real? vals) (series-new-f64 "" (map-non-null exact->inexact rhs))]
         [(andmap string? vals) (series-new-str "" rhs)]
         [(andmap symbol? vals) (series-new-str "" (map-non-null symbol->string rhs))]
         [(andmap boolean? vals) (series-new-bool "" rhs)]
         [(temporal-values-dtype vals)
          => (lambda (dtype)
               (check-one-zone who vals)
               (series-new-temporal who "" rhs dtype))]
         [else (error who "is-in list must be homogeneous ints/reals/strings/symbols/booleans/gregor values, got ~v" rhs)]))
     (expr-lit-series s)]))

(define (integer-and-float vals)
  (for/fold ([integer #f] [float #f] #:result (and integer float (list integer float)))
            ([v (in-list vals)])
    (values (or integer (and (exact-integer? v) v))
            (or float (and (real? v) (not (exact-integer? v)) v)))))

(define membership-integers/c (or/c (listof int64/c) (listof uint64/c)))

(define (membership-explanation v)
  (define vals (if (list? v) (filter-not polars-null? v) '()))
  (match (integer-and-float vals)
    [(list integer float)
     (lambda (blame)
       (raise-blame-error blame v
                          (string-append "the list mixes integers and floats, which have no"
                                         " common dtype\n  integer: ~e\n  float: ~e\n  given: ~e")
                          integer float v))]
    [_ #:when (and (andmap exact-integer? vals)
                   (not (or (andmap int64/c vals) (andmap uint64/c vals))))
     (lambda (blame)
       (raise-blame-error blame v '(expected: "~s" given: "~e")
                          (contract-name membership-integers/c) v))]
    [_ #t]))

(define membership-list/c
  (flat-contract-with-explanation membership-explanation #:name 'membership-list/c))

(define index-list/c (listof (or/c int64/c polars-null?)))

(define (map-non-null f xs)
  (for/list ([x (in-list xs)])
    (if (polars-null? x) x (f x))))

(define (check-one-zone who vals)
  (define conflict (zone-conflict vals))
  (when conflict
    (raise-arguments-error who "the values have no common dtype: their time zones differ"
                           "dtype" (temporal-value-dtype (car conflict))
                           "other dtype" (temporal-value-dtype (cadr conflict)))))

(define (expr-is-in e rhs #:who [who 'expr-is-in])
  (expr-is-in/raw e (->membership-expr who rhs)))

(define-compat expr-is-between/raw
  (_fun _Expr-ptr _Expr-ptr _Expr-ptr _uint8 -> _Expr-ptr)
  #:c-id expr_is_between
  #:wrap (allocator expr-drop))

(define (closed->byte who closed)
  (case closed
    [(both) 0] [(left) 1] [(right) 2] [(none) 3]
    [else (error who "closed must be one of 'both 'left 'right 'none, got ~v" closed)]))

(define (expr-is-between e lower upper #:closed [closed 'both])
  (expr-is-between/raw e (->expr lower) (->expr upper)
                       (closed->byte 'expr-is-between closed)))

;; --- Cumulative + shift / diff ---

(define-syntax-parse-rule (define-cum name:id raw:id c-id:id)
  (begin
    (define-compat raw
      (_fun _Expr-ptr _uint8 -> _Expr-ptr)
      #:c-id c-id
      #:wrap (allocator expr-drop))
    (define (name e #:reverse [reverse #f])
      (raw e (if reverse 1 0)))))

(define-cum expr-cum-sum   expr-cum-sum/raw   expr_cum_sum)
(define-cum expr-cum-prod  expr-cum-prod/raw  expr_cum_prod)
(define-cum expr-cum-min   expr-cum-min/raw   expr_cum_min)
(define-cum expr-cum-max   expr-cum-max/raw   expr_cum_max)
(define-cum expr-cum-count expr-cum-count/raw expr_cum_count)

(define-compat expr-shift/raw
  (_fun _Expr-ptr _int64 -> _Expr-ptr)
  #:c-id expr_shift
  #:wrap (allocator expr-drop))

(define-compat expr-shift-and-fill/raw
  (_fun _Expr-ptr _int64 _Expr-ptr -> _Expr-ptr)
  #:c-id expr_shift_and_fill
  #:wrap (allocator expr-drop))

(define (expr-shift e #:n [n 1] #:fill-value [fill-value #f])
  (if fill-value
      (expr-shift-and-fill/raw e n (->expr fill-value))
      (expr-shift/raw e n)))

(define-compat expr-diff/raw
  (_fun _Expr-ptr _int64 _uint8 -> _Expr-ptr)
  #:c-id expr_diff
  #:wrap (allocator expr-drop))

(define null-behavior/c (or/c 'ignore 'drop))

(define (expr-diff e #:n [n 1] #:null-behavior [null-behavior 'ignore])
  (expr-diff/raw e n (if (eq? null-behavior 'drop) 1 0)))

;; --- Sorting / selection helpers ---

(define-compat expr-reverse
  (_fun _Expr-ptr -> _Expr-ptr) #:wrap (allocator expr-drop))

(define-compat expr-filter/raw
  (_fun _Expr-ptr _Expr-ptr -> _Expr-ptr)
  #:c-id expr_filter
  #:wrap (allocator expr-drop))

(define (expr-filter e predicate) (expr-filter/raw e (->expr predicate)))

(define-compat expr-gather/raw
  (_fun _Expr-ptr _Expr-ptr -> _Expr-ptr)
  #:c-id expr_gather
  #:wrap (allocator expr-drop))

(define (expr-gather e indices)
  (expr-gather/raw e (->index-expr indices)))

(define (->index-expr indices)
  (cond
    [(Expr-ptr? indices) indices]
    [(Series-ptr? indices) (expr-lit-series indices)]
    [else (expr-lit-series (series-new-i64 "" indices))]))

(define-compat expr-sort-by/raw
  (_fun _Expr-ptr
        (by : (_list i _Expr-ptr))
        (descending : (_list i _stdbool))
        (nulls-last : (_list i _stdbool))
        (_size = (length by))
        (maintain-order : _stdbool)
        -> _Expr-ptr/null)
  #:c-id expr_sort_by_with_options
  #:wrap (allocator expr-drop))

(define (expr-sort-by e #:by by
                      #:descending [descending #f]
                      #:nulls-last [nulls-last #f]
                      #:maintain-order [maintain-order #f])
  (define by-list (if (list? by) by (list by)))
  (or (expr-sort-by/raw e (map ->key-expr by-list)
                        (sort-flags 'expr-sort-by "#:descending" descending by-list)
                        (sort-flags 'expr-sort-by "#:nulls-last" nulls-last by-list)
                        maintain-order)
      (error 'expr-sort-by "failed to build the sort_by expression")))

(define-compat expr-rank/raw
  (_fun _Expr-ptr _uint8 _uint8 _uint8 _uint64 -> _Expr-ptr)
  #:c-id expr_rank
  #:wrap (allocator expr-drop))

(define rank-methods '(average min max dense ordinal))

(define rank-method/c (apply or/c rank-methods))

(define (expr-rank e #:method [method 'average] #:descending [descending #f] #:seed [seed #f])
  (expr-rank/raw e
                 (index-of rank-methods method)
                 (if descending 1 0)
                 (if seed 1 0)
                 (or seed 0)))

(define-compat expr-head/raw
  (_fun _Expr-ptr _uint8 _size -> _Expr-ptr)
  #:c-id expr_head
  #:wrap (allocator expr-drop))

(define-compat expr-tail/raw
  (_fun _Expr-ptr _uint8 _size -> _Expr-ptr)
  #:c-id expr_tail
  #:wrap (allocator expr-drop))

(define (expr-head e #:n [n 10])
  (expr-head/raw e (if n 1 0) (or n 0)))

(define (expr-tail e #:n [n 10])
  (expr-tail/raw e (if n 1 0) (or n 0)))

(define-compat expr-slice
  (_fun _Expr-ptr _int64 _size -> _Expr-ptr)
  #:c-id expr_slice_v2
  #:wrap (allocator expr-drop))

;; --- Phase A4: aggregations (collapse a column to one value) ---

(define-compat expr-sum
  (_fun _Expr-ptr -> _Expr-ptr)
  #:wrap (allocator expr-drop))

(define-compat expr-mean
  (_fun _Expr-ptr -> _Expr-ptr)
  #:wrap (allocator expr-drop))

(define-compat expr-min
  (_fun _Expr-ptr -> _Expr-ptr)
  #:wrap (allocator expr-drop))

(define-compat expr-max
  (_fun _Expr-ptr -> _Expr-ptr)
  #:wrap (allocator expr-drop))

(define-compat expr-count
  (_fun _Expr-ptr -> _Expr-ptr)
  #:wrap (allocator expr-drop))

(define-compat expr-n-unique
  (_fun _Expr-ptr -> _Expr-ptr)
  #:wrap (allocator expr-drop))

(define-compat expr-first
  (_fun _Expr-ptr -> _Expr-ptr)
  #:wrap (allocator expr-drop))

(define-compat expr-last
  (_fun _Expr-ptr -> _Expr-ptr)
  #:wrap (allocator expr-drop))

(define-compat expr-median
  (_fun _Expr-ptr -> _Expr-ptr)
  #:wrap (allocator expr-drop))

(define-compat expr-std/raw
  (_fun _Expr-ptr _uint8 -> _Expr-ptr)
  #:c-id expr_std
  #:wrap (allocator expr-drop))

(define-compat expr-var/raw
  (_fun _Expr-ptr _uint8 -> _Expr-ptr)
  #:c-id expr_var
  #:wrap (allocator expr-drop))

(define (expr-std e #:ddof [ddof 1]) (expr-std/raw e ddof))
(define (expr-var e #:ddof [ddof 1]) (expr-var/raw e ddof))

;; --- Phase A5: window (over) + per-Expr sort ---

(define-compat expr-over/c
  (_fun _Expr-ptr
        (parts : (_list i _Expr-ptr))
        (_size = (length parts))
        -> _Expr-ptr)
  #:c-id expr_over
  #:wrap (allocator expr-drop))

;; expr-over takes either string keys or already-built Expr-ptrs.
(define (expr-over e parts)
  (expr-over/c e (map ->key-expr parts)))

(define-compat expr-sort/raw
  (_fun _Expr-ptr _stdbool _stdbool -> _Expr-ptr/null)
  #:c-id expr_sort_with_options
  #:wrap (allocator expr-drop))

(define (expr-sort e #:descending [descending #f] #:nulls-last [nulls-last #f])
  (or (expr-sort/raw e descending nulls-last)
      (error 'expr-sort "failed to build the sort expression")))

;; --- Conditional: when / then / otherwise ---

(define-compat expr-when-then/c
  (_fun (conds : (_list i _Expr-ptr))
        (vals : (_list i _Expr-ptr))
        (_size = (length conds))
        (otherwise : _Expr-ptr)
        -> _Expr-ptr)
  #:c-id expr_when_then
  #:wrap (allocator expr-drop))

;; (expr-when (list (list pred value) ...) #:otherwise default)
;; Builds the chained when().then()...otherwise() expression.  Both
;; predicates and values are lifted with ->expr, so Racket scalars work.
(define (expr-when clauses #:otherwise otherwise)
  (when (null? clauses)
    (error 'expr-when "requires at least one [pred value] clause"))
  (for ([c (in-list clauses)])
    (unless (and (list? c) (= 2 (length c)))
      (error 'expr-when "each clause must be (list pred value); got ~v" c)))
  (expr-when-then/c (for/list ([c (in-list clauses)]) (->expr (car c)))
                    (for/list ([c (in-list clauses)]) (->expr (cadr c)))
                    (->expr otherwise)))

;; --- Phase A3: lazy frame integration ---

(define-compat lazyframe-filter
  (_fun _LazyFrame-ptr _Expr-ptr -> _LazyFrame-ptr)
  #:wrap (allocator lazyframe-drop))

(define-compat lazyframe-select/c
  (_fun _LazyFrame-ptr
        (exprs : (_list i _Expr-ptr))
        (_size = (length exprs))
        -> _LazyFrame-ptr)
  #:c-id lazyframe_select
  #:wrap (allocator lazyframe-drop))

(define (lazyframe-select lf exprs)
  (lazyframe-select/c lf exprs))

;; Eager-feeling conveniences: take a DataFrame, return a DataFrame.
(define (dataframe-with-columns df exprs)
  (collect-plan/who 'dataframe-with-columns df (lambda (lf) (lazyframe-with-columns lf exprs))))

(define (dataframe-select-exprs df exprs)
  (collect-plan/who 'dataframe-select-exprs df (lambda (lf) (lazyframe-select lf exprs))))

(define (dataframe-filter-expr df predicate)
  (collect-plan/who 'dataframe-filter-expr df (lambda (lf) (lazyframe-filter lf predicate))))

;; --- Phase A4: lazy group-by ---
;;
;; LazyGroupBy::agg consumes self on the Rust side, which doesn't fit
;; Racket's allocator/deallocator round-tripping; fold group_by + agg
;; into one FFI call so the intermediate state never crosses the boundary.

(define-compat lazyframe-group-by-agg/c
  (_fun _LazyFrame-ptr
        (keys : (_list i _Expr-ptr))
        (_size = (length keys))
        (aggs : (_list i _Expr-ptr))
        (_size = (length aggs))
        -> _LazyFrame-ptr)
  #:c-id lazyframe_group_by_agg
  #:wrap (allocator lazyframe-drop))

;; Lifts strings to (col s); already-Expr values pass through.
(define (->key-expr v)
  (cond
    [(Expr-ptr? v) v]
    [(string? v) (col v)]
    [else (error '->key-expr "expected string or Expr-ptr, got ~v" v)]))

(define (lazyframe-group-by-agg lf keys aggs)
  (lazyframe-group-by-agg/c lf (map ->key-expr keys) aggs))

(define (dataframe-group-by-agg df keys aggs)
  (collect-plan/who 'dataframe-group-by-agg df (lambda (lf) (lazyframe-group-by-agg lf keys aggs))))

;; --- Phase A6: more LazyFrame ops (sort / unique / drop_nulls) ---

(define-compat lazyframe-sort/raw
  (_fun _LazyFrame-ptr
        (names : _str-list)
        (descending : (_list i _stdbool))
        (nulls-last : (_list i _stdbool))
        (_size = (length names))
        (maintain-order : _stdbool)
        -> _LazyFrame-ptr/null)
  #:c-id lazyframe_sort_with_options_v2
  #:wrap (allocator lazyframe-drop))

(define (lazyframe-sort lf names
                        #:descending [descending #f]
                        #:nulls-last [nulls-last #f]
                        #:maintain-order [maintain-order #f])
  (or (lazyframe-sort/raw lf names
                          (sort-flags 'lazyframe-sort "#:descending" descending names)
                          (sort-flags 'lazyframe-sort "#:nulls-last" nulls-last names)
                          maintain-order)
      (error 'lazyframe-sort "failed to build the sort plan")))

(define-compat lazyframe-unique
  (_fun _LazyFrame-ptr -> _LazyFrame-ptr)
  #:wrap (allocator lazyframe-drop))

(define-compat lazyframe-drop-nulls
  (_fun _LazyFrame-ptr -> _LazyFrame-ptr)
  #:wrap (allocator lazyframe-drop))

(define (dataframe-sort-exprs df names
                              #:descending [descending #f]
                              #:nulls-last [nulls-last #f]
                              #:maintain-order [maintain-order #f])
  (collect-plan/who 'lazyframe-collect df
                    (lambda (lf)
                      (lazyframe-sort lf names
                                      #:descending descending
                                      #:nulls-last nulls-last
                                      #:maintain-order maintain-order))))

;; --- Phase A7: lazy head / tail / slice ---
;;
;; Mirror eager dataframe-{head,tail,slice} so a lazy plan can be sliced
;; without an intermediate .collect().

(define-compat lazyframe-head
  (_fun _LazyFrame-ptr _size -> _LazyFrame-ptr)
  #:wrap (allocator lazyframe-drop))

(define-compat lazyframe-tail
  (_fun _LazyFrame-ptr _size -> _LazyFrame-ptr)
  #:wrap (allocator lazyframe-drop))

(define-compat lazyframe-slice
  (_fun _LazyFrame-ptr _int64 _size -> _LazyFrame-ptr)
  #:wrap (allocator lazyframe-drop))

(provide-row-windows LazyFrame-ptr? lazyframe-head lazyframe-tail lazyframe-slice)

;; --- Phase A8: lazy join ---

(define-compat lazyframe-join/c
  (_fun _LazyFrame-ptr _LazyFrame-ptr _str-list _str-list _int32 -> _LazyFrame-ptr/null)
  #:c-id lazyframe_join_v2
  #:wrap (allocator lazyframe-drop))

(define (lazyframe-join left right
                        #:on [on #f]
                        #:left-on [left-on #f]
                        #:right-on [right-on #f]
                        #:how [how 'inner])
  (define-values (lon ron) (join-keys how on left-on right-on))
  (call/foreign-error 'lazyframe-join
                      (lambda () (lazyframe-join/c left right lon ron (join-symbol->code how)))))

;; --- Phase A9: expr cast ---

(define-compat expr-cast/c
  (_fun _Expr-ptr _CompatDType -> _Expr-ptr)
  #:c-id expr_cast
  #:wrap (allocator expr-drop))

(define-compat expr-cast-enum/raw
  (_fun _Expr-ptr _str-list -> _Expr-ptr/null)
  #:c-id expr_cast_enum_v2
  #:wrap (allocator expr-drop))

(define-compat expr-cast-datetime-tz/raw
  (_fun _Expr-ptr _int32 _c-string -> _Expr-ptr/null)
  #:c-id expr_cast_datetime_tz
  #:wrap (allocator expr-drop))

(define (expr-cast e dtype)
  (expr-cast-to 'expr-cast e dtype))

(define (expr-cast-to who e dtype)
  (cond
    [(enum-dtype? dtype)
     (call/foreign-error who
                         (lambda () (expr-cast-enum/raw e (map symbol->string (cdr dtype))))
                         "cannot convert to ~v" dtype)]
    [(zoned-datetime-dtype? dtype)
     (match-define (list _ unit zone) dtype)
     (check-time-zone-name who zone)
     (call/foreign-error who
                         (lambda ()
                           (expr-cast-datetime-tz/raw e (time-unit-symbol->code unit) zone))
                         "cannot convert to ~v" dtype)]
    [else (expr-cast/c e (->compat-dtype dtype))]))

(module+ internal
  (provide call-with-plan collect-plan/who expr-cast-datetime-tz/raw expr-diff expr-forward-fill
           expr-head expr-rank expr-round expr-shift expr-slice expr-sort expr-sort-by expr-std
           expr-tail expr-var
           lazyframe-collect/who lazyframe-explain lazyframe-head lazyframe-join lazyframe-slice
           lazyframe-sort lazyframe-tail rank-methods))
