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
                  DataFrame-ptr?))

(module+ test
  (require rackunit
           (only-in polars/private/foreign
                    series-new-i32
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
         dataframe-lazy
         lazyframe-with-columns lazyframe-collect
         lazyframe-filter lazyframe-select
         lazyframe-group-by-agg
         dataframe-with-columns dataframe-select-exprs dataframe-filter-expr
         dataframe-group-by-agg)

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
  (check-equal? (dataframe-height grouped/expr-key) 2))
