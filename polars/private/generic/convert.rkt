#lang racket/base

(require racket/contract/base
         (only-in ffi/vector f64vector?)
         (only-in racket/sequence sequence-map)
         (only-in polars/private/bulk
                  check-column-names dataframe->columns dataframe->f64vector dataframe->hash
                  dataframe->rows in-dataframe-rows in-series series->f64vector series->list
                  series->vector)
         (only-in polars/private/foreign dataframe-column dataframe-column-names)
         (only-in polars/private/generic/core dataframe? series? wrap-series))

(provide
 (contract-out
  [series->list (->* (series?) (#:null any/c) list?)]
  [series->vector (->* (series?) (#:null any/c) vector?)]
  [series->f64vector (->* (series?) (#:null (or/c real? 'error)) f64vector?)]
  [in-series (->* (series?) (#:null any/c) sequence?)]
  [dataframe->columns
   (->* (dataframe?)
        (#:columns (listof string?) #:null any/c)
        (listof (cons/c string? vector?)))]
  [dataframe->hash
   (->* (dataframe?)
        (#:columns (listof string?) #:null any/c)
        (and/c (hash/c string? vector?) immutable?))]
  [dataframe->f64vector
   (->* (dataframe?)
        (#:columns (listof string?) #:order (or/c 'fortran 'c) #:null (or/c real? 'error))
        (values f64vector? exact-nonnegative-integer? exact-nonnegative-integer?))]
  [in-dataframe-columns (->* (dataframe?) (#:columns (listof string?)) sequence?)]
  [in-dataframe-rows
   (->* (dataframe?)
        (#:columns (listof string?)
         #:named? boolean?
         #:null any/c
         #:buffer-size exact-positive-integer?)
        sequence?)]
  [dataframe->rows
   (->* (dataframe?)
        (#:columns (listof string?) #:named? boolean? #:null any/c)
        (listof (or/c vector? (and/c hash? immutable?))))]))

(define (in-dataframe-columns d #:columns [names (dataframe-column-names d)])
  (check-column-names 'in-dataframe-columns d names)
  (sequence-map (lambda (name) (wrap-series (dataframe-column d name))) names))

(module+ internal
  (provide in-dataframe-columns))
