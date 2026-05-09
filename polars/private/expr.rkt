#lang racket/base

;; Expr / LazyFrame DSL — Phase A1.
;;
;; Sits on top of polars/private/foreign for the FFI plumbing (define-compat,
;; the libcompat handle, _DataFrame-ptr).  Exposes its own Expr-ptr and
;; LazyFrame-ptr opaque cpointer types.

(require ffi/unsafe
         ffi/unsafe/alloc
         ffi/unsafe/define
         ffi/unsafe/define/conventions
         racket/runtime-path
         (only-in polars/private/foreign
                  _DataFrame-ptr
                  DataFrame-ptr?
                  _CompatDType make-CompatDType
                  compat-dtype-tag/boolean
                  compat-dtype-tag/uint8 compat-dtype-tag/uint16
                  compat-dtype-tag/uint32 compat-dtype-tag/uint64
                  compat-dtype-tag/int8 compat-dtype-tag/int16
                  compat-dtype-tag/int32 compat-dtype-tag/int64
                  compat-dtype-tag/float32 compat-dtype-tag/float64
                  compat-dtype-tag/string compat-dtype-tag/binary
                  compat-dtype-tag/date compat-dtype-tag/datetime
                  compat-dtype-tag/duration compat-dtype-tag/time
                  compat-dtype-tag/null
                  compat-time-unit/none
                  compat-time-unit/nanoseconds
                  compat-time-unit/microseconds
                  compat-time-unit/milliseconds))

(module+ test
  (require rackunit
           (only-in polars/private/foreign
                    series-new-i32
                    series-new-i64
                    series-new-f64
                    series-new-str
                    dataframe-new
                    dataframe-height
                    dataframe-width
                    dataframe-column
                    dataframe-column-names
                    dataframe-column-name
                    series-len
                    series-dtype
                    series-sum-i32
                    series-sum-f64)))

(provide _Expr-ptr Expr-ptr?
         _LazyFrame-ptr LazyFrame-ptr?
         expr-drop lazyframe-drop
         expr-col expr-lit-i32 expr-lit-i64 expr-lit-f64 expr-lit-bool expr-lit-str
         expr-alias
         lit col ->expr ->key-expr
         expr-add expr-sub expr-mul expr-div expr-mod
         expr-gt expr-lt expr-ge expr-le expr-eq expr-ne
         expr-and expr-or expr-xor
         expr-not expr-neg expr-is-null expr-is-not-null
         expr-sum expr-mean expr-min expr-max
         expr-count expr-n-unique expr-first expr-last expr-median
         expr-std expr-var
         expr-over expr-sort
         dataframe-lazy
         lazyframe-with-columns lazyframe-collect
         lazyframe-filter lazyframe-select
         lazyframe-group-by-agg
         lazyframe-sort lazyframe-unique lazyframe-drop-nulls
         lazyframe-head lazyframe-tail lazyframe-slice
         lazyframe-join
         expr-cast
         dataframe-with-columns dataframe-select-exprs dataframe-filter-expr
         dataframe-group-by-agg
         dataframe-sort-exprs)

(define-runtime-path expr-native-libs-dir "../native-libs")

