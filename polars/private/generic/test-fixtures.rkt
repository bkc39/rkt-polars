#lang racket/base

;; Shared fixtures for the polars/private/generic/* test submodules.  Requires
;; the wrapper core directly (not the aggregator) so a test submodule can depend
;; on it without a module cycle; re-exports the handful of low-level names the
;; tests reach for (col / Expr-ptr? / expr-add / polars-null? / datetime).

(require polars/private/generic/core
         (only-in polars/private/expr col Expr-ptr? expr-add)
         (only-in polars/private/foreign polars-null polars-null?)
         (only-in gregor datetime))

(provide (all-defined-out)
         col Expr-ptr? expr-add polars-null polars-null? datetime)

(define ints   (series '(1 2 3 4) #:name "ints" #:dtype 'i32))
(define floats (series '(1.5 2.0 4.25 8.0) #:name "floats"))
(define withnull (series (list 10 polars-null 30) #:dtype 'i32))

(define frame
  (dataframe (list (series '("alice" "bob" "carol") #:name "user")
                   (series '(10 25 18) #:name "score" #:dtype 'i32)
                   (series '(1.2 3.5 2.0) #:name "cost"))))

(define ops-df
  (dataframe (list (series '("a" "a" "b" "b" "c") #:name "group")
                   (series '(10 25 7 30 18) #:name "value" #:dtype 'i32)
                   (series '(1.2 2.4 0.5 3.1 1.8) #:name "cost"))))

(define v64 (series '(10 25 7 30 18) #:name "value"))   ; int64 (default)
