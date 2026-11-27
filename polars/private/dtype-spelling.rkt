#lang racket/base

(require (only-in racket/contract/base and/c flat-contract-predicate or/c)
         racket/match
         (only-in polars/private/compat-dtype
                  datetime-zone/c dtype-short-names enum-dtype? time-zone-name/c
                  zoned-datetime-dtype?))

(provide cast-target/c dtype-aliases dtype-spec? normalize-dtype)

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
    [(and (? zoned-datetime-dtype?) (list _ _ zone)) (time-zone-name? zone)]
    [_ (enum-dtype? v)]))

(define time-zone-name? (flat-contract-predicate time-zone-name/c))

(define cast-target/c (and/c datetime-zone/c (or/c dtype-spec? 'binary 'duration)))

(define (normalize-dtype dt [who 'normalize-dtype])
  (cond
    [(not (dtype-spec? dt)) (error who "unsupported dtype ~v" dt)]
    [(symbol? dt) (hash-ref dtype-aliases dt)]
    [else dt]))