(define-ffi-definer define-compat
  (ffi-lib (build-path expr-native-libs-dir "libcompat"))
  #:make-c-id convention:hyphen->underscore)

(define-cpointer-type _Expr-ptr)
(define-cpointer-type _LazyFrame-ptr)

(define-compat expr-drop
  (_fun _Expr-ptr -> _void)
  #:wrap (deallocator))

(define-compat lazyframe-drop
  (_fun _LazyFrame-ptr -> _void)
  #:wrap (deallocator))

(define-compat expr-col
  (_fun _string -> _Expr-ptr)
  #:wrap (allocator expr-drop))

(define-compat expr-lit-i32
  (_fun _int32 -> _Expr-ptr)
  #:wrap (allocator expr-drop))

(define-compat expr-lit-i64
  (_fun _int64 -> _Expr-ptr)
  #:wrap (allocator expr-drop))

(define-compat expr-lit-f64
  (_fun _double -> _Expr-ptr)
  #:wrap (allocator expr-drop))

(define-compat expr-lit-bool/raw
  (_fun _uint8 -> _Expr-ptr)
  #:c-id expr_lit_bool
  #:wrap (allocator expr-drop))

(define (expr-lit-bool b)
  (expr-lit-bool/raw (if b 1 0)))

(define-compat expr-lit-str
  (_fun _string -> _Expr-ptr)
  #:wrap (allocator expr-drop))

(define-compat expr-alias
  (_fun _Expr-ptr _string -> _Expr-ptr)
  #:wrap (allocator expr-drop))

;; lit dispatches on Racket type.
(define (lit v)
  (cond
    [(boolean? v) (expr-lit-bool v)]
    [(exact-integer? v)
     (if (and (>= v -2147483648) (<= v 2147483647))
         (expr-lit-i32 v)
         (expr-lit-i64 v))]
    [(real? v) (expr-lit-f64 (exact->inexact v))]
    [(string? v) (expr-lit-str v)]
    [else (error 'lit "no Expr literal for ~v" v)]))

;; col is a one-letter alias for expr-col, since column references are by far
;; the most common Expr leaf.
(define (col name) (expr-col name))

(define-compat dataframe-lazy
  (_fun _DataFrame-ptr -> _LazyFrame-ptr)
  #:wrap (allocator lazyframe-drop))

(define-compat lazyframe-with-columns/c
  (_fun _LazyFrame-ptr
        (exprs : (_list i _Expr-ptr))
        (_size = (length exprs))
        -> _LazyFrame-ptr)
  #:c-id lazyframe_with_columns
  #:wrap (allocator lazyframe-drop))

(define (lazyframe-with-columns lf exprs)
  (lazyframe-with-columns/c lf exprs))

(define-compat lazyframe-collect
  (_fun _LazyFrame-ptr -> _DataFrame-ptr)
  #:c-id lazyframe_collect)

;; --- Phase A2: Expr operations ---

;; Each binary op has a /raw Expr-Expr binding plus a public wrapper
;; that auto-lifts non-Expr arguments via `lit`.  Hand-written rather
;; than macro-generated because define-compat needs a literal #:c-id.

(define (->expr v)
  (if (Expr-ptr? v) v (lit v)))

(define-compat expr-add/raw
  (_fun _Expr-ptr _Expr-ptr -> _Expr-ptr)
  #:c-id expr_add
  #:wrap (allocator expr-drop))
(define (expr-add a b) (expr-add/raw (->expr a) (->expr b)))

(define-compat expr-sub/raw
  (_fun _Expr-ptr _Expr-ptr -> _Expr-ptr)
  #:c-id expr_sub
  #:wrap (allocator expr-drop))
(define (expr-sub a b) (expr-sub/raw (->expr a) (->expr b)))

(define-compat expr-mul/raw
  (_fun _Expr-ptr _Expr-ptr -> _Expr-ptr)
  #:c-id expr_mul
  #:wrap (allocator expr-drop))
(define (expr-mul a b) (expr-mul/raw (->expr a) (->expr b)))

(define-compat expr-div/raw
  (_fun _Expr-ptr _Expr-ptr -> _Expr-ptr)
  #:c-id expr_div
  #:wrap (allocator expr-drop))
(define (expr-div a b) (expr-div/raw (->expr a) (->expr b)))

(define-compat expr-mod/raw
  (_fun _Expr-ptr _Expr-ptr -> _Expr-ptr)
  #:c-id expr_mod
  #:wrap (allocator expr-drop))
(define (expr-mod a b) (expr-mod/raw (->expr a) (->expr b)))

(define-compat expr-gt/raw
  (_fun _Expr-ptr _Expr-ptr -> _Expr-ptr)
  #:c-id expr_gt
  #:wrap (allocator expr-drop))
(define (expr-gt a b) (expr-gt/raw (->expr a) (->expr b)))

(define-compat expr-lt/raw
  (_fun _Expr-ptr _Expr-ptr -> _Expr-ptr)
  #:c-id expr_lt
  #:wrap (allocator expr-drop))
(define (expr-lt a b) (expr-lt/raw (->expr a) (->expr b)))

(define-compat expr-ge/raw
  (_fun _Expr-ptr _Expr-ptr -> _Expr-ptr)
  #:c-id expr_ge
  #:wrap (allocator expr-drop))
(define (expr-ge a b) (expr-ge/raw (->expr a) (->expr b)))

(define-compat expr-le/raw
  (_fun _Expr-ptr _Expr-ptr -> _Expr-ptr)
  #:c-id expr_le
  #:wrap (allocator expr-drop))
(define (expr-le a b) (expr-le/raw (->expr a) (->expr b)))

(define-compat expr-eq/raw
  (_fun _Expr-ptr _Expr-ptr -> _Expr-ptr)
  #:c-id expr_eq
  #:wrap (allocator expr-drop))
(define (expr-eq a b) (expr-eq/raw (->expr a) (->expr b)))

(define-compat expr-ne/raw
  (_fun _Expr-ptr _Expr-ptr -> _Expr-ptr)
  #:c-id expr_ne
  #:wrap (allocator expr-drop))
(define (expr-ne a b) (expr-ne/raw (->expr a) (->expr b)))

(define-compat expr-and/raw
  (_fun _Expr-ptr _Expr-ptr -> _Expr-ptr)
  #:c-id expr_and
  #:wrap (allocator expr-drop))
(define (expr-and a b) (expr-and/raw (->expr a) (->expr b)))

(define-compat expr-or/raw
  (_fun _Expr-ptr _Expr-ptr -> _Expr-ptr)
  #:c-id expr_or
  #:wrap (allocator expr-drop))
(define (expr-or a b) (expr-or/raw (->expr a) (->expr b)))

(define-compat expr-xor/raw
  (_fun _Expr-ptr _Expr-ptr -> _Expr-ptr)
  #:c-id expr_xor
  #:wrap (allocator expr-drop))
(define (expr-xor a b) (expr-xor/raw (->expr a) (->expr b)))

(define-compat expr-not
  (_fun _Expr-ptr -> _Expr-ptr)
  #:wrap (allocator expr-drop))

(define-compat expr-neg
  (_fun _Expr-ptr -> _Expr-ptr)
  #:wrap (allocator expr-drop))

(define-compat expr-is-null
  (_fun _Expr-ptr -> _Expr-ptr)
  #:wrap (allocator expr-drop))

(define-compat expr-is-not-null
  (_fun _Expr-ptr -> _Expr-ptr)
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

;; std / var carry a ddof argument (degrees-of-freedom adjustment).
;; Default to 1 to match polars (and pandas).
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
  (_fun _Expr-ptr _uint8 -> _Expr-ptr)
  #:c-id expr_sort
  #:wrap (allocator expr-drop))

(define (expr-sort e #:descending [descending #f])
  (expr-sort/raw e (if descending 1 0)))

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
  (lazyframe-collect
   (lazyframe-with-columns (dataframe-lazy df) exprs)))

(define (dataframe-select-exprs df exprs)
  (lazyframe-collect
   (lazyframe-select (dataframe-lazy df) exprs)))

(define (dataframe-filter-expr df predicate)
  (lazyframe-collect
   (lazyframe-filter (dataframe-lazy df) predicate)))

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
  (lazyframe-collect
   (lazyframe-group-by-agg (dataframe-lazy df) keys aggs)))

;; --- Phase A6: more LazyFrame ops (sort / unique / drop_nulls) ---
;;
;; Mirror the eager dataframe-{sort,unique,drop-nulls} surface so a fluent
;; lazy pipeline (filter → group-by-agg → sort) doesn't need to .collect()
;; mid-stream.  `lazyframe-sort` accepts the same #:descending shapes as
;; the eager `dataframe-sort` (a single bool, or a per-column list).

(define-compat lazyframe-sort/c
  (_fun _LazyFrame-ptr
        (names : (_list i _string))
        (descending : (_list i _uint8))
        (_size = (length names))
        -> _LazyFrame-ptr)
  #:c-id lazyframe_sort
  #:wrap (allocator lazyframe-drop))

(define (lazyframe-sort lf names #:descending [descending #f])
  (define dlist
    (cond
      [(eq? descending #f) (map (lambda (_) 0) names)]
      [(eq? descending #t) (map (lambda (_) 1) names)]
      [(list? descending)
       (unless (= (length descending) (length names))
         (error 'lazyframe-sort
                "descending list length ~a does not match names length ~a"
                (length descending) (length names)))
       (map (lambda (b) (if b 1 0)) descending)]
      [else (error 'lazyframe-sort "bad descending: ~v" descending)]))
  (lazyframe-sort/c lf names dlist))

(define-compat lazyframe-unique
  (_fun _LazyFrame-ptr -> _LazyFrame-ptr)
  #:wrap (allocator lazyframe-drop))

(define-compat lazyframe-drop-nulls
  (_fun _LazyFrame-ptr -> _LazyFrame-ptr)
  #:wrap (allocator lazyframe-drop))

(define (dataframe-sort-exprs df names #:descending [descending #f])
  (lazyframe-collect
   (lazyframe-sort (dataframe-lazy df) names #:descending descending)))

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

;; --- Phase A8: lazy join ---
;;
;; Mirrors the eager `dataframe-join` keyword surface (#:on, #:left-on,
;; #:right-on, #:how) and shares its CompatJoinKind tags.  Cross join
;; ignores keys; resolved before crossing the FFI boundary.

(define compat-join-kind/inner 1)
(define compat-join-kind/left  2)
(define compat-join-kind/outer 3)
(define compat-join-kind/cross 4)

(define (lazyframe-join-symbol->code sym)
  (case sym
    [(inner) compat-join-kind/inner]
    [(left)  compat-join-kind/left]
    [(outer full) compat-join-kind/outer]
    [(cross) compat-join-kind/cross]
    [else (error 'lazyframe-join
                 "unknown join kind ~v (expected 'inner 'left 'outer 'cross)"
                 sym)]))

(define-compat lazyframe-join/c
  (_fun _LazyFrame-ptr _LazyFrame-ptr
        (left-on : (_list i _string))
        (_size = (length left-on))
        (right-on : (_list i _string))
        (_size = (length right-on))
        _int32
        -> _LazyFrame-ptr)
  #:c-id lazyframe_join
  #:wrap (allocator lazyframe-drop))

(define (lazyframe-join left right
                        #:on [on #f]
                        #:left-on [left-on #f]
                        #:right-on [right-on #f]
                        #:how [how 'inner])
  (define-values (lon ron)
    (cond
      [(eq? how 'cross) (values '() '())]
      [on (values on on)]
      [(and left-on right-on) (values left-on right-on)]
      [else (error 'lazyframe-join
                   "must supply #:on, or #:left-on and #:right-on")]))
  (lazyframe-join/c left right lon ron (lazyframe-join-symbol->code how)))

;; --- Phase A9: expr cast ---
;;
;; Reuses the existing CompatDType cstruct (input side mirror of
;; series-dtype output).  Accepts the symbols emitted by series-dtype
;; for the simple scalars; datetime/duration accept either the bare
;; symbol (defaults to microseconds) or `(datetime <time-unit>)` /
;; `(duration <time-unit>)` for explicit time units.

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
    [else        #f]))

(define (->compat-dtype dtype)
  (cond
    [(symbol? dtype)
     (define tag (simple-dtype-tag dtype))
     (case dtype
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
    [(and (pair? dtype) (eq? (car dtype) 'datetime))
     (make-CompatDType compat-dtype-tag/datetime
                       (time-unit-symbol->code (cadr dtype)) 0 0)]
    [(and (pair? dtype) (eq? (car dtype) 'duration))
     (make-CompatDType compat-dtype-tag/duration
                       (time-unit-symbol->code (cadr dtype)) 0 0)]
    [else (error '->compat-dtype "unsupported cast target ~v" dtype)]))

(define-compat expr-cast/c
  (_fun _Expr-ptr _CompatDType -> _Expr-ptr)
  #:c-id expr_cast
  #:wrap (allocator expr-drop))

(define (expr-cast e dtype)
  (expr-cast/c e (->compat-dtype dtype)))

(module+ test
  (define df
    (dataframe-new
     (list (series-new-i32 "x" '(1 2 3 4))
           (series-new-f64 "y" '(0.5 1.5 2.5 3.5)))))

  (define lf (dataframe-lazy df))
  (check-pred LazyFrame-ptr? lf)

  ;; with-columns adding a literal column
  (define lf2
    (lazyframe-with-columns lf
                            (list (expr-alias (expr-lit-i32 7) "seven"))))
  (check-pred LazyFrame-ptr? lf2)

  (define collected (lazyframe-collect lf2))
  (check-pred DataFrame-ptr? collected)
  (check-equal? (dataframe-height collected) 4)
  (check-equal? (dataframe-width collected) 3)
  (check-equal? (sort (dataframe-column-names collected) string<?)
                '("seven" "x" "y"))
  (check-equal? (series-sum-i32 (dataframe-column collected "seven")) 28)

  ;; lit dispatch
  (check-pred Expr-ptr? (lit 1))
  (check-pred Expr-ptr? (lit 1.5))
  (check-pred Expr-ptr? (lit "hello"))
  (check-pred Expr-ptr? (lit #t))

  ;; col alias
  (check-pred Expr-ptr? (col "x"))

  ;; --- Phase A2 tests: Expr ops via with-columns ---

  (define (collect-with df . exprs)
    (lazyframe-collect
     (lazyframe-with-columns (dataframe-lazy df) exprs)))

  ;; arithmetic: x * 2 -> double_x
  (define df-double
    (collect-with df (expr-alias (expr-mul (col "x") 2) "double_x")))
  (check-equal? (series-sum-i32 (dataframe-column df-double "double_x"))
                20) ;; 2+4+6+8

  ;; arithmetic with auto-lifted f64: y + 1.0
  (define df-yp1
    (collect-with df (expr-alias (expr-add (col "y") 1.0) "y1")))
  (check-= (series-sum-f64 (dataframe-column df-yp1 "y1"))
           12.0  ;; 1.5+2.5+3.5+4.5
           1e-9)

  ;; comparison produces a boolean column
  (define df-mask
    (collect-with df (expr-alias (expr-gt (col "x") 2) "big")))
  (check-equal? (series-dtype (dataframe-column df-mask "big")) 'boolean)

  ;; boolean ops: (x > 1) AND (x < 4)  -> {2, 3}
  (define df-and
    (collect-with df
                  (expr-alias (expr-and (expr-gt (col "x") 1)
                                        (expr-lt (col "x") 4))
                              "in_range")))
  (check-equal? (series-dtype (dataframe-column df-and "in_range")) 'boolean)

  ;; unary not / is_null
  (define df-unops
    (collect-with df
                  (expr-alias (expr-not (expr-eq (col "x") 1)) "not_one")
                  (expr-alias (expr-is-null (col "x")) "x_null")))
  (check-equal? (series-dtype (dataframe-column df-unops "not_one")) 'boolean)
  (check-equal? (series-dtype (dataframe-column df-unops "x_null")) 'boolean)

  ;; --- Phase A3 tests ---

  ;; dataframe-filter-expr: x > 2 -> 2 rows (3, 4)
  (define filtered (dataframe-filter-expr df (expr-gt (col "x") 2)))
  (check-equal? (dataframe-height filtered) 2)
  (check-equal? (series-sum-i32 (dataframe-column filtered "x")) 7)

  ;; dataframe-select-exprs: keep x, add x*10 aliased
  (define projected
    (dataframe-select-exprs df
                            (list (col "x")
                                  (expr-alias (expr-mul (col "x") 10) "x10"))))
  (check-equal? (dataframe-width projected) 2)
  (check-equal? (series-sum-i32 (dataframe-column projected "x10")) 100)

  ;; --- Phase A4 tests: aggregations + lazy group-by ---

  ;; Top-level aggregation: select(col("x").sum()) -> single row of 10
  (define agg-only
    (dataframe-select-exprs df
                            (list (expr-alias (expr-sum (col "x")) "sum_x")
                                  (expr-alias (expr-mean (col "y")) "mean_y"))))
  (check-equal? (dataframe-height agg-only) 1)
  (check-equal? (series-sum-i32 (dataframe-column agg-only "sum_x")) 10)
  (check-= (series-sum-f64 (dataframe-column agg-only "mean_y")) 2.0 1e-9)

  ;; Group-by + agg: groups of x by parity of (x mod 2).
  (define df-grp
    (dataframe-new
     (list (series-new-str "g" '("a" "a" "b" "b" "b"))
           (series-new-i32 "v" '(10 20 1 2 3)))))

  (define grouped
    (dataframe-group-by-agg
     df-grp
     '("g")
     (list (expr-alias (expr-sum (col "v")) "sum_v")
           (expr-alias (expr-count (col "v")) "n"))))
  (check-equal? (dataframe-height grouped) 2)
  ;; sum across groups must equal sum across input regardless of order
  (check-equal? (series-sum-i32 (dataframe-column grouped "sum_v")) 36)

  ;; key list also accepts already-built Expr-ptrs
  (define grouped/expr-key
    (dataframe-group-by-agg
     df-grp
     (list (col "g"))
     (list (expr-alias (expr-max (col "v")) "max_v"))))
  (check-equal? (dataframe-height grouped/expr-key) 2)

  ;; --- Phase A6 tests: lazy sort / unique / drop-nulls ---

  ;; lazyframe-sort: descending=#t on a single column
  (define sorted-desc
    (lazyframe-collect
     (lazyframe-sort (dataframe-lazy df) '("x") #:descending #t)))
  (check-equal? (dataframe-height sorted-desc) 4)
  (check-equal? (series-sum-i32 (dataframe-column sorted-desc "x")) 10)

  ;; per-column descending list
  (define df-multi
    (dataframe-new
     (list (series-new-str "g" '("a" "a" "b" "b"))
           (series-new-i32 "v" '(2 1 4 3)))))
  (define sorted-multi
    (lazyframe-collect
     (lazyframe-sort (dataframe-lazy df-multi) '("g" "v")
                     #:descending '(#f #t))))
  (check-equal? (dataframe-height sorted-multi) 4)

  ;; lazyframe-unique: dedup whole rows
  (define df-dup
    (dataframe-new
     (list (series-new-i32 "k" '(1 1 2 2 3))
           (series-new-i32 "v" '(10 10 20 20 30)))))
  (define deduped
    (lazyframe-collect (lazyframe-unique (dataframe-lazy df-dup))))
  (check-equal? (dataframe-height deduped) 3)

  ;; fluent pipeline: filter → group-by-agg → sort
  (define df-sales
    (dataframe-new
     (list (series-new-str "g" '("a" "a" "b" "b" "c" "c"))
           (series-new-i32 "v" '(10 25 7 30 18 4)))))
  (define top-by-sum
    (lazyframe-collect
     (lazyframe-sort
      (lazyframe-group-by-agg
       (lazyframe-filter (dataframe-lazy df-sales)
                         (expr-gt (col "v") 5))
       '("g")
       (list (expr-alias (expr-sum (col "v")) "sum_v")))
      '("sum_v") #:descending #t)))
  (check-equal? (dataframe-height top-by-sum) 3)
  ;; after filter (drop v=4), per-group sums are a:35, b:37, c:18
  (check-equal? (series-sum-i32 (dataframe-column top-by-sum "sum_v")) 90)

  ;; --- Phase A5 tests: window (over) + per-Expr sort ---

  ;; sum_v_per_g = sum(v).over("g") — same length as input, repeats the
  ;; per-group sum on each row.
  (define df-window
    (dataframe-with-columns
     df-grp
     (list (expr-alias (expr-over (expr-sum (col "v")) '("g"))
                       "sum_v_per_g"))))
  (check-equal? (dataframe-height df-window) 5)
  ;; group "a": v=10+20=30 (2 rows); group "b": v=1+2+3=6 (3 rows)
  ;; total of sum_v_per_g column = 30*2 + 6*3 = 78
  (check-equal? (series-sum-i32 (dataframe-column df-window "sum_v_per_g")) 78)

  ;; expr-over also accepts pre-built Expr keys
  (define df-window/expr-key
    (dataframe-with-columns
     df-grp
     (list (expr-alias (expr-over (expr-max (col "v")) (list (col "g")))
                       "max_v_per_g"))))
  (check-equal? (dataframe-height df-window/expr-key) 5)

  ;; expr-sort inside an aggregation: per group, first(sort(v, desc)) is
  ;; the per-group max.
  (define grouped-sort
    (dataframe-group-by-agg
     df-grp
     '("g")
     (list (expr-alias (expr-first (expr-sort (col "v") #:descending #t))
                       "max_v"))))
  (check-equal? (dataframe-height grouped-sort) 2)
  ;; max(v) per group: a -> 20, b -> 3, sum = 23
  (check-equal? (series-sum-i32 (dataframe-column grouped-sort "max_v")) 23)

  ;; --- Phase A7 tests: lazy head / tail / slice ---

  (define df-rows
    (dataframe-new
     (list (series-new-i32 "x" '(1 2 3 4 5 6)))))

  (define head3
    (lazyframe-collect (lazyframe-head (dataframe-lazy df-rows) 3)))
  (check-equal? (dataframe-height head3) 3)
  (check-equal? (series-sum-i32 (dataframe-column head3 "x")) 6) ;; 1+2+3

  (define tail2
    (lazyframe-collect (lazyframe-tail (dataframe-lazy df-rows) 2)))
  (check-equal? (dataframe-height tail2) 2)
  (check-equal? (series-sum-i32 (dataframe-column tail2 "x")) 11) ;; 5+6

  (define mid
    (lazyframe-collect (lazyframe-slice (dataframe-lazy df-rows) 2 3)))
  (check-equal? (dataframe-height mid) 3)
  (check-equal? (series-sum-i32 (dataframe-column mid "x")) 12) ;; 3+4+5

  ;; pipeline: filter then take first two — no intermediate collect.
  (define top-two-after-filter
    (lazyframe-collect
     (lazyframe-head
      (lazyframe-sort
       (lazyframe-filter (dataframe-lazy df-rows) (expr-gt (col "x") 1))
       '("x") #:descending #t)
      2)))
  (check-equal? (dataframe-height top-two-after-filter) 2)
  ;; sorted desc {6,5,4,3,2}, head 2 -> {6,5}
  (check-equal? (series-sum-i32 (dataframe-column top-two-after-filter "x")) 11)

  ;; --- Phase A8 tests: lazy join ---

  (define users
    (dataframe-new
     (list (series-new-i32 "uid"  '(1 2 3 4))
           (series-new-str "name" '("a" "b" "c" "d")))))
  (define orders
    (dataframe-new
     (list (series-new-i32 "uid"    '(1 1 2 5))
           (series-new-i32 "amount" '(10 20 30 40)))))

  ;; inner join on shared key
  (define joined-inner
    (lazyframe-collect
     (lazyframe-join (dataframe-lazy users) (dataframe-lazy orders)
                     #:on '("uid") #:how 'inner)))
  ;; uids 1,1,2 match -> 3 rows; amounts 10+20+30=60
  (check-equal? (dataframe-height joined-inner) 3)
  (check-equal? (series-sum-i32 (dataframe-column joined-inner "amount")) 60)

  ;; left join keeps unmatched users (uid=3,4)
  (define joined-left
    (lazyframe-collect
     (lazyframe-join (dataframe-lazy users) (dataframe-lazy orders)
                     #:on '("uid") #:how 'left)))
  (check-equal? (dataframe-height joined-left) 5) ;; 1,1,2,3,4

  ;; #:left-on / #:right-on with differently named keys
  (define orders-r
    (dataframe-new
     (list (series-new-i32 "buyer"  '(1 1 2 5))
           (series-new-i32 "amount" '(10 20 30 40)))))
  (define joined-named
    (lazyframe-collect
     (lazyframe-join (dataframe-lazy users) (dataframe-lazy orders-r)
                     #:left-on '("uid") #:right-on '("buyer") #:how 'inner)))
  (check-equal? (dataframe-height joined-named) 3)
  (check-equal? (series-sum-i32 (dataframe-column joined-named "amount")) 60)

  ;; cross join: 4 users x 4 orders = 16
  (define joined-cross
    (lazyframe-collect
     (lazyframe-join (dataframe-lazy users) (dataframe-lazy orders)
                     #:how 'cross)))
  (check-equal? (dataframe-height joined-cross) 16)

  ;; pipeline: lazy join → group_by_agg, no intermediate collect
  (define per-user
    (lazyframe-collect
     (lazyframe-group-by-agg
      (lazyframe-join (dataframe-lazy users) (dataframe-lazy orders)
                      #:on '("uid") #:how 'inner)
      '("uid")
      (list (expr-alias (expr-sum (col "amount")) "total")))))
  (check-equal? (dataframe-height per-user) 2)
  ;; total across groups = 60
  (check-equal? (series-sum-i32 (dataframe-column per-user "total")) 60)

  ;; --- Phase A9 tests: expr cast ---

  (define df-cast
    (dataframe-new
     (list (series-new-i32 "x" '(1 2 3 4)))))

  ;; i32 -> f64
  (define cast-f64
    (dataframe-with-columns
     df-cast
     (list (expr-alias (expr-cast (col "x") 'float64) "xf"))))
  (check-equal? (series-dtype (dataframe-column cast-f64 "xf")) 'float64)
  (check-= (series-sum-f64 (dataframe-column cast-f64 "xf")) 10.0 1e-9)

  ;; i32 -> i64
  (define cast-i64
    (dataframe-with-columns
     df-cast
     (list (expr-alias (expr-cast (col "x") 'int64) "xl"))))
  (check-equal? (series-dtype (dataframe-column cast-i64 "xl")) 'int64)

  ;; i32 -> string
  (define cast-str
    (dataframe-with-columns
     df-cast
     (list (expr-alias (expr-cast (col "x") 'string) "xs"))))
  (check-equal? (series-dtype (dataframe-column cast-str "xs")) 'string)

  ;; i32 -> boolean (nonzero -> #t)
  (define cast-bool
    (dataframe-with-columns
     df-cast
     (list (expr-alias (expr-cast (col "x") 'boolean) "xb"))))
  (check-equal? (series-dtype (dataframe-column cast-bool "xb")) 'boolean)

  ;; cast inside a pipeline: literal i32 -> f64, then divide
  (define df-div
    (dataframe-with-columns
     df-cast
     (list (expr-alias (expr-div (expr-cast (col "x") 'float64)
                                 (expr-cast (lit 2) 'float64))
                       "half"))))
  (check-equal? (series-dtype (dataframe-column df-div "half")) 'float64)
  (check-= (series-sum-f64 (dataframe-column df-div "half"))
           5.0 ;; (1+2+3+4)/2
           1e-9)

  ;; datetime cast — bare symbol defaults to microseconds
  (define df-ts
    (dataframe-new
     (list (series-new-i64 "t" '(0 1000 2000 3000)))))
  (define cast-dt
    (dataframe-with-columns
     df-ts
     (list (expr-alias (expr-cast (col "t") 'datetime) "ts"))))
  (define dt-tag (series-dtype (dataframe-column cast-dt "ts")))
  (check-equal? (car dt-tag) 'datetime)
  (check-equal? (cadr dt-tag) 'microseconds)

  ;; datetime cast with explicit time unit
  (define cast-dt-ns
    (dataframe-with-columns
     df-ts
     (list (expr-alias (expr-cast (col "t") '(datetime nanoseconds)) "ts"))))
  (check-equal? (cadr (series-dtype (dataframe-column cast-dt-ns "ts")))
                'nanoseconds)

  ;; unsupported target raises (not panics)
  (check-exn exn:fail? (lambda () (expr-cast (col "x") 'no-such-dtype)))

  ;; --- Phase A10 tests: expr-std / expr-var with #:ddof ---

  (define df-stats
    (dataframe-new
     (list (series-new-i32 "g" '(1 1 1 1))
           (series-new-f64 "v" '(2.0 4.0 4.0 6.0)))))

  ;; sample std (ddof=1, default): mean=4, deviations {-2,0,0,2},
  ;; variance = (4+0+0+4)/(4-1) = 8/3, std = sqrt(8/3) ~= 1.6329932
  (define stats-default
    (dataframe-select-exprs
     df-stats
     (list (expr-alias (expr-std (col "v")) "s")
           (expr-alias (expr-var (col "v")) "v"))))
  (check-equal? (dataframe-height stats-default) 1)
  (check-= (series-sum-f64 (dataframe-column stats-default "s"))
           1.6329931618554518 1e-9)
  (check-= (series-sum-f64 (dataframe-column stats-default "v"))
           (/ 8.0 3.0) 1e-9)

  ;; population std/var (ddof=0): variance = 8/4 = 2, std = sqrt(2)
  (define stats-pop
    (dataframe-select-exprs
     df-stats
     (list (expr-alias (expr-std (col "v") #:ddof 0) "s")
           (expr-alias (expr-var (col "v") #:ddof 0) "v"))))
  (check-= (series-sum-f64 (dataframe-column stats-pop "s"))
           1.4142135623730951 1e-9)
  (check-= (series-sum-f64 (dataframe-column stats-pop "v"))
           2.0 1e-9)

  ;; std inside a group_by_agg pipeline
  (define df-grp-stats
    (dataframe-new
     (list (series-new-str "g" '("a" "a" "a" "b" "b" "b"))
           (series-new-f64 "v" '(1.0 2.0 3.0 10.0 20.0 30.0)))))
  (define grp-std
    (dataframe-group-by-agg
     df-grp-stats
     '("g")
     (list (expr-alias (expr-std (col "v")) "s"))))
  (check-equal? (dataframe-height grp-std) 2)
  ;; per-group sample std: a -> 1.0, b -> 10.0; total = 11.0
  (check-= (series-sum-f64 (dataframe-column grp-std "s")) 11.0 1e-9))
