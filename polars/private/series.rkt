#lang racket/base

(require (only-in racket/list make-list)
         polars/private/foreign
         (only-in polars/private/resource with-release)
         (only-in polars/private/temporal temporal-encoder))

(provide series-new-temporal
         series-repeat-temporal)

(define (series-from-physical who name physicals dtype)
  (define construct
    (cond
      [(eq? dtype 'date) (if (vector? physicals) series-new-i32/vec series-new-i32)]
      [(vector? physicals) series-new-i64/vec]
      [else series-new-i64]))
  (with-release ([s (construct name physicals) series-drop])
    (series-cast-to who s dtype)))

(define (physical-encoder who dtype)
  (define encode (temporal-encoder who dtype))
  (lambda (v) (if (polars-null? v) v (encode v))))

(define (series-new-temporal who name elements dtype)
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
