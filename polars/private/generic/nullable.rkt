#lang racket/base

;; Polars' null / NaN Expr ops: fill-null / fill-nan, forward/backward fill,
;; is-null / is-not-null / is-nan / is-not-nan / is-finite / is-infinite, and
;; drop-nans.  Each takes an Expr or a bare column-name string (auto-lifted via
;; col), mirroring pl.col(x).<op>().  drop-nulls itself lives in reshape, where
;; it also covers eager series / dataframe; it accepts an Expr there too.

(require polars/private/foreign
         polars/private/expr)

(provide is-null is-not-null is-nan is-not-nan is-finite is-infinite
         fill-null fill-nan forward-fill backward-fill drop-nans)

(define (->null-expr who x)
  (cond [(Expr-ptr? x) x]
        [(string? x)   (col x)]
        [else (error who "expected an Expr or column name, got ~v" x)]))

(define (is-null x)     (expr-is-null     (->null-expr 'is-null x)))
(define (is-not-null x) (expr-is-not-null (->null-expr 'is-not-null x)))
(define (is-nan x)      (expr-is-nan      (->null-expr 'is-nan x)))
(define (is-not-nan x)  (expr-is-not-nan  (->null-expr 'is-not-nan x)))
(define (is-finite x)   (expr-is-finite   (->null-expr 'is-finite x)))
(define (is-infinite x) (expr-is-infinite (->null-expr 'is-infinite x)))

;; fill-null / fill-nan replace missing / NaN with a value (auto-lifted to a
;; literal); forward/backward-fill carry the last/next valid value forward or
;; back (#:limit caps how far a single run is carried).
(define (fill-null x value) (expr-fill-null (->null-expr 'fill-null x) value))
(define (fill-nan x value)  (expr-fill-nan  (->null-expr 'fill-nan x) value))
(define (forward-fill x #:limit [limit #f])
  (expr-forward-fill (->null-expr 'forward-fill x) #:limit limit))
(define (backward-fill x #:limit [limit #f])
  (expr-backward-fill (->null-expr 'backward-fill x) #:limit limit))
(define (drop-nans x) (expr-drop-nans (->null-expr 'drop-nans x)))

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
