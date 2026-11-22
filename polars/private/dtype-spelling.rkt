#lang racket/base

(require racket/match
         (only-in polars/private/compat-dtype
                  dtype-short-names enum-dtype? zoned-datetime-dtype?))

(provide dtype-aliases dtype-spec? normalize-dtype)

(define dtype-aliases
  (for/fold ([aliases dtype-short-names])
            ([canonical (in-list '(int8 int16 int32 int64 uint8 uint16 uint32 uint64
                                   float32 float64 boolean string
                                   date time datetime categorical null))])
    (hash-set aliases canonical canonical)))

(define (dtype-spec? v)
  (match v
    [(? symbol?) (hash-has-key? dtype-aliases v)]
    [(list* (or 'datetime 'duration)
            (or #f 'none 'nanoseconds 'microseconds 'milliseconds)
            (or '() (list #f)))
     #t]
    [_ (or (enum-dtype? v) (zoned-datetime-dtype? v))]))

(define (normalize-dtype dt [who 'normalize-dtype])
  (cond
    [(not (dtype-spec? dt)) (error who "unsupported dtype ~v" dt)]
    [(symbol? dt) (hash-ref dtype-aliases dt)]
    [else dt]))
