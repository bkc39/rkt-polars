#lang racket/base

;; Polars' null / NaN Expr ops: fill-null / fill-nan, forward/backward fill,
;; is-null / is-not-null / is-nan / is-not-nan / is-finite / is-infinite, and
;; drop-nans.  Each takes an Expr or a bare column-name string (auto-lifted via
;; col), mirroring pl.col(x).<op>().  drop-nulls itself lives in reshape, where
;; it also covers eager series / dataframe; it accepts an Expr there too.

(require polars/private/foreign
         polars/private/expr
         polars/private/generic/expr-util)

(provide is-null is-not-null is-nan is-not-nan is-finite is-infinite
         fill-null fill-nan forward-fill backward-fill drop-nans)

(define-expr-unop is-null     'is-null     expr-is-null)
(define-expr-unop is-not-null 'is-not-null expr-is-not-null)
(define-expr-unop is-nan      'is-nan      expr-is-nan)
(define-expr-unop is-not-nan  'is-not-nan  expr-is-not-nan)
(define-expr-unop is-finite   'is-finite   expr-is-finite)
(define-expr-unop is-infinite 'is-infinite expr-is-infinite)

;; fill-null / fill-nan replace missing / NaN with a value (auto-lifted to a
;; literal); forward/backward-fill carry the last/next valid value forward or
;; back (#:limit caps how far a single run is carried).
(define (fill-null x value) (expr-fill-null (->col-expr 'fill-null x) value))
(define (fill-nan x value)  (expr-fill-nan  (->col-expr 'fill-nan x) value))
(define (forward-fill x #:limit [limit #f])
  (expr-forward-fill (->col-expr 'forward-fill x) #:limit limit))
(define (backward-fill x #:limit [limit #f])
  (expr-backward-fill (->col-expr 'backward-fill x) #:limit limit))
(define-expr-unop drop-nans 'drop-nans expr-drop-nans)

(module+ test
  (require rackunit (only-in threading ~>)
           polars/private/generic/core
           polars/private/generic/reductions   ; alias
           polars/private/generic/reshape)     ; with-columns / select / drop-nulls
  (define df
    (dataframe (list (series (list 1.0 polars-null 3.0 polars-null 5.0) #:name "x")
                     (series (list 1.0 +nan.0 3.0 +inf.0 -1.0) #:name "y"))))
  (define out
    (~> df (with-columns
             (alias (fill-null "x" 0.0) "x_filled")
             (alias (forward-fill "x") "x_ffill")
             (alias (backward-fill "x") "x_bfill")
             (alias (is-null "x") "x_is_null")
             (alias (fill-nan "y" -99.0) "y_no_nan")
             (alias (is-nan "y") "y_is_nan")
             (alias (is-finite "y") "y_is_finite")
             (alias (is-infinite "y") "y_is_inf"))))
  (check-equal? (ref (ref out #:columns "x_filled") 1) 0.0)
  (check-equal? (ref (ref out #:columns "x_ffill") 1) 1.0)
  (check-equal? (ref (ref out #:columns "x_bfill") 1) 3.0)
  (check-equal? (ref (ref out #:columns "x_is_null") 1) #t)
  (check-equal? (ref (ref out #:columns "x_is_null") 0) #f)
  (check-equal? (ref (ref out #:columns "y_no_nan") 1) -99.0)
  (check-equal? (ref (ref out #:columns "y_is_nan") 1) #t)
  (check-equal? (ref (ref out #:columns "y_is_finite") 0) #t)
  (check-equal? (ref (ref out #:columns "y_is_inf") 3) #t)
  ;; drop-nulls / drop-nans on an Expr collapse the column length (via select)
  (check-equal? (height (select df (alias (drop-nulls (col "x")) "x"))) 3)
  (check-equal? (height (select df (alias (drop-nans (col "y")) "y"))) 4))
