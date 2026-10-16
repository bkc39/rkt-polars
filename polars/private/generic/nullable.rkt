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
           polars/private/generic/reshape      ; with-columns / select / drop-nulls
           (only-in racket/list make-list)
           (only-in polars/private/bulk series->list)
           (only-in polars/private/generic/ordering sort))
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
  (check-equal? (~> df (select (fill-null "x" polars-null)) (ref "x") series->list)
                (list 1.0 polars-null 3.0 polars-null 5.0))
  (define broadcast (~> df (with-columns (alias (lit polars-null) "n")) (ref "n")))
  (check-equal? (list (dtype broadcast) (series->list broadcast))
                (list 'null (make-list 5 polars-null)))
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
  (check-equal? (height (select df (alias (drop-nans (col "y")) "y"))) 4)
  (define nulls (series (list polars-null polars-null) #:name "n"))
  (check-equal? (map (lambda (reduce) (reduce nulls)) (list sum mean min max std var))
                (make-list 6 polars-null))
  (check-equal? (list (n-unique nulls) (null-count nulls) (len nulls)) '(1 2 2))
  (define anchored (series (list polars-null polars-null) #:name "^x$"))
  (check-equal? (map (lambda (reduce) (reduce anchored)) (list sum mean min max std var))
                (make-list 6 polars-null))
  (check-equal? (map (lambda (reduce) (reduce (series '("b" "a") #:name "^x$"))) (list min max))
                '("a" "b"))
  (check-equal? (mean (series '(#t #f #t #t) #:name "^x$")) 0.75)
  (define null-frame (dataframe (list (series '(a b a) #:name "g")
                                      (series (list polars-null polars-null polars-null)
                                              #:name "n"))))
  (define (column-of d name)
    (define s (ref d name))
    (list (dtype s) (series->list s)))
  (for ([reduce (list sum mean min max median first last std var)])
    (check-equal? (column-of (select null-frame (reduce "n")) "n")
                  (list 'null (list polars-null))
                  (format "~a" (object-name reduce))))
  (define counted (select null-frame (count "n") (alias (n-unique "n") "u")))
  (check-equal? (map (lambda (name) (column-of counted name)) '("n" "u"))
                (list (list 'uint32 '(0)) (list 'uint32 '(1))))
  (check-equal? (sum (series (list polars-null))) polars-null)
  (check-equal? (column-of (~> null-frame (group-by "g") (agg (sum "n")) (sort "g")) "n")
                (list 'null (list polars-null polars-null)))
  (check-equal? (column-of (select null-frame (fill-null "n" 0)) "n") (list 'int32 '(0 0 0)))
  (check-equal? (column-of (select null-frame (cast "n" 'int64)) "n")
                (list 'int64 (list polars-null polars-null polars-null)))
  (check-equal? (column-of (select null-frame (is-null "n")) "n") (list 'boolean '(#t #t #t)))
  (check-equal? (map (lambda (s) (list (series-dtype s) (series-len s)))
                     (list (sort nulls) (unique nulls)))
                '((null 2) (null 1))))
