#lang racket/base

(require polars/private/facade)

(define-facade
  #:parts ((except-in polars/private/expr-core lazyframe-explain) polars/private/expr-dt
           polars/private/expr-ops polars/private/expr-select polars/private/expr-str
           polars/private/lazyframe)
  #:hide (_Expr-ptr/null _LazyFrame-ptr/null define-compat drop-owned explain/c expr-drop-count
          expr-dropped expr-dt-convert-time-zone expr-dt-replace-time-zone expr-lit-null
          lazyframe-drop-count lazyframe-dropped lazyframe-explain/who lit-integer/c
          parse-datetime sort-by/c time-unit/c)
  #:internal-parts (polars/private/expr-ops polars/private/expr-select polars/private/lazyframe))
