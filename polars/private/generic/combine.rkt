#lang racket/base

(require (only-in racket/contract/base -> contract-out or/c)
         racket/match
         (only-in polars/private/expr lazyframe-join)
         (only-in (submod polars/private/foreign internal)
                  dataframe-hstack/who dataframe-join-asof/who dataframe-join/who
                  dataframe-vstack/who)
         (only-in polars/private/join-options asof-keys frame-join-asof/c frame-join/c join-keys)
         (only-in polars/private/generic/core
                  dataframe? lazyframe? series? wrap-dataframe wrap-lazyframe))

(provide (contract-out
          [join (frame-join/c (or/c dataframe? lazyframe?) same-kind/c same-kind/c 'join/c)]
          [join-asof (frame-join-asof/c dataframe? 'join-asof/c)]
          [vstack (-> dataframe? dataframe? dataframe?)]
          [hstack (-> dataframe? series? ... dataframe?)]))

(define (same-kind/c left)
  (if (dataframe? left) dataframe? lazyframe?))

(define (join left right
              #:on [on #f] #:left-on [left-on #f] #:right-on [right-on #f]
              #:how [how 'inner])
  (match left
    [(? dataframe?)
     (define-values (lon ron) (join-keys how on left-on right-on))
     (wrap-dataframe (dataframe-join/who 'join left right lon ron how))]
    [_ (wrap-lazyframe
        (lazyframe-join left right #:on on #:left-on left-on #:right-on right-on #:how how))]))

(define (join-asof left right
                   #:on [on #f] #:left-on [left-on #f] #:right-on [right-on #f]
                   #:by [by #f] #:left-by [left-by #f] #:right-by [right-by #f]
                   #:strategy [strategy 'backward] #:tolerance [tolerance #f])
  (define-values (lon ron lby rby) (asof-keys on left-on right-on by left-by right-by))
  (wrap-dataframe
   (dataframe-join-asof/who 'join-asof left right lon ron lby rby strategy tolerance)))

(define (vstack top bottom)
  (wrap-dataframe (dataframe-vstack/who 'vstack top bottom)))

(define (hstack d . columns)
  (wrap-dataframe (dataframe-hstack/who 'hstack d columns)))

(module+ internal
  (provide hstack join join-asof vstack))
