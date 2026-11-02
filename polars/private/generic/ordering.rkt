#lang racket/base

(require (prefix-in base: (only-in racket/base sort))
         (only-in racket/contract/base
                  -> ->* ->i contract-out flat-named-contract
                  non-empty-listof none/c or/c procedure-arity-includes/c
                  rename-contract the-unsupplied-arg unsupplied-arg?)
         (only-in polars/private/c-integer uint64/c)
         (only-in polars/private/expr
                  Expr-ptr? expr-gather expr-rank expr-sort expr-sort-by index-list/c lazyframe-sort
                  rank-method/c)
         (only-in polars/private/expr-core sort-by/c)
         (only-in polars/private/foreign sort-flags-mismatch sort-flags/c)
         (only-in (submod polars/private/foreign internal) dataframe-sort/who series-sort/who)
         (only-in polars/private/generic/core
                  dataframe? lazyframe? series? wrap-dataframe wrap-lazyframe wrap-series)
         (only-in polars/private/generic/expr-util ->col-expr col-expr/c))

(provide (contract-out [sort sort/c]
                       [sort-by (sort-by/c col-expr/c 'sort-by/c)]
                       [rank (->* (col-expr/c)
                                  (#:method rank-method/c
                                   #:descending boolean?
                                   #:seed (or/c #f uint64/c))
                                  Expr-ptr?)]
                       [gather (-> col-expr/c (or/c Expr-ptr? series? index-list/c) Expr-ptr?)]))

(define (sort-frame? x) (or (dataframe? x) (lazyframe? x)))

(define (->keys by) (if (list? by) by (list by)))

(define sortable/c
  (flat-named-contract 'sortable/c
                       (or/c dataframe? lazyframe? series? Expr-ptr? string? list?)))
(define sort-keys/c
  (flat-named-contract 'sort-keys/c (or/c string? (non-empty-listof string?))))
(define frame-only/c (flat-named-contract 'frame-only/c none/c))
(define list-only/c (flat-named-contract 'list-only/c none/c))
(define frame-or-list-only/c (flat-named-contract 'frame-or-list-only/c none/c))
(define polars-only/c (flat-named-contract 'polars-only/c none/c))

(define (polars-flag/c x)
  (cond [(sort-frame? x) sort-flags/c]
        [(list? x) polars-only/c]
        [else boolean?]))

(define sort/c
  (rename-contract
   (->i ([x sortable/c])
        ([by (x) (cond [(sort-frame? x) sort-keys/c]
                       [(list? x) (procedure-arity-includes/c 2)]
                       [else frame-or-list-only/c])]
         #:descending [descending (x) (if (list? x) boolean? (polars-flag/c x))]
         #:nulls-last [nulls-last (x) (polars-flag/c x)]
         #:maintain-order [maintain-order (x) (if (sort-frame? x) boolean? frame-only/c)]
         #:key [extract-key (x)
                            (if (list? x) (or/c #f (procedure-arity-includes/c 1)) list-only/c)]
         #:cache-keys? [cache-keys? (x) (if (list? x) boolean? list-only/c)])
        #:pre/desc (x by descending nulls-last)
        (cond [(and (sort-frame? x) (unsupplied-arg? by))
               "sorting a dataframe or lazyframe needs sort keys"]
              [(and (list? x) (unsupplied-arg? by))
               "racket/base sort needs a less-than? procedure"]
              [(sort-frame? x) (sort-flags-mismatch by descending nulls-last)]
              [else #t])
        [result (x) (cond [(dataframe? x) dataframe?]
                          [(lazyframe? x) lazyframe?]
                          [(series? x) series?]
                          [(list? x) list?]
                          [else Expr-ptr?])])
   'sort/c))

(define (sort x [by the-unsupplied-arg]
              #:descending [descending #f]
              #:nulls-last [nulls-last #f]
              #:maintain-order [maintain-order #f]
              #:key [extract-key #f]
              #:cache-keys? [cache-keys? #f])
  (cond
    [(dataframe? x)
     (wrap-dataframe
      (dataframe-sort/who 'sort x (->keys by) descending nulls-last maintain-order))]
    [(lazyframe? x)
     (wrap-lazyframe
      (lazyframe-sort x (->keys by) #:descending descending #:nulls-last nulls-last
                      #:maintain-order maintain-order))]
    [(series? x)
     (wrap-series (series-sort/who 'sort x descending nulls-last))]
    [(list? x)
     (base:sort x (if descending (lambda (a b) (by b a)) by)
                #:key extract-key #:cache-keys? cache-keys?)]
    [else
     (expr-sort (->col-expr 'sort x) #:descending descending #:nulls-last nulls-last)]))

(define (sort-by x #:by by
                 #:descending [descending #f]
                 #:nulls-last [nulls-last #f]
                 #:maintain-order [maintain-order #f])
  (expr-sort-by (->col-expr 'sort-by x) #:by by #:descending descending
                #:nulls-last nulls-last #:maintain-order maintain-order))

;; rank: #:method 'average | 'min | 'max | 'dense | 'ordinal, #:descending, #:seed.
(define (rank x #:method [method 'average] #:descending [descending #f] #:seed [seed #f])
  (expr-rank (->col-expr 'rank x) #:method method #:descending descending #:seed seed))

(define (gather x indices)
  (expr-gather (->col-expr 'gather x) indices))

(module+ internal
  (provide rank sort sort-by))
