#lang racket/base

;; High-level, "rackety" generic API layered over the monomorphic Series /
;; DataFrame bindings in polars/private/foreign.
;;
;; A series is exposed as a wrapper struct (the `series` predicate is `series?`)
;; rather than the raw FFI pointer.  The struct carries `prop:cpointer`, so a
;; wrapped series still marshals transparently as a `_Series-ptr` through every
;; existing binding (series-dtype, series-sum-i32, dataframe-new, …); we only
;; pay for the wrapper at the boundary.  It also carries `prop:custom-write`, so
;; a series prints in the REPL the way Polars prints it.  The underlying pointer
;; is deliberately not part of the public series API.
;;
;; The dataframe is exposed the same way: a `dataframe` wrapper struct
;; (`dataframe?`) with prop:cpointer + a Polars-table prop:custom-write, built by
;; the smart `dataframe` constructor.
;;
;; Dispatch uses small, purpose-named racket/generic interfaces:
;;   gen:describable    — (describe x)        series, dataframe
;;   gen:has-ref        — (ref x [key] #:columns ...)  series, dataframe
;;   gen:sized          — (len x)             series (#elements), dataframe (height)
;;   gen:has-shape      — (shape x)           series (n), dataframe (rows cols)
;;   gen:has-dtype      — (dtype x)           series
;;   gen:has-null-count — (null-count x)      series
;; Both wrappers implement the interfaces they have a capability for via
;; #:methods.  Dataframe-only metadata (width, height, column-name(s)) are plain
;; guarded functions.
;;
;; Naming convention: a trailing `!` marks an operation that mutates its
;; argument in place (rename!); the un-suffixed form returns a fresh value
;; (rename, via clone).
;;
;; dtype promotion lattice
;; -----------------------
;; series-dtype returns canonical symbols (int8 int16 int32 int64, uint8 ..
;; uint64, float32 float64, boolean, string, date, time, (datetime ..)).
;; Reductions follow a simple, documented rule:
;;   * sum / min / max  preserve the input dtype.
;;   * mean             always returns float64 (the underlying series-mean-*
;;                      bindings compute in double precision regardless of the
;;                      input integer/float width), so (mean ints) is a flonum.
;; The widening order from narrow to wide is:
;;   int8 < int16 < int32 < int64        (signed)
;;   uint8 < uint16 < uint32 < uint64     (unsigned)
;;   any integer < float32 < float64      (to floating point, used by mean)
;; Casts between dtypes are performed with series-cast.

(require racket/match
         racket/generic
         (except-in racket/list first last)
         racket/string
         (only-in ffi/unsafe prop:cpointer)
         (prefix-in base: racket/base)
         (only-in gregor datetime? date? ~t)
         polars/private/foreign
         polars/private/expr
         polars/private/series)

(module+ test
  (require rackunit gregor (only-in threading ~>)))

(provide series series? series->string
         dataframe dataframe?
         describe ref
         len shape shape/values dtype null-count
         width height column-name column-names
         gen:describable describable?
         gen:has-ref has-ref?
         gen:sized sized?
         gen:has-shape has-shape?
         gen:has-dtype has-dtype?
         gen:has-null-count has-null-count?
         sum mean min max
         count n-unique first last median std var alias
         > < >= <= = !=
         filter sort
         group-by agg grouped?
         rename rename! clone series-clone)

;; ---------------------------------------------------------------------------
;; generic interfaces
;;
;; Small, purpose-named capability interfaces (per the project's
;; "name capability generics, not catch-alls" rule).  Some are genuinely
;; cross-type (a series and a dataframe both have a `len` and a `shape`);
;; others have a single implementor today but are named so a future type
;; (e.g. an expression) can join without a rename.

;; sentinel for "argument not supplied" in ref's optional positional/keyword args
(define unset (gensym 'unset))

;; describe: print a one-line summary for a series, a shape + per-column dtype
;; summary for a dataframe.
(define-generics describable
  (describe describable))

;; ref: index a series (returns the element) or slice columns out of a
;; dataframe.  Data-first, so it threads.  See series-ref* / dataframe-ref*.
(define-generics has-ref
  (ref has-ref [key] #:columns [columns] #:rows [rows]))

;; len: number of elements (series) / number of rows (dataframe).
(define-generics sized
  (len sized))

;; shape: (values n) for a series, (values rows cols) for a dataframe.
(define-generics has-shape
  (shape has-shape))

;; dtype: a series' element dtype (canonical symbol).
(define-generics has-dtype
  (dtype has-dtype))

;; null-count: number of null entries in a series.
(define-generics has-null-count
  (null-count has-null-count))

;; ---------------------------------------------------------------------------
;; the series wrapper

(struct series-rec (ptr)
  #:reflection-name 'series
  ;; marshals as a _Series-ptr wherever the FFI expects one
  #:property prop:cpointer 0
  ;; prints like a Polars series
  #:property prop:custom-write
  (lambda (s port mode)
    (write-string (series->string s) port))
  #:methods gen:describable
  [(define (describe s) (describe-series s))]
  #:methods gen:has-ref
  [(define (ref s [key unset] #:columns [columns unset] #:rows [rows unset])
     (series-ref* s key columns rows))]
  #:methods gen:sized
  [(define (len s) (series-len s))]
  #:methods gen:has-shape
  [(define (shape s) (list (series-len s)))]
  #:methods gen:has-dtype
  [(define (dtype s) (series-dtype s))]
  #:methods gen:has-null-count
  [(define (null-count s) (series-null-count s))])

(define series? series-rec?)
(define (wrap-series ptr) (series-rec ptr))

;; ---------------------------------------------------------------------------
;; the dataframe wrapper
;;
;; Mirrors the series wrapper: carries prop:cpointer (so it still marshals as a
;; _DataFrame-ptr through every dataframe-* binding) and prop:custom-write (so a
;; dataframe prints in Polars' table format under display / ~a, with no need for
;; a separate display-dataframe).

(struct dataframe-rec (ptr)
  #:reflection-name 'dataframe
  #:property prop:cpointer 0
  #:property prop:custom-write
  (lambda (d port mode)
    (write-string (dataframe->string d) port))
  #:methods gen:describable
  [(define (describe d) (describe-dataframe d))]
  #:methods gen:has-ref
  [(define (ref d [key unset] #:columns [columns unset] #:rows [rows unset])
     (dataframe-ref* d key columns rows))]
  #:methods gen:sized
  [(define (len d) (dataframe-height d))]
  #:methods gen:has-shape
  [(define (shape d)
     (let-values ([(rows cols) (dataframe-shape d)])
       (list rows cols)))])

(define dataframe? dataframe-rec?)
(define (wrap-dataframe ptr) (dataframe-rec ptr))

;; smart constructor: wraps dataframe-new (which accepts series wrappers, since
;; they marshal as _Series-ptr).  Keep the raw dataframe-new as the low-level API.
(define (dataframe series-list)
  (wrap-dataframe (dataframe-new series-list)))

;; dataframe-only accessors.  Only one tabular type exists today, so these are
;; plain functions guarded on dataframe?; promote to a gen:tabular capability if
;; a second tabular type (e.g. a lazyframe wrapper) appears.
(define (guard-dataframe who d)
  (unless (dataframe? d)
    (error who "expected a dataframe, got ~v" d)))

(define (width d)  (guard-dataframe 'width d)  (dataframe-width d))
(define (height d) (guard-dataframe 'height d) (dataframe-height d))
(define (column-name d i)
  (guard-dataframe 'column-name d)
  (dataframe-column-name d i))
(define (column-names d)
  (guard-dataframe 'column-names d)
  (dataframe-column-names d))

;; shape returns the dimensions as a list (the list-based interface used in the
;; examples); shape/values is the multiple-values variant for callers that want
;; to bind the dimensions positionally with let-values / define-values.
(define (shape/values x) (apply values (shape x)))

;; ---------------------------------------------------------------------------
;; dtype aliases
;;
;; Accept both the short constructor spellings (i32, f64, str, bool) and the
;; canonical symbols returned by series-dtype (int32, float64, string,
;; boolean).  Maps everything to a canonical symbol.

(define dtype-aliases
  (hash 'i8 'int8    'int8 'int8
        'i16 'int16   'int16 'int16
        'i32 'int32   'int32 'int32
        'i64 'int64   'int64 'int64
        'u8 'uint8    'uint8 'uint8
        'u16 'uint16  'uint16 'uint16
        'u32 'uint32  'uint32 'uint32
        'u64 'uint64  'uint64 'uint64
        'f32 'float32 'float32 'float32
        'f64 'float64 'float64 'float64
        'bool 'boolean 'boolean 'boolean
        'str 'string   'string 'string
        'date 'date
        'time 'time
        'datetime 'datetime))

(define (normalize-dtype dt)
  (cond
    [(and (symbol? dt) (hash-ref dtype-aliases dt #f)) => values]
    [(and (pair? dt) (memq (car dt) '(datetime duration))) dt]
    [else (error 'series "unsupported dtype ~v" dt)]))

;; ---------------------------------------------------------------------------
;; series: keyword constructor with dtype inference

(define (infer-dtype elements)
  (define vals
    (for/list ([x (in-list (if (vector? elements)
                               (vector->list elements)
                               elements))]
               #:unless (polars-null? x))
      x))
  ;; Defaults mirror Polars' inference for a Python list: integers -> Int64,
  ;; reals -> Float64, strings -> String, booleans -> Boolean.
  (cond
    [(null? vals) 'int64]
    [(andmap boolean? vals) 'boolean]
    [(andmap exact-integer? vals) 'int64]
    [(andmap real? vals) 'float64]              ; mixed int/float -> float64
    [(andmap string? vals) 'string]
    [(andmap datetime? vals) 'datetime]
    [else (error 'series
                 "cannot infer a dtype from elements; pass #:dtype explicitly")]))

(define (dtype->constructor canonical vec?)
  (case canonical
    [(int8)    (if vec? series-new-i8/vec  series-new-i8)]
    [(int16)   (if vec? series-new-i16/vec series-new-i16)]
    [(int32)   (if vec? series-new-i32/vec series-new-i32)]
    [(int64)   (if vec? series-new-i64/vec series-new-i64)]
    [(uint8)   (if vec? series-new-u8/vec  series-new-u8)]
    [(uint16)  (if vec? series-new-u16/vec series-new-u16)]
    [(uint32)  (if vec? series-new-u32/vec series-new-u32)]
    [(uint64)  (if vec? series-new-u64/vec series-new-u64)]
    [(float32) (if vec? series-new-f32/vec series-new-f32)]
    [(float64) (if vec? series-new-f64/vec series-new-f64)]
    [(boolean) (if vec? series-new-bool/vec series-new-bool)]
    [(string)  (if vec? series-new-str/vec series-new-str)]
    [else
     (match canonical
       [(or 'datetime `(datetime . ,_))
        (if vec? series-new-datetime/vec series-new-datetime)]
       [_ (error 'series "no constructor for dtype ~v" canonical)])]))

;; The float constructors want flonums; accept exact reals too by coercing,
;; so (series '(1 2 3) #:dtype 'f64) does what the user means.
(define (coerce-elements canonical elements)
  (case canonical
    [(float32 float64)
     (define (->fl x) (if (and (not (polars-null? x)) (exact? x))
                          (exact->inexact x)
                          x))
     (if (vector? elements)
         (for/vector #:length (vector-length elements) ([x (in-vector elements)]) (->fl x))
         (map ->fl elements))]
    [else elements]))

;; (series elements #:name "n" #:dtype 'i32)
;; elements may be a list or a vector; nulls are polars-null.  Returns a series.
(define (series elements #:name [name ""] #:dtype [dtype #f])
  (define canonical (if dtype (normalize-dtype dtype) (infer-dtype elements)))
  (define ctor (dtype->constructor canonical (vector? elements)))
  (wrap-series (ctor name (coerce-elements canonical elements))))

;; ---------------------------------------------------------------------------
;; dtype-dispatched reductions

(define sum-table
  (hash 'int8 series-sum-i8 'int16 series-sum-i16
        'int32 series-sum-i32 'int64 series-sum-i64
        'uint8 series-sum-u8 'uint16 series-sum-u16
        'uint32 series-sum-u32 'uint64 series-sum-u64
        'float32 series-sum-f32 'float64 series-sum-f64))

(define min-table
  (hash 'int8 series-min-i8 'int16 series-min-i16
        'int32 series-min-i32 'int64 series-min-i64
        'uint8 series-min-u8 'uint16 series-min-u16
        'uint32 series-min-u32 'uint64 series-min-u64
        'float32 series-min-f32 'float64 series-min-f64))

(define max-table
  (hash 'int8 series-max-i8 'int16 series-max-i16
        'int32 series-max-i32 'int64 series-max-i64
        'uint8 series-max-u8 'uint16 series-max-u16
        'uint32 series-max-u32 'uint64 series-max-u64
        'float32 series-max-f32 'float64 series-max-f64))

(define mean-table
  (hash 'int8 series-mean-i8 'int16 series-mean-i16
        'int32 series-mean-i32 'int64 series-mean-i64
        'uint8 series-mean-u8 'uint16 series-mean-u16
        'uint32 series-mean-u32 'uint64 series-mean-u64
        'float32 series-mean-f32 'float64 series-mean-f64))

(define (series-reduce who table s)
  (define dt (series-dtype s))
  (define f (hash-ref table dt #f))
  (unless f
    (error who "unsupported dtype for reduction: ~v" dt))
  (f s))

;; sum / mean / min / max are generic across three worlds:
;;   * a single Expr   -> the corresponding aggregation Expr (expr-sum, …), so
;;                        (sum (col "value")) reads like Polars' col("value").sum()
;;   * a single series -> reduce to a scalar (dispatching on dtype)
;;   * anything else   -> the numeric racket/base behaviour, so requiring polars
;;                        does not break (max 1 2 3) or (sum) etc.

(define (sum . args)
  (match args
    [(list (? Expr-ptr? e)) (expr-sum e)]
    [(list (? string? s)) (expr-sum (col s))]
    [(list (? series? s)) (series-reduce 'sum sum-table s)]
    [_ (apply base:+ args)]))

(define (mean . args)
  (match args
    [(list (? Expr-ptr? e)) (expr-mean e)]
    [(list (? string? s)) (expr-mean (col s))]
    [(list (? series? s)) (series-reduce 'mean mean-table s)]
    [(list) (error 'mean "expected at least one argument")]
    [_ (/ (apply base:+ args) (length args))]))

(define (min . args)
  (match args
    [(list (? Expr-ptr? e)) (expr-min e)]
    [(list (? string? s)) (expr-min (col s))]
    [(list (? series? s)) (series-reduce 'min min-table s)]
    [_ (apply base:min args)]))

(define (max . args)
  (match args
    [(list (? Expr-ptr? e)) (expr-max e)]
    [(list (? string? s)) (expr-max (col s))]
    [(list (? series? s)) (series-reduce 'max max-table s)]
    [_ (apply base:max args)]))

;; --- additional Expr aggregators (Polars col(...).agg() spellings) ----------
;;
;; These take an Expr or a bare column name (lifted via col), so both
;; (count (col "value")) and (count "value") work inside agg.  first / last
;; additionally keep their racket/list list-accessor behaviour so requiring
;; polars does not break (first '(1 2 3)).

(define (->agg-expr who x)
  (cond
    [(Expr-ptr? x) x]
    [(string? x) (col x)]
    [else (error who "expected an Expr or column-name string, got ~v" x)]))

(define (count x)     (expr-count    (->agg-expr 'count x)))
(define (n-unique x)  (expr-n-unique (->agg-expr 'n-unique x)))
(define (median x)    (expr-median   (->agg-expr 'median x)))
(define (std x #:ddof [ddof 1]) (expr-std (->agg-expr 'std x) #:ddof ddof))
(define (var x #:ddof [ddof 1]) (expr-var (->agg-expr 'var x) #:ddof ddof))

;; first / last: Expr / column-name -> aggregation Expr; list -> list accessor.
(define (first x)
  (cond
    [(Expr-ptr? x) (expr-first x)]
    [(string? x) (expr-first (col x))]
    [(pair? x) (car x)]
    [else (error 'first "expected an Expr, column name, or non-empty list, got ~v" x)]))

(define (last x)
  (cond
    [(Expr-ptr? x) (expr-last x)]
    [(string? x) (expr-last (col x))]
    [(pair? x) (let loop ([l x]) (if (null? (cdr l)) (car l) (loop (cdr l))))]
    [else (error 'last "expected an Expr, column name, or non-empty list, got ~v" x)]))

;; alias: name an Expr (Polars' .alias) — e.g. (alias (sum (col "value")) "total").
(define (alias e name) (expr-alias e name))

;; --- generic comparison operators -------------------------------------------
;;
;; Binary dispatch, mirroring the sum/min/max precedent:
;;   * an Expr operand -> build a comparison Expr (scalars auto-lifted), so
;;                        (> (col "value") 15) reads like Polars' col(..) > 15
;;   * a series operand -> build an eager boolean-mask series by broadcasting the
;;                        scalar into a constant series of the operand's dtype and
;;                        running the element-wise series-series op
;;   * otherwise        -> the numeric racket/base operator (variadic preserved)

;; A constant series of `dt`, length `n`, every slot = `value`.  Reuses the
;; same dtype->constructor / coerce-elements machinery as the `series` ctor.
(define (const-series dt n value)
  (define ctor (dtype->constructor dt #f))
  (wrap-series (ctor "" (coerce-elements dt (make-list n value)))))

;; The other operand of a series comparison, as a series matching `s`.
(define (cmp-other s other)
  (if (series? other) other (const-series (series-dtype s) (series-len s) other)))

;; Each operator: expr builder, series op (series on the left), the reflected
;; series op (series on the right), and the numeric fallback.
(define-syntax-rule (define-cmp name expr-op series-op series-op-reflected base-op)
  (define (name . args)
    (cond
      [(andmap base:number? args) (apply base-op args)]
      [(base:= (length args) 2)
       (let ([a (base:car args)] [b (base:cadr args)])
         (cond
           [(or (Expr-ptr? a) (Expr-ptr? b)) (expr-op a b)]
           [(series? a) (wrap-series (series-op a (cmp-other a b)))]
           [(series? b) (wrap-series (series-op-reflected b (cmp-other b a)))]
           [else (apply base-op args)]))]
      [else (apply base-op args)])))

;; `!=` has no racket/base spelling; fall back to (not (= …)).
(define (base:!= . args) (base:not (apply base:= args)))

(define-cmp >  expr-gt series-gt series-lt base:>)
(define-cmp <  expr-lt series-lt series-gt base:<)
(define-cmp >= expr-ge series-ge series-le base:>=)
(define-cmp <= expr-le series-le series-ge base:<=)
(define-cmp =  expr-eq series-eq series-eq base:=)
(define-cmp != expr-ne series-ne series-ne base:!=)

;; --- data-first frame operations (thread with ~>) ---------------------------

;; filter: (filter df predicate-expr) / (filter df mask-series) -> dataframe.
;; Falls back to racket/base filter, so (filter even? '(1 2 3 4)) still works.
(define (filter . args)
  (match args
    [(list (? dataframe? d) (? Expr-ptr? pred))
     (wrap-dataframe (dataframe-filter-expr d pred))]
    [(list (? dataframe? d) (? series? mask))
     (wrap-dataframe (dataframe-filter d mask))]
    [_ (apply base:filter args)]))

;; sort: (sort df names #:descending d) -> dataframe; otherwise racket/base sort.
;; `names` may be a single column name or a list of names.
(define (sort x [second unset] #:descending [descending unset])
  (cond
    [(dataframe? x)
     (when (eq? second unset)
       (error 'sort "sorting a dataframe requires column name(s)"))
     (wrap-dataframe
      (dataframe-sort x (if (list? second) second (list second))
                      #:descending (if (eq? descending unset) #f descending)))]
    [(eq? second unset)
     (error 'sort "racket/base sort needs a less-than? procedure")]
    [else (base:sort x second)]))

;; --- group-by / agg: the deferred, threading-compatible group handle --------
;;
;; Rust's LazyGroupBy::agg consumes self, so there is no standalone group handle
;; to round-trip across the FFI.  `group-by` instead returns a lightweight Racket
;; struct that just captures the source frame and the key columns (no FFI yet);
;; `agg` then performs the single folded dataframe-group-by-agg call.  This lets
;;   (~> df (group-by "group") (agg (sum (col "value"))))
;; read exactly like df.group_by("group").agg(col("value").sum()).
(struct grouped (frame keys) #:reflection-name 'grouped)

(define (group-by frame . keys)
  (when (null? keys)
    (error 'group-by "needs at least one group key"))
  (grouped frame keys))

(define (agg g . agg-exprs)
  (unless (grouped? g)
    (error 'agg "expected a grouped frame from group-by, got ~v" g))
  (wrap-dataframe
   (dataframe-group-by-agg (grouped-frame g) (grouped-keys g) agg-exprs)))

;; ---------------------------------------------------------------------------
;; describe / ref helpers (used by the generic methods above)
;;
;; describe mirrors Polars' .describe(): it returns a summary-statistics
;; *dataframe* (which prints as a table), not a one-line string.  A series'
;; describe adapts its rows to the dtype — numeric gets the full
;; count/null_count/mean/std/min/25%/50%/75%/max, boolean drops std and the
;; quantiles, and other dtypes (string, temporal) keep just
;; count/null_count/min/max.  A dataframe's describe uses Polars' fixed nine-row
;; layout for every column, leaving cells a column has no statistic for null.

(define numeric-dtypes
  '(int8 int16 int32 int64 uint8 uint16 uint32 uint64 float32 float64))

(define (numeric-dtype? dt) (and (symbol? dt) (memq dt numeric-dtypes) #t))

;; The nine statistic labels, in Polars' order.
(define describe-stat-names
  '("count" "null_count" "mean" "std" "min" "25%" "50%" "75%" "max"))

;; mean / min / max of a series via the expr engine (works for every dtype,
;; including string min/max), returned as three values.
(define (series-mean-min-max s)
  (define name (series-name s))
  (define out
    (dataframe-select-exprs
     (dataframe-new (list s))
     (list (expr-alias (expr-mean (col name)) "mean")
           (expr-alias (expr-min (col name)) "min")
           (expr-alias (expr-max (col name)) "max"))))
  (values (series-ref (dataframe-column out "mean") 0)
          (series-ref (dataframe-column out "min") 0)
          (series-ref (dataframe-column out "max") 0)))

(define (->f64-or-null v) (if (polars-null? v) v (exact->inexact v)))

;; Render a min/max scalar as a string for the non-numeric describe path.
;; Strings pass through; gregor temporal values get a clean ISO-ish rendering
;; instead of their #<datetime …> write form.
(define (->string-or-null v)
  (cond
    [(polars-null? v) v]
    [(datetime? v) (~t v "yyyy-MM-dd HH:mm:ss")]
    [(date? v) (~t v "yyyy-MM-dd")]
    [else (format "~a" v)]))

;; The nine numeric statistics for `s`, all as flonums (or polars-null), in
;; describe-stat-names order.
(define (numeric-describe-values s)
  (define n (series-len s))
  (define nulls (series-null-count s))
  (define-values (mean mn mx) (series-mean-min-max s))
  (list (exact->inexact (- n nulls))
        (exact->inexact nulls)
        (->f64-or-null mean)
        (series-std s)
        (->f64-or-null mn)
        (series-quantile s 0.25)
        (series-quantile s 0.50)
        (series-quantile s 0.75)
        (->f64-or-null mx)))

;; Build the two-column (statistic, value) result frame.
(define (stats-frame names values)
  (dataframe (list (series names #:name "statistic")
                   (series values #:name "value"))))

(define (describe-series s)
  (define dt (series-dtype s))
  (define n (series-len s))
  (define nulls (series-null-count s))
  (define count (- n nulls))
  (cond
    [(numeric-dtype? dt)
     (stats-frame describe-stat-names (numeric-describe-values s))]
    [(eq? dt 'boolean)
     (define-values (mean mn mx) (series-mean-min-max s))
     (define (bool->f v) (if (polars-null? v) v (if v 1.0 0.0)))
     (stats-frame '("count" "null_count" "mean" "min" "max")
                  (list (exact->inexact count) (exact->inexact nulls)
                        (->f64-or-null mean) (bool->f mn) (bool->f mx)))]
    [else
     (define-values (_mean mn mx) (series-mean-min-max s))
     (stats-frame '("count" "null_count" "min" "max")
                  (list (number->string count) (number->string nulls)
                        (->string-or-null mn) (->string-or-null mx)))]))

;; One value column for a dataframe's describe: always nine rows, with nulls in
;; the slots the column's dtype has no statistic for.
(define (describe-column-values s)
  (define dt (series-dtype s))
  (define n (series-len s))
  (define nulls (series-null-count s))
  (define count (- n nulls))
  (cond
    [(numeric-dtype? dt) (numeric-describe-values s)]
    [(eq? dt 'boolean)
     (define-values (mean mn mx) (series-mean-min-max s))
     (define (bool->f v) (if (polars-null? v) v (if v 1.0 0.0)))
     (list (exact->inexact count) (exact->inexact nulls) (->f64-or-null mean)
           polars-null (bool->f mn) polars-null polars-null polars-null (bool->f mx))]
    [else
     (define-values (_mean mn mx) (series-mean-min-max s))
     (list (number->string count) (number->string nulls)
           polars-null polars-null (->string-or-null mn)
           polars-null polars-null polars-null (->string-or-null mx))]))

(define (describe-dataframe d)
  (define names (dataframe-column-names d))
  (define value-cols
    (for/list ([nm (in-list names)])
      (series (describe-column-values (wrap-series (dataframe-column d nm)))
              #:name nm)))
  (dataframe (cons (series describe-stat-names #:name "statistic") value-cols)))

;; ref dispatch for a series: positional index only.
(define (series-ref* s key columns rows)
  (cond
    [(not (eq? columns unset)) (error 'ref "a series has no columns to select")]
    [(not (eq? rows unset)) (error 'ref "series row slicing not supported")]
    [(eq? key unset) (error 'ref "ref on a series requires an index")]
    [else (series-ref s key)]))

;; ref dispatch for a dataframe: column selection (by name or index) via either
;; a positional key or #:columns.  A single selector returns a wrapped series; a
;; list of selectors returns a wrapped dataframe (a column-projected slice).
;; Row slicing (#:rows) is reserved but not yet implemented.
(define (column->name d c)
  (cond
    [(string? c) c]
    [(exact-nonnegative-integer? c) (dataframe-column-name d c)]
    [else (error 'ref "dataframe column selector must be a string or index, got ~v" c)]))

(define (dataframe-ref* d key columns rows)
  (unless (eq? rows unset)
    (error 'ref "dataframe row slicing not yet implemented"))
  (define sel
    (cond
      [(not (eq? columns unset)) columns]
      [(not (eq? key unset)) key]
      [else (error 'ref "ref on a dataframe requires a column key or #:columns")]))
  (cond
    [(list? sel)
     (wrap-dataframe (dataframe-select d (map (lambda (c) (column->name d c)) sel)))]
    [else (wrap-series (dataframe-column d (column->name d sel)))]))

;; ---------------------------------------------------------------------------
;; clone / rename

;; series-slice already returns a fresh series, so a full-length slice is a
;; cheap clone that needs no native-lib support.
(define (series-clone s)
  (wrap-series (series-slice s 0 (series-len s))))

(define (clone x)
  (cond
    [(series? x) (series-clone x)]
    [else (error 'clone "expected a series, got ~v" x)]))

;; mutating: renames in place, returns void (as is conventional for ! mutators)
(define (rename! x new-name)
  (cond
    [(series? x) (series-rename x new-name)]
    [else (error 'rename! "expected a series, got ~v" x)]))

;; non-mutating: returns a renamed copy, leaving the original untouched
(define (rename x new-name)
  (cond
    [(series? x)
     (define c (series-clone x))
     (series-rename c new-name)
     c]
    [else (error 'rename "expected a series, got ~v" x)]))

;; ---------------------------------------------------------------------------
;; Polars-style printing

(define (dtype->polars-label dt)
  (define (tu->label tu)
    (case tu
      [(milliseconds) "ms"]
      [(microseconds) "us"]
      [(nanoseconds)  "ns"]
      [else (format "~a" tu)]))
  (cond
    [(symbol? dt)
     (case dt
       [(int8) "i8"] [(int16) "i16"] [(int32) "i32"] [(int64) "i64"]
       [(uint8) "u8"] [(uint16) "u16"] [(uint32) "u32"] [(uint64) "u64"]
       [(float32) "f32"] [(float64) "f64"]
       [(string) "str"] [(boolean) "bool"]
       [(date) "date"] [(time) "time"]
       [else (format "~a" dt)])]
    [(and (pair? dt) (eq? (car dt) 'datetime))
     (format "datetime[~a]" (tu->label (cadr dt)))]
    [(and (pair? dt) (eq? (car dt) 'duration))
     (format "duration[~a]" (tu->label (cadr dt)))]
    [else (format "~a" dt)]))

(define (value->cell v)
  (cond
    [(polars-null? v) "null"]
    [(string? v) (format "~s" v)]      ; quoted, like Polars
    [else (format "~a" v)]))

;; Polars shows at most ~10 rows: the first 5, an ellipsis, then the last 5.
(define (row-indices len)
  (if (<= len 10)
      (range len)
      (append (range 0 5) (list 'ellipsis) (range (- len 5) len))))

(define (series->string s)
  (define len (series-len s))
  (define lines
    (for/list ([i (in-list (row-indices len))])
      (if (eq? i 'ellipsis)
          "\t…"
          (string-append "\t" (value->cell (series-ref s i))))))
  (string-append
   (format "shape: (~a,)\n" len)
   (format "Series: '~a' [~a]\n" (series-name s) (dtype->polars-label (series-dtype s)))
   "[\n"
   (string-join lines "\n")
   "\n]"))

;; ---------------------------------------------------------------------------

(module+ test
  ;; constructor returns a series wrapper; series? distinguishes it
  (check-pred series? (series '(1 2 3)))
  (check-false (series? 5))
  (check-false (series? '(1 2 3)))

  ;; dtype inference + alias parity
  (check-equal? (series-dtype (series '(1 2 3) #:dtype 'i32)) 'int32)
  (check-equal? (series-dtype (series '(1 2 3) #:dtype 'int32)) 'int32)
  (check-equal? (series-dtype (series '(1 2 3))) 'int64)   ; Polars default
  (check-equal? (series-dtype (series '(1.0 2.0))) 'float64)
  (check-equal? (series-dtype (series '("a" "b"))) 'string)
  (check-equal? (series-dtype (series '(#t #f))) 'boolean)
  (check-equal? (series-dtype (series (list (datetime 2024 1 1)))) '(datetime milliseconds #f))
  (check-equal? (series-dtype (series (vector 1 2 3) #:dtype 'f64)) 'float64)
  (check-equal? (series-name (series '(1 2 3) #:name "xs")) "xs")
  (check-equal? (series-dtype (series (list (expt 2 40)))) 'int64)

  ;; reductions dispatch on dtype
  (define ints (series '(1 2 3 4) #:name "ints" #:dtype 'i32))
  (define floats (series '(1.5 2.0 4.25 8.0) #:name "floats"))
  (check-equal? (sum ints) 10)
  (check-equal? (max floats) 8.0)
  (check-equal? (min ints) 1)
  (check-equal? (mean ints) 2.5)
  (check-pred flonum? (mean ints))

  ;; numeric fallback preserves racket/base behaviour
  (check-equal? (max 1 2 3) 3)
  (check-equal? (min 4 2 9) 2)
  (check-equal? (sum 1 2 3) 6)
  (check-equal? (sum) 0)
  (check-equal? (mean 2 4) 3)

  ;; Polars-style printing
  (check-true (regexp-match? #rx"shape: \\(4,\\)" (series->string ints)))
  (check-true (regexp-match? #rx"Series: 'ints' \\[i32\\]" (series->string ints)))
  (check-equal? (format "~a" ints) (series->string ints))   ; custom-write
  ;; null and truncation
  (define big (series (range 100) #:dtype 'i64))
  (check-true (regexp-match? #rx"…" (series->string big)))
  (define withnull (series (list 10 polars-null 30) #:dtype 'i32))
  (check-true (regexp-match? #rx"null" (series->string withnull)))

  ;; ref on series and dataframe; df ref returns a wrapped series
  (check-equal? (ref withnull 0) 10)
  (check-equal? (ref withnull 1) polars-null)
  (define df (dataframe (list ints floats)))   ; accepts series wrappers
  (check-pred series? (ref df "floats"))
  (check-pred series? (ref df 0))
  (check-equal? (series-name (ref df "floats")) "floats")
  (check-equal? (series-name (ref df 0)) "ints")

  ;; clone / rename / rename!
  (define original (series '(1 2 3) #:name "orig" #:dtype 'i32))
  (define renamed (rename original "copy"))
  (check-pred series? renamed)
  (check-equal? (series-name original) "orig")  ; untouched
  (check-equal? (series-name renamed) "copy")
  (check-pred void? (rename! original "mutated"))
  (check-equal? (series-name original) "mutated")

  ;; series capability generics
  (check-equal? (len floats) 4)
  (check-equal? (shape floats) '(4))
  (check-equal? (call-with-values (lambda () (shape/values floats)) list) '(4))
  (check-equal? (dtype ints) 'int32)
  (check-equal? (null-count withnull) 1)

  ;; dataframe wrapper
  (define users (series '("alice" "bob" "carol") #:name "user"))
  (define sc (series '(10 25 18) #:name "score" #:dtype 'i32))
  (define cost (series '(1.2 3.5 2.0) #:name "cost"))
  (define frame (dataframe (list users sc cost)))
  (check-pred dataframe? frame)
  (check-false (dataframe? sc))

  ;; shape / len / width / height / column metadata
  (check-equal? (shape frame) '(3 3))
  (check-equal? (call-with-values (lambda () (shape/values frame)) list) '(3 3))
  (check-equal? (len frame) 3)
  (check-equal? (height frame) 3)
  (check-equal? (width frame) 3)
  (check-equal? (column-name frame 0) "user")
  (check-equal? (column-names frame) '("user" "score" "cost"))

  ;; ref: single column (positional or #:columns) -> series; list -> dataframe
  (check-pred series? (ref frame "score"))
  (check-pred series? (ref frame #:columns "score"))
  (check-pred series? (ref frame #:columns 1))
  (check-equal? (dtype (ref frame #:columns "score")) 'int32)
  (define projected (ref frame #:columns '("user" "cost")))
  (check-pred dataframe? projected)
  (check-equal? (width projected) 2)
  (check-equal? (column-names projected) '("user" "cost"))

  ;; row slicing is reserved, not yet implemented
  (check-exn exn:fail? (lambda () (ref frame #:rows 0)))

  ;; custom-write prints the Polars table
  (check-true (regexp-match? #rx"shape: \\(3, 3\\)" (format "~a" frame)))

  ;; describe returns a Polars-style stats dataframe (matching .describe())
  (define sc-desc (describe sc))             ; sc = i32 '(10 25 18)
  (check-pred dataframe? sc-desc)
  (check-equal? (column-names sc-desc) '("statistic" "value"))
  (check-equal? (height sc-desc) 9)          ; numeric -> 9 rows
  (check-equal? (ref (ref sc-desc #:columns "statistic") 0) "count")
  (check-equal? (ref (ref sc-desc #:columns "value") 0) 3.0)   ; count
  (check-equal? (ref (ref sc-desc #:columns "value") 4) 10.0)  ; min
  (check-equal? (ref (ref sc-desc #:columns "value") 8) 25.0)  ; max

  (define fr-desc (describe frame))          ; user(str) score(i32) cost(f64)
  (check-pred dataframe? fr-desc)
  (check-equal? (height fr-desc) 9)          ; fixed nine-row layout
  (check-equal? (column-names fr-desc) '("statistic" "user" "score" "cost"))
  (check-equal? (ref (ref fr-desc #:columns "user") 0) "3")       ; string count
  (check-equal? (ref (ref fr-desc #:columns "user") 4) "alice")   ; string min
  (check-equal? (ref (ref fr-desc #:columns "user") 8) "carol")   ; string max
  (check-pred polars-null? (ref (ref fr-desc #:columns "user") 2)) ; mean -> null
  (check-equal? (ref (ref fr-desc #:columns "score") 4) 10.0)     ; numeric min

  ;; --- fluent / threading-compatible API -----------------------------------

  (define ops-df
    (dataframe (list (series '("a" "a" "b" "b" "c") #:name "group")
                     (series '(10 25 7 30 18) #:name "value" #:dtype 'i32)
                     (series '(1.2 2.4 0.5 3.1 1.8) #:name "cost"))))

  ;; comparison operators dispatch three ways
  ;;  * Expr operand -> a comparison Expr
  (check-pred Expr-ptr? (> (col "value") 15))
  (check-pred Expr-ptr? (< 15 (col "value")))
  (check-pred Expr-ptr? (= (col "group") "a"))
  ;;  * series operand -> an eager boolean mask (works on int64, the default)
  (define v64 (series '(10 25 7 30 18) #:name "value"))   ; int64
  (define mask (> v64 15))
  (check-pred series? mask)
  (check-equal? (dtype mask) 'boolean)
  (check-equal? (for/list ([i (in-range (len mask))]) (ref mask i))
                '(#f #t #f #t #t))
  ;; series on the right reflects the comparison
  (check-equal? (for/list ([i (in-range 5)]) (ref (< 15 v64) i))
                '(#f #t #f #t #t))
  ;;  * numbers -> racket/base behaviour (variadic preserved)
  (check-equal? (> 3 2) #t)
  (check-equal? (< 1 2 3) #t)
  (check-equal? (= 2 2) #t)
  (check-equal? (!= 2 3) #t)
  (check-equal? (!= 2 2) #f)

  ;; filter: Expr predicate, mask series, and racket/base fallback
  (check-equal? (height (filter ops-df (> (col "value") 15))) 3)
  (check-equal? (height (filter ops-df mask)) 3)
  (check-equal? (filter even? '(1 2 3 4)) '(2 4))

  ;; sort: dataframe (multi-key, descending list) and racket/base fallback
  (define sorted (sort ops-df '("group" "value") #:descending '(#f #t)))
  (check-pred dataframe? sorted)
  (check-equal? (ref (ref sorted #:columns "value") 0) 25)   ; a, value desc
  (check-equal? (sort '(3 1 2) <) '(1 2 3))

  ;; group-by + agg: deferred handle threads, agg performs the single FFI call
  (check-pred grouped? (group-by ops-df "group"))
  (define rolled
    (~> ops-df
        (group-by "group")
        (agg (alias (sum (col "value")) "sum_value")
             (alias (count (col "value")) "n"))))
  (check-pred dataframe? rolled)
  (check-equal? (height rolled) 3)
  (check-equal? (sort (column-names rolled) string<?) '("group" "n" "sum_value"))
  ;; per-group sums: a=35, b=37, c=18 (group order is not guaranteed)
  (define (group-sum g)
    (for/first ([i (in-range (height rolled))]
                #:when (string=? (ref (ref rolled #:columns "group") i) g))
      (ref (ref rolled #:columns "sum_value") i)))
  (check-equal? (group-sum "a") 35)
  (check-equal? (group-sum "b") 37)
  (check-equal? (group-sum "c") 18)

  ;; Expr aggregators accept a bare column name too
  (check-pred Expr-ptr? (sum "value"))
  (check-pred Expr-ptr? (mean (col "value")))
  (check-pred Expr-ptr? (n-unique "group"))
  ;; first / last keep their list-accessor behaviour
  (check-equal? (first '(1 2 3)) 1)
  (check-equal? (last '(1 2 3)) 3)
  (check-pred Expr-ptr? (first (col "value"))))
