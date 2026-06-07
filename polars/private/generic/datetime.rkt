#lang racket/base

;; Polars' `.dt` namespace: calendar/clock field extraction from a datetime Expr.
;; Each mirrors pl.col(x).dt.<method>().  The first argument is the column to
;; operate on; a bare column-name string is auto-lifted via `col`, so both
;;   (year (col "ts"))  and  (year "ts")
;; work.  These are exported prefix-free (year / month / day / hour / minute /
;; second); `second` shadows racket/list's list accessor for consumers that
;; also require racket/list.

(require polars/private/foreign
         polars/private/expr)

(provide year month day hour minute second)

;; Lift a column-name string to an Expr; pass an Expr through unchanged.
(define (->dt-expr who x)
  (cond [(Expr-ptr? x) x]
        [(string? x)   (col x)]
        [else (error who "expected an Expr or column name, got ~v" x)]))

(define (year x)   (expr-dt-year   (->dt-expr 'year x)))
(define (month x)  (expr-dt-month  (->dt-expr 'month x)))
(define (day x)    (expr-dt-day    (->dt-expr 'day x)))
(define (hour x)   (expr-dt-hour   (->dt-expr 'hour x)))
(define (minute x) (expr-dt-minute (->dt-expr 'minute x)))
(define (second x) (expr-dt-second (->dt-expr 'second x)))

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
          (alias (year "ts") "year")
          (alias (month "ts") "month")
          (alias (day "ts") "day")
          (alias (hour "ts") "hour")
          (alias (minute "ts") "minute")
          (alias (second "ts") "second"))))
  (check-equal? (ref (ref out #:columns "year") 0) 2024)
  (check-equal? (ref (ref out #:columns "month") 0) 1)
  (check-equal? (ref (ref out #:columns "day") 0) 2)
  (check-equal? (ref (ref out #:columns "hour") 0) 8)
  (check-equal? (ref (ref out #:columns "minute") 0) 30)
  (check-equal? (ref (ref out #:columns "second") 0) 5)
  ;; an Expr argument works the same as a column-name string
  (check-equal? (ref (ref (~> df (with-columns (alias (year (col "ts")) "y")))
                          #:columns "y")
                     0)
                2024))
