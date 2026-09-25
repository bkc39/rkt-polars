#lang racket/base

;; Shared Expr / LazyFrame FFI plumbing and scalar leaves.

(require ffi/unsafe
         ffi/unsafe/alloc
         ffi/unsafe/define
         ffi/unsafe/define/conventions
         (only-in racket/contract
                  [-> ->/c] any/c contract-out non-empty-listof or/c)
         racket/runtime-path
         (only-in polars/private/foreign ->compat-dtype _CompatDType _rsstring)
         (only-in polars/private/generic/dtype dtype-spec? normalize-dtype))

(provide (contract-out [expr->string (->/c Expr-ptr? string?)])
         define-compat
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

(struct expr ([ptr #:mutable])
  #:property prop:cpointer (lambda (e) (expr-ptr e))
  #:property prop:custom-write
  (lambda (e port mode)
    (write-string (if (expr-ptr e) (expr->string e) "#<expr: dropped>") port)))

(define (wrap-expr p) (and p (expr p)))

(define-cpointer-type _Expr-ptr _pointer #f wrap-expr)
(define-cpointer-type _LazyFrame-ptr)

(define-compat expr-drop/raw
  (_fun _Expr-ptr -> _void)
  #:c-id expr_drop
  #:wrap (deallocator))

(define (expr-drop e)
  (expr-drop/raw e)
  (set-expr-ptr! e #f))

(define-compat expr-drop-count
  (_fun -> _size))

(define-compat lazyframe-drop
  (_fun _LazyFrame-ptr -> _void)
  #:wrap (deallocator))

(define-compat expr->string
  (_fun _Expr-ptr -> _rsstring)
  #:c-id expr_to_string)

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
  (require rackunit)
  (define-compat expr-add
    (_fun _Expr-ptr _Expr-ptr -> _Expr-ptr)
    #:wrap (allocator expr-drop))
  (define-compat expr-mul
    (_fun _Expr-ptr _Expr-ptr -> _Expr-ptr)
    #:wrap (allocator expr-drop))
  (define print-col (col "x"))
  (check-equal? (expr->string print-col) "col(\"x\")")
  (check-equal? (format "~a" print-col) "col(\"x\")")
  (check-equal? (format "~s" print-col) "col(\"x\")")
  (check-equal? (format "~v" print-col) "col(\"x\")")
  (check-equal? (expr->string (expr-add (col "a") (col "b")))
                "[(col(\"a\")) + (col(\"b\"))]")
  (check-equal? (expr->string (expr-alias (col "a") "b")) "col(\"a\").alias(\"b\")")
  (check-equal? (expr->string (expr-mul (col "v") (lit 10))) "[(col(\"v\")) * (dyn int: 10)]")
  (check-equal? (expr->string (lit "hi")) "String(hi)")
  (check-equal? (expr->string (lit #t)) "true")
  (check-pred Expr-ptr? print-col)
  (check-true (cpointer? print-col))
  (check-pred Expr-ptr? (expr-alias print-col "y"))
  (check-false (equal? (col "x") (col "x")))
  (define dropped (col "d"))
  (expr-drop dropped)
  (check-equal? (format "~a" dropped) "#<expr: dropped>")
  (check-exn exn:fail? (lambda () (expr-alias dropped "e")))
  (check-exn exn:fail? (lambda () (expr-drop dropped)))
  (define drop-before (expr-drop-count))
  (for ([_ (in-range 100)])
    (void (expr-alias (col "g") "h")))
  (for ([_ (in-range 10)])
    (collect-garbage)
    (sleep 0.01))
  (check-true (>= (- (expr-drop-count) drop-before) 200)))
