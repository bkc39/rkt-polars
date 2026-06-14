#lang racket/base

;; Polars' membership / distinct predicate Expr ops: is-in (against a list,
;; Series, or Expr), is-between (#:closed), and the distinctness flags
;; is-unique / is-duplicated / is-first-distinct / is-last-distinct.  Each takes
;; an Expr or a bare column-name string (auto-lifted via col).

(require polars/private/foreign
         polars/private/expr
         polars/private/generic/expr-util)

(provide is-in is-between
         is-unique is-duplicated is-first-distinct is-last-distinct)

;; is-in: membership against a homogeneous Racket list, a Series, or an Expr.
(define (is-in x rhs) (expr-is-in (->col-expr 'is-in x) rhs))
;; is-between: lower..upper, #:closed 'both | 'left | 'right | 'none.
(define (is-between x lower upper #:closed [closed 'both])
  (expr-is-between (->col-expr 'is-between x) lower upper #:closed closed))

(define-expr-unop is-unique         'is-unique         expr-is-unique)
(define-expr-unop is-duplicated     'is-duplicated     expr-is-duplicated)
(define-expr-unop is-first-distinct 'is-first-distinct expr-is-first-distinct)
(define-expr-unop is-last-distinct  'is-last-distinct  expr-is-last-distinct)

(module+ test
  (require rackunit (only-in threading ~>)
           polars/private/generic/core
           polars/private/generic/reductions   ; alias
           polars/private/generic/reshape)     ; with-columns
  (define df (dataframe (list (series '(1 2 2 3 5 5 8) #:name "x" #:dtype 'i64))))
  (define out
    (~> df (with-columns
             (alias (is-in "x" '(2 3 8)) "in")
             (alias (is-between "x" 2 5) "btw")
             (alias (is-between "x" 2 5 #:closed 'left) "btw_l")
             (alias (is-unique "x") "uniq")
             (alias (is-duplicated "x") "dup")
             (alias (is-first-distinct "x") "first")
             (alias (is-last-distinct "x") "last"))))
  (define (c name i) (ref (ref out #:columns name) i))
  ;; x = (1 2 2 3 5 5 8)
  (check-equal? (c "in" 0) #f)      ; 1 not in (2 3 8)
  (check-equal? (c "in" 1) #t)      ; 2 in
  (check-equal? (c "btw" 1) #t)     ; 2 in [2,5]
  (check-equal? (c "btw" 4) #t)     ; 5 in [2,5]
  (check-equal? (c "btw_l" 4) #f)   ; 5 not in [2,5)
  (check-equal? (c "uniq" 0) #t)    ; 1 appears once
  (check-equal? (c "uniq" 1) #f)    ; 2 appears twice
  (check-equal? (c "dup" 1) #t)
  (check-equal? (c "first" 1) #t)   ; first 2
  (check-equal? (c "first" 2) #f)   ; second 2
  (check-equal? (c "last" 1) #f)
  (check-equal? (c "last" 2) #t))   ; last 2