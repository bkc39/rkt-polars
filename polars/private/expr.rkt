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

(provide (all-defined-out))

(define-runtime-path native-libs-dir "../native-libs")

(define-ffi-definer define-compat
  (ffi-lib (build-path native-libs-dir "libcompat"))
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
  (check-pred Expr-ptr? (col "x")))
