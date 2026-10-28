#lang racket/base

;; Polars' `.dt` namespace: calendar/clock field extraction from a datetime Expr.
;; Each mirrors pl.col(x).dt.<method>().  The first argument is the column to
;; operate on; a bare column-name string is auto-lifted via `col`, so both
;;   (dt-year (col "ts"))  and  (dt-year "ts")
;; work.  The `dt-` prefix is the Lisp realization of Polars' `.dt` namespace:
;; uniform with the `str-` namespace and collision-safe (e.g. the upcoming
;; dt-date / dt-time would otherwise clash with gregor's date and racket/base's
;; time).

(require racket/contract/base
         (only-in racket/string non-empty-string?)
         polars/private/foreign
         polars/private/expr
         (only-in polars/private/expr-dt expr-dt-convert-time-zone expr-dt-replace-time-zone)
         (only-in polars/private/generic/core series? wrap-series)
         polars/private/generic/expr-util)

(provide dt-year dt-month dt-day dt-hour dt-minute dt-second
         dt-iso-year dt-quarter dt-week dt-weekday dt-ordinal-day
         dt-is-leap-year dt-date dt-time
         dt-millisecond dt-microsecond dt-nanosecond
         dt-timestamp dt-strftime dt-truncate
         (contract-out
          [dt-convert-time-zone (-> (or/c series? col-expr/c) non-empty-string?
                                    (or/c series? Expr-ptr?))]
          [dt-replace-time-zone (->* ((or/c series? col-expr/c) (or/c #f non-empty-string?))
                                     (#:ambiguous (or/c 'raise 'earliest 'latest 'null)
                                      #:non-existent (or/c 'raise 'null))
                                     (or/c series? Expr-ptr?))]))

(define-expr-unop dt-year   'dt-year   expr-dt-year)
(define-expr-unop dt-month  'dt-month  expr-dt-month)
(define-expr-unop dt-day    'dt-day    expr-dt-day)
(define-expr-unop dt-hour   'dt-hour   expr-dt-hour)
(define-expr-unop dt-minute 'dt-minute expr-dt-minute)
(define-expr-unop dt-second 'dt-second expr-dt-second)

;; ISO / calendar fields, date+time extraction, and subsecond fields.
(define-expr-unop dt-iso-year     'dt-iso-year     expr-dt-iso-year)
(define-expr-unop dt-quarter      'dt-quarter      expr-dt-quarter)
(define-expr-unop dt-week         'dt-week         expr-dt-week)
(define-expr-unop dt-weekday      'dt-weekday      expr-dt-weekday)
(define-expr-unop dt-ordinal-day  'dt-ordinal-day  expr-dt-ordinal-day)
(define-expr-unop dt-is-leap-year 'dt-is-leap-year expr-dt-is-leap-year)
(define-expr-unop dt-date         'dt-date         expr-dt-date)
(define-expr-unop dt-time         'dt-time         expr-dt-time)
(define-expr-unop dt-millisecond  'dt-millisecond  expr-dt-millisecond)
(define-expr-unop dt-microsecond  'dt-microsecond  expr-dt-microsecond)
(define-expr-unop dt-nanosecond   'dt-nanosecond   expr-dt-nanosecond)

;; epoch timestamp (#:unit 'milliseconds|'microseconds|'nanoseconds), strftime
;; formatting, and truncation to a fixed interval (e.g. "1h", "1d").
(define (dt-timestamp x #:unit [unit 'microseconds])
  (expr-dt-timestamp (->col-expr 'dt-timestamp x) #:unit unit))
(define (dt-strftime x fmt) (expr-dt-strftime (->col-expr 'dt-strftime x) fmt))
(define (dt-truncate x every)
  (expr-dt-truncate (->col-expr 'dt-truncate x) (->expr/who 'dt-truncate every)))

(define (dt-convert-time-zone x zone)
  (define who 'dt-convert-time-zone)
  (if (series? x)
      (wrap-series (series-dt-convert-time-zone who x zone))
      (expr-dt-convert-time-zone (->col-expr who x) zone #:who who)))

(define (dt-replace-time-zone x zone
                              #:ambiguous [ambiguous 'raise]
                              #:non-existent [non-existent 'raise])
  (define who 'dt-replace-time-zone)
  (if (series? x)
      (wrap-series (series-dt-replace-time-zone who x zone ambiguous non-existent))
      (expr-dt-replace-time-zone (->col-expr who x) zone
                                 #:ambiguous ambiguous #:non-existent non-existent #:who who)))

(module+ internal
  (provide dt-convert-time-zone dt-replace-time-zone))
