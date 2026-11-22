#lang racket/base

(require ffi/unsafe
         ffi/unsafe/alloc
         (only-in racket/contract/base contract-out)
         (only-in polars/private/expr-core LazyFrame-ptr? _Expr-ptr _LazyFrame-ptr
                  _LazyFrame-ptr/null define-compat explain/c lazyframe-drop lazyframe-explain)
         (only-in polars/private/expr-select ->key-expr)
         (only-in polars/private/foreign
                  DataFrame-ptr? _DataFrame-ptr _DataFrame-ptr/null call/foreign-error
                  call/polars-reason dataframe-drop frame-sort/c provide-row-windows sort-flags)
         (only-in polars/private/join-options frame-join/c join-keys join-symbol->code)
         (only-in polars/private/resource _str-list with-release))

(provide dataframe-lazy
         lazyframe-with-columns lazyframe-collect lazyframe-collect/raw
         lazyframe-filter lazyframe-select
         lazyframe-group-by-agg
         lazyframe-unique lazyframe-drop-nulls
         dataframe-with-columns dataframe-select-exprs dataframe-filter-expr
         dataframe-group-by-agg
         (contract-out
          [lazyframe-explain (explain/c LazyFrame-ptr?)]
          [lazyframe-join (frame-join/c LazyFrame-ptr? (lambda (_) LazyFrame-ptr?)
                                        (lambda (_) LazyFrame-ptr?) 'lazyframe-join/c)]
          [lazyframe-sort (frame-sort/c LazyFrame-ptr? 'lazyframe-sort/c)]
          [dataframe-sort-exprs (frame-sort/c DataFrame-ptr? 'dataframe-sort-exprs/c)]))

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

(define (dataframe-with-columns df exprs)
  (collect-plan/who 'dataframe-with-columns df (lambda (lf) (lazyframe-with-columns lf exprs))))

(define (dataframe-select-exprs df exprs)
  (collect-plan/who 'dataframe-select-exprs df (lambda (lf) (lazyframe-select lf exprs))))

(define (dataframe-filter-expr df predicate)
  (collect-plan/who 'dataframe-filter-expr df (lambda (lf) (lazyframe-filter lf predicate))))

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

(define (lazyframe-group-by-agg lf keys aggs)
  (lazyframe-group-by-agg/c lf (map ->key-expr keys) aggs))

(define (dataframe-group-by-agg df keys aggs)
  (collect-plan/who 'dataframe-group-by-agg df (lambda (lf) (lazyframe-group-by-agg lf keys aggs))))

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
  (collect-plan/who 'dataframe-sort-exprs df
                    (lambda (lf)
                      (lazyframe-sort lf names
                                      #:descending descending
                                      #:nulls-last nulls-last
                                      #:maintain-order maintain-order))))

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
  (lazyframe-join/who 'lazyframe-join left right lon ron how))

(define (lazyframe-join/who who left right lon ron how)
  (call/foreign-error who
                      (lambda () (lazyframe-join/c left right lon ron (join-symbol->code how)))))

(module+ internal
  (provide call-with-plan collect-plan/who lazyframe-collect/who lazyframe-explain lazyframe-head
           lazyframe-join lazyframe-join/who lazyframe-slice lazyframe-sort lazyframe-tail))
