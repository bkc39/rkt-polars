#lang racket/base

;; Polars' `.dt` namespace: calendar/clock field extraction from a datetime Expr.
;; Each mirrors pl.col(x).dt.<method>().  The first argument is the column to
;; operate on; a bare column-name string is auto-lifted via `col`, so both
;;   (dt-year (col "ts"))  and  (dt-year "ts")
;; work.  The `dt-` prefix is the Lisp realization of Polars' `.dt` namespace:
;; uniform with the `str-` namespace and collision-safe (e.g. the upcoming
;; dt-date / dt-time would otherwise clash with gregor's date and racket/base's
;; time).

(require polars/private/foreign
         polars/private/expr)

(provide dt-year dt-month dt-day dt-hour dt-minute dt-second)

;; Lift a column-name string to an Expr; pass an Expr through unchanged.
(define (->dt-expr who x)
  (cond [(Expr-ptr? x) x]
        [(string? x)   (col x)]
        [else (error who "expected an Expr or column name, got ~v" x)]))

(define (dt-year x)   (expr-dt-year   (->dt-expr 'dt-year x)))
(define (dt-month x)  (expr-dt-month  (->dt-expr 'dt-month x)))
(define (dt-day x)    (expr-dt-day    (->dt-expr 'dt-day x)))
(define (dt-hour x)   (expr-dt-hour   (->dt-expr 'dt-hour x)))
(define (dt-minute x) (expr-dt-minute (->dt-expr 'dt-minute x)))
(define (dt-second x) (expr-dt-second (->dt-expr 'dt-second x)))

(module+ test
  (require rackunit (only-in threading ~>)
           (only-in gregor datetime)
           polars/private/generic/core
           polars/private/generic/reductions   ; alias
           polars/private/generic/reshape)     ; with-columns
  (define df
    (dataframe (list (series (list (datetime 2024 1 2 8 30 5)) #:name "ts"))))
  (define out
    (~> df
        (with-columns
          (alias (dt-year "ts") "year")
          (alias (dt-month "ts") "month")
          (alias (dt-day "ts") "day")
          (alias (dt-hour "ts") "hour")
          (alias (dt-minute "ts") "minute")
          (alias (dt-second "ts") "second"))))
  (check-equal? (ref (ref out #:columns "year") 0) 2024)
  (check-equal? (ref (ref out #:columns "month") 0) 1)
  (check-equal? (ref (ref out #:columns "day") 0) 2)
  (check-equal? (ref (ref out #:columns "hour") 0) 8)
  (check-equal? (ref (ref out #:columns "minute") 0) 30)
  (check-equal? (ref (ref out #:columns "second") 0) 5)
  ;; an Expr argument works the same as a column-name string
  (check-equal? (ref (ref (~> df (with-columns (alias (dt-year (col "ts")) "y")))
                          #:columns "y")
                     0)
                2024))
