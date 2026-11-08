#lang racket/base

(require (only-in racket/list make-list)
         (only-in racket/match match match-define)
         polars/private/foreign
         (only-in (submod polars/private/foreign internal) series-ref-datetime)
         (only-in polars/private/resource with-release)
         (only-in polars/private/temporal
                  check-date-datetime-mix chrono-edge? temporal-encoder))

(provide series-new-temporal
         series-repeat-temporal
         zoned-temporal-encoder)

(define (series-from-physical who name physicals dtype)
  (define construct
    (cond
      [(eq? dtype 'date) (if (vector? physicals) series-new-i32/vec series-new-i32)]
      [(vector? physicals) series-new-i64/vec]
      [else series-new-i64]))
  (with-release ([s (construct name physicals) series-drop])
    (series-cast-to who s dtype)))

;; polars reads a wall clock through chrono, which refuses one outside its range.
(define (local-clock-readable? who dtype ticks)
  (match-define (list _ unit zone) dtype)
  (with-release ([s (series-from-physical who "" (list ticks) dtype) series-drop])
    (and (series-ref-datetime who s 0 unit zone (lambda (_reason) #f)) #t)))

(define (zoned-temporal-encoder who dtype)
  (define encode (temporal-encoder who dtype))
  (match dtype
    [(list 'datetime unit (? string?))
     (lambda (v)
       (define ticks (encode v))
       (when (and (chrono-edge? unit ticks) (not (local-clock-readable? who dtype ticks)))
         (raise-arguments-error who "value out of range for this dtype" "dtype" dtype "value" v))
       ticks)]
    [_ encode]))

(define (physical-encoder who dtype)
  (define encode (zoned-temporal-encoder who dtype))
  (lambda (v) (if (polars-null? v) v (encode v))))

(define (series-new-temporal who name elements dtype)
  (check-date-datetime-mix who dtype elements)
  (define physical (physical-encoder who dtype))
  (series-from-physical who
                        name
                        (if (vector? elements)
                            (for/vector #:length (vector-length elements) ([v (in-vector elements)])
                              (physical v))
                            (map physical elements))
                        dtype))

(define (series-repeat-temporal who name value n dtype)
  (series-from-physical who name (make-list n ((physical-encoder who dtype) value)) dtype))
