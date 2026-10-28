#lang racket/base

;; Polars' membership / distinct predicate Expr ops: is-in (against a list,
;; Series, or Expr), is-between (#:closed), and the distinctness flags
;; is-unique / is-duplicated / is-first-distinct / is-last-distinct.  Each takes
;; an Expr or a bare column-name string (auto-lifted via col).

(require polars/private/expr
         polars/private/generic/expr-util
         (only-in racket/contract/base ->* any/c contract-out or/c))

(provide is-in
         (contract-out
          [is-between (->* (col-expr/c any/c any/c) (#:closed (or/c 'both 'left 'right 'none))
                           Expr-ptr?)])
         is-unique is-duplicated is-first-distinct is-last-distinct)

;; is-in: membership against a homogeneous Racket list, a Series, or an Expr.
(define (is-in x rhs) (expr-is-in (->col-expr 'is-in x) rhs #:who 'is-in))
;; is-between: lower..upper, #:closed 'both | 'left | 'right | 'none.
(define (is-between x lower upper #:closed [closed 'both])
  (expr-is-between (->col-expr 'is-between x) (->expr/who 'is-between lower)
                   (->expr/who 'is-between upper) #:closed closed))

(define-expr-unop is-unique         'is-unique         expr-is-unique)
(define-expr-unop is-duplicated     'is-duplicated     expr-is-duplicated)
(define-expr-unop is-first-distinct 'is-first-distinct expr-is-first-distinct)
(define-expr-unop is-last-distinct  'is-last-distinct  expr-is-last-distinct)

(module+ internal
  (provide is-between))
