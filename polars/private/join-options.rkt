#lang racket/base

(require (only-in racket/contract/base
                  ->i and/c non-empty-listof not/c or/c rename-contract unsupplied-arg?)
         racket/match
         (only-in polars/private/c-integer int64/c)
         (only-in polars/private/resource utf-8-name/c utf-8-names/c))

(provide asof-keys asof-strategy-symbol->code asof-tolerance->parts frame-join-asof/c
         frame-join/c join-keys join-symbol->code)

(define join-kind-codes
  (hasheq 'inner 1 'left 2 'outer 3 'full 3 'cross 4 'semi 5 'anti 6))

(define join-how/c (apply or/c (hash-keys join-kind-codes #t)))

(define (join-symbol->code how)
  (hash-ref join-kind-codes how))

(define (supplied v)
  (and (not (unsupplied-arg? v)) v))

(define (join-keys how on left-on right-on)
  (cond
    [(eq? (supplied how) 'cross) (values '() '())]
    [(supplied on) (values on on)]
    [else (values left-on right-on)]))

(define (join-keys-given how on left-on right-on)
  (or (eq? (supplied how) 'cross)
      (and (supplied on) #t)
      (and (supplied left-on) (supplied right-on) #t)
      "must supply #:on, or #:left-on and #:right-on"))

(define join-keys/c (or/c #f (non-empty-listof utf-8-name/c)))

(define (frame-join/c left/c right/c-of result/c-of name)
  (rename-contract
   (->i ([left left/c] [right (left) (right/c-of left)])
        (#:on [on join-keys/c]
         #:left-on [left-on join-keys/c]
         #:right-on [right-on join-keys/c]
         #:how [how join-how/c])
        #:pre/desc (how on left-on right-on) (join-keys-given how on left-on right-on)
        [result (left) (result/c-of left)])
   name))

(define asof-strategy-codes (hasheq 'backward 1 'forward 2 'nearest 3))

(define asof-strategy/c (apply or/c (hash-keys asof-strategy-codes #t)))

(define (asof-strategy-symbol->code strategy)
  (hash-ref asof-strategy-codes strategy))

(define compat-asof-tolerance/none    0)
(define compat-asof-tolerance/integer 1)
(define compat-asof-tolerance/float   2)

(define asof-tolerance/c (or/c #f int64/c (and/c real? (not/c exact-integer?))))

(define (asof-tolerance->parts tolerance)
  (match tolerance
    [#f (values compat-asof-tolerance/none 0 0.0)]
    [(? exact-integer?) (values compat-asof-tolerance/integer tolerance 0.0)]
    [_ (values compat-asof-tolerance/float 0 (exact->inexact tolerance))]))

(define (asof-by-given by left-by right-by)
  (match* ((supplied by) (supplied left-by) (supplied right-by))
    [(#f #f #f) #t]
    [(_ #f #f) #t]
    [(#f (? list? l) (? list? r))
     (or (= (length l) (length r))
         (format "#:left-by has ~a names and #:right-by ~a; they must be equal"
                 (length l) (length r)))]
    [(#f _ _) "must supply both #:left-by and #:right-by"]
    [(_ _ _) "supply either #:by or #:left-by and #:right-by, not both"]))

(define (asof-on-given on left-on right-on)
  (or (and (supplied on) #t)
      (and (supplied left-on) (supplied right-on) #t)
      "must supply #:on, or #:left-on and #:right-on"))

(define (frame-join-asof/c frame/c name)
  (rename-contract
   (->i ([left frame/c] [right frame/c])
        (#:on [on (or/c #f utf-8-name/c)]
         #:left-on [left-on (or/c #f utf-8-name/c)]
         #:right-on [right-on (or/c #f utf-8-name/c)]
         #:by [by (or/c #f utf-8-names/c)]
         #:left-by [left-by (or/c #f utf-8-names/c)]
         #:right-by [right-by (or/c #f utf-8-names/c)]
         #:strategy [strategy asof-strategy/c]
         #:tolerance [tolerance asof-tolerance/c])
        #:pre/desc (on left-on right-on) (asof-on-given on left-on right-on)
        #:pre/desc (by left-by right-by) (asof-by-given by left-by right-by)
        [result frame/c])
   name))

(define (asof-keys on left-on right-on by left-by right-by)
  (values (or on left-on) (or on right-on) (or by left-by '()) (or by right-by '())))
