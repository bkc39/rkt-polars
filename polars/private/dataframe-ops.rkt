#lang racket/base

(require ffi/unsafe
         ffi/unsafe/alloc
         (only-in racket/contract/base ->i contract-out flat-named-contract listof
                  non-empty-listof or/c rename-contract)
         (only-in racket/provide matching-identifiers-out)
         syntax/parse/define
         (only-in polars/private/compat-ffi define-compat)
         (only-in polars/private/owned DataFrame-ptr? _DataFrame-ptr _DataFrame-ptr/null)
         (only-in polars/private/reason call/foreign-error call/polars-reason)
         (only-in (submod polars/private/dataframe-core internal) define-frame-op/reason)
         (only-in (submod polars/private/owned internal) dataframe-drop)
         (only-in polars/private/join-options
                  asof-keys asof-strategy-symbol->code asof-tolerance->parts frame-join-asof/c
                  frame-join/c join-keys join-symbol->code)
         (only-in polars/private/resource _str _str-list)
         (for-syntax racket/base racket/syntax syntax/parse))

(provide (except-out (all-defined-out)
                     dataframe-join dataframe-join-asof dataframe-sort
                     (matching-identifiers-out #rx"^dataframe-.*/who$" (all-defined-out)))
         (contract-out
          [dataframe-join (frame-join/c DataFrame-ptr? (lambda (_) DataFrame-ptr?)
                                        (lambda (_) DataFrame-ptr?) 'dataframe-join/c)]
          [dataframe-join-asof (frame-join-asof/c DataFrame-ptr? 'dataframe-join-asof/c)]
          [dataframe-sort (frame-sort/c DataFrame-ptr? 'dataframe-sort/c)]))

(define-compat dataframe-sort/raw
  (_fun _DataFrame-ptr
        (names : _str-list)
        (descending : (_list i _stdbool))
        (nulls-last : (_list i _stdbool))
        (_size = (length names))
        (maintain-order : _stdbool)
        -> _DataFrame-ptr/null)
  #:c-id dataframe_sort_with_options_v2
  #:wrap (allocator dataframe-drop))

(define sort-flags/c
  (flat-named-contract 'sort-flags/c (or/c boolean? (listof boolean?))))

(define (sort-flags-mismatch keys descending nulls-last)
  (define n (if (list? keys) (length keys) 1))
  (or (for/first ([flags (in-list (list descending nulls-last))]
                  [keyword (in-list '("#:descending" "#:nulls-last"))]
                  #:when (and (list? flags) (not (= (length flags) n))))
        (format "the length of ~a (~a) does not match the number of sort keys (~a)"
                keyword (length flags) n))
      #t))

(define (frame-sort/c frame? name)
  (rename-contract
   (->i ([frame frame?] [names (non-empty-listof string?)])
        (#:descending [descending sort-flags/c]
         #:nulls-last [nulls-last sort-flags/c]
         #:maintain-order [maintain-order boolean?])
        #:pre/desc (names descending nulls-last)
        (sort-flags-mismatch names descending nulls-last)
        [result frame?])
   name))

;; the raw bindings read (length names) flags from each list: never pass a shorter one
(define (sort-flags who keyword flags keys)
  (cond
    [(boolean? flags) (for/list ([_ (in-list keys)]) flags)]
    [(= (length flags) (length keys)) flags]
    [else (raise-arguments-error who (format "~a needs one flag per sort key" keyword)
                                 keyword flags
                                 "keys" keys)]))

(define (dataframe-sort/who who df names descending nulls-last maintain-order)
  (define flags (sort-flags who "#:descending" descending names))
  (define nulls (sort-flags who "#:nulls-last" nulls-last names))
  (call/polars-reason who (lambda () (dataframe-sort/raw df names flags nulls maintain-order))))

(define (dataframe-sort df names
                        #:descending [descending #f]
                        #:nulls-last [nulls-last #f]
                        #:maintain-order [maintain-order #f])
  (dataframe-sort/who 'dataframe-sort df names descending nulls-last maintain-order))

(define-syntax-parse-rule (define-group-by-agg agg:id)
  #:with name (format-id #'agg "dataframe-group-by-~a" #'agg)
  #:with raw (format-id #'agg "dataframe-group-by-~a/c" #'agg)
  #:with rust-id (format-id #'agg "dataframe_group_by_~a_v2" #'agg)
  (begin
    (define-compat raw
      (_fun _DataFrame-ptr _str-list _str-list -> _DataFrame-ptr/null)
      #:c-id rust-id
      #:wrap (allocator dataframe-drop))
    (define (name df #:by by #:agg agg)
      (call/polars-reason 'name (lambda () (raw df by agg))))))

(define-group-by-agg sum)
(define-group-by-agg mean)
(define-group-by-agg min)
(define-group-by-agg max)
(define-group-by-agg count)

(define-frame-op/reason (dataframe-join left right left-on right-on how)
  (dataframe-join/c left right left-on right-on (join-symbol->code how))
  (define-compat dataframe-join/c
    (_fun _DataFrame-ptr _DataFrame-ptr _str-list _str-list _int32 -> _DataFrame-ptr/null)
    #:c-id dataframe_join_v2
    #:wrap (allocator dataframe-drop)))

(define (dataframe-join left right
                        #:on [on #f]
                        #:left-on [left-on #f]
                        #:right-on [right-on #f]
                        #:how [how 'inner])
  (define-values (lon ron) (join-keys how on left-on right-on))
  (dataframe-join/who 'dataframe-join left right lon ron how))

(define-compat dataframe-join-asof/raw
  (_fun _DataFrame-ptr _DataFrame-ptr _str _str _int32 -> _DataFrame-ptr/null)
  #:c-id dataframe_join_asof_v2
  #:wrap (allocator dataframe-drop))

(define-frame-op/reason (dataframe-join-asof left right left-on right-on left-by right-by
                                             strategy tolerance)
  (let-values ([(kind integer float) (asof-tolerance->parts tolerance)])
    (dataframe-join-asof-options/raw left right left-on right-on
                                     (asof-strategy-symbol->code strategy)
                                     left-by right-by kind integer float))
  (define-compat dataframe-join-asof-options/raw
    (_fun _DataFrame-ptr _DataFrame-ptr _str _str _int32 _str-list _str-list _int32 _int64 _double
          -> _DataFrame-ptr/null)
    #:c-id dataframe_join_asof_options_v2
    #:wrap (allocator dataframe-drop)))

(define (dataframe-join-asof left right
                             #:on [on #f]
                             #:left-on [left-on #f]
                             #:right-on [right-on #f]
                             #:by [by #f]
                             #:left-by [left-by #f]
                             #:right-by [right-by #f]
                             #:strategy [strategy 'backward]
                             #:tolerance [tolerance #f])
  (define-values (lon ron lby rby) (asof-keys on left-on right-on by left-by right-by))
  (dataframe-join-asof/who 'dataframe-join-asof left right lon ron lby rby strategy tolerance))

(define compat-pivot-agg/none  0)
(define compat-pivot-agg/first 1)
(define compat-pivot-agg/sum   2)
(define compat-pivot-agg/min   3)
(define compat-pivot-agg/max   4)
(define compat-pivot-agg/mean  5)
(define compat-pivot-agg/count 6)

(define (pivot-agg-symbol->code sym)
  (case sym
    [(none #f) compat-pivot-agg/none]
    [(first)   compat-pivot-agg/first]
    [(sum)     compat-pivot-agg/sum]
    [(min)     compat-pivot-agg/min]
    [(max)     compat-pivot-agg/max]
    [(mean)    compat-pivot-agg/mean]
    [(count)   compat-pivot-agg/count]
    [else (error 'dataframe-pivot
                 "unknown pivot aggregation ~v (expected #f 'first 'sum 'min 'max 'mean 'count)"
                 sym)]))

(define-compat dataframe-pivot/raw
  (_fun _DataFrame-ptr _str-list _str-list _str-list _int32 -> _DataFrame-ptr/null)
  #:c-id dataframe_pivot_v2
  #:wrap (allocator dataframe-drop))

(define (pivot-frame who df on index values agg)
  (call/foreign-error who
                      (lambda () (dataframe-pivot/raw df on index values (pivot-agg-symbol->code agg)))
                      "cannot pivot the dataframe"))

(define (dataframe-pivot df #:on on #:index index #:values values
                         #:agg [agg 'first])
  (pivot-frame 'dataframe-pivot df on index values agg))

(define-compat dataframe-unpivot/raw
  (_fun _DataFrame-ptr _str-list _str-list -> _DataFrame-ptr/null)
  #:c-id dataframe_unpivot_v2
  #:wrap (allocator dataframe-drop))

(define (unpivot-frame who df on index)
  (call/foreign-error who (lambda () (dataframe-unpivot/raw df on index))
                      "cannot unpivot the dataframe"))

(define (dataframe-unpivot df #:on on #:index index)
  (unpivot-frame 'dataframe-unpivot df on index))

(module+ internal
  (provide dataframe-join dataframe-join-asof dataframe-join-asof/who dataframe-join/who
           dataframe-sort dataframe-sort/who))
