#lang racket/base

;; Polars' cumulative / sequential Expr ops: cum-sum / cum-prod / cum-min /
;; cum-max / cum-count (each #:reverse), shift (#:n, #:fill-value), and diff
;; (#:n, #:null-behavior).  Each takes an Expr or a bare column-name string
;; (auto-lifted via col).

(require (only-in racket/contract/base ->* any/c contract-out)
         (only-in polars/private/c-integer int64/c)
         polars/private/expr
         polars/private/generic/expr-util)

(provide cum-sum cum-prod cum-min cum-max cum-count
         (contract-out
          [shift (->* (col-expr/c) (#:n int64/c #:fill-value any/c) Expr-ptr?)]
          [diff (->* (col-expr/c) (#:n int64/c #:null-behavior null-behavior/c)
                     Expr-ptr?)]))

(define (cum-sum x #:reverse [reverse #f])
  (expr-cum-sum (->col-expr 'cum-sum x) #:reverse reverse))
(define (cum-prod x #:reverse [reverse #f])
  (expr-cum-prod (->col-expr 'cum-prod x) #:reverse reverse))
(define (cum-min x #:reverse [reverse #f])
  (expr-cum-min (->col-expr 'cum-min x) #:reverse reverse))
(define (cum-max x #:reverse [reverse #f])
  (expr-cum-max (->col-expr 'cum-max x) #:reverse reverse))
(define (cum-count x #:reverse [reverse #f])
  (expr-cum-count (->col-expr 'cum-count x) #:reverse reverse))

;; shift rows by #:n (positive = later, negative = earlier); #:fill-value fills
;; the vacated slots instead of null.  diff takes successive differences over a
;; lag of #:n, with #:null-behavior 'ignore | 'drop.
(define (shift x #:n [n 1] #:fill-value [fill-value #f])
  (expr-shift (->col-expr 'shift x) #:n n
              #:fill-value (and fill-value (->expr/who 'shift fill-value))))
(define (diff x #:n [n 1] #:null-behavior [null-behavior 'ignore])
  (expr-diff (->col-expr 'diff x) #:n n #:null-behavior null-behavior))

(module+ internal
  (provide diff shift))
