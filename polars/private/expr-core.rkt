#lang racket/base

;; Shared Expr / LazyFrame FFI plumbing and scalar leaves.

(require ffi/unsafe
         ffi/unsafe/alloc
         ffi/unsafe/define
         ffi/unsafe/define/conventions
         (only-in racket/contract
                  [-> ->/c] any/c contract-out non-empty-listof or/c)
         racket/runtime-path
         (only-in polars/private/foreign ->compat-dtype _CompatDType)
         (only-in polars/private/generic/dtype dtype-spec? normalize-dtype))

(provide define-compat
         _Expr-ptr _Expr-ptr/null Expr-ptr?
         _LazyFrame-ptr LazyFrame-ptr?
         expr-drop lazyframe-drop
         expr-col expr-lit-i32 expr-lit-i64 expr-lit-f64 expr-lit-bool expr-lit-str
         expr-alias
         lit ->expr
         dtype-spec?
         (contract-out
          [col (->/c (or/c string? regexp? dtype-spec?) Expr-ptr?)]
          [expr-all (->/c Expr-ptr?)]
          [expr-dtype-col (->/c dtype-spec? Expr-ptr?)]
          [expr-exclude (->/c multi-column-expr?
                              (non-empty-listof (or/c string? regexp?))
                              Expr-ptr?)]
          [multi-column-expr? (->/c any/c boolean?)]))

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

(define (->column-pattern v)
  (if (regexp? v)
      (string-append "^.*(?:" (object-name v) ").*$")
      v))

(define-compat expr-all
  (_fun -> _Expr-ptr)
  #:wrap (allocator expr-drop))

(define-compat expr-multi-column/raw
  (_fun _Expr-ptr -> _uint8)
  #:c-id expr_multi_column)

(define (multi-column-expr? v)
  (and (Expr-ptr? v) (= 1 (expr-multi-column/raw v))))

(define-compat expr-exclude/raw
  (_fun _Expr-ptr
        (names : (_list i _string))
        (_size = (length names))
        -> _Expr-ptr/null)
  #:c-id expr_exclude
  #:wrap (allocator expr-drop))

(define-compat expr-dtype-col/raw
  (_fun _CompatDType -> _Expr-ptr/null)
  #:c-id expr_dtype_col
  #:wrap (allocator expr-drop))

(define (expr-exclude e names)
  (or (expr-exclude/raw e (map ->column-pattern names))
      (error 'expr-exclude "operation failed")))

(define (expr-dtype-col dtype)
  (or (expr-dtype-col/raw (->compat-dtype (normalize-dtype dtype)))
      (error 'expr-dtype-col "operation failed")))

(define (col spec)
  (if (dtype-spec? spec)
      (expr-dtype-col spec)
      (expr-col (->column-pattern spec))))

(define (->expr v)
  (if (Expr-ptr? v) v (lit v)))

(module+ test
  (require rackunit (prefix-in contracted: (submod "..")))
  (check-equal? (->column-pattern #rx"^sepal_") "^.*(?:^sepal_).*$")
  (check-equal? (->column-pattern #px"\\d+") "^.*(?:\\d+).*$")
  (check-equal? (->column-pattern "^a$") "^a$")
  (check-pred Expr-ptr? (expr-all))
  (check-pred Expr-ptr? (expr-dtype-col 'float64))
  (check-pred Expr-ptr? (expr-dtype-col 'f64))
  (check-pred Expr-ptr? (expr-dtype-col '(duration nanoseconds)))
  (check-pred Expr-ptr? (expr-exclude (expr-all) '("a")))
  (check-pred Expr-ptr? (expr-exclude (expr-dtype-col 'int32) (list "a" #rx"^b")))
  (check-pred Expr-ptr? (expr-exclude (expr-col "^a.*$") '("ab")))
  (check-true (multi-column-expr? (expr-all)))
  (check-true (multi-column-expr? (expr-dtype-col 'string)))
  (check-true (multi-column-expr? (col #rx"x")))
  (check-true (multi-column-expr? (expr-alias (expr-all) "y")))
  (check-false (multi-column-expr? (expr-col "a")))
  (check-false (multi-column-expr? (lit 1)))
  (check-false (multi-column-expr? "a"))
  (check-exn #rx"^expr-exclude: contract violation\n  expected: multi-column-expr\\?"
             (lambda () (contracted:expr-exclude (expr-col "a") '("b"))))
  (check-exn #rx"^expr-exclude: contract violation"
             (lambda () (contracted:expr-exclude (expr-all) '())))
  (check-exn #rx"^expr-dtype-col: contract violation"
             (lambda () (contracted:expr-dtype-col 'list)))
  (check-exn #rx"^col: contract violation\n  expected: \\(or/c string\\? regexp\\? dtype-spec\\?\\)\n  given: 42"
             (lambda () (contracted:col 42)))
  (check-exn #rx"^col: contract violation" (lambda () (contracted:col 'list)))
  (check-exn #rx"^col: contract violation" (lambda () (contracted:col #rx#"bytes")))
  (check-exn #rx"^col: contract violation" (lambda () (contracted:col '(datetime weeks))))
  (check-exn #rx"^col: contract violation"
             (lambda () (contracted:col '(datetime microseconds "UTC")))))
