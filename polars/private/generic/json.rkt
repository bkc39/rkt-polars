#lang racket/base

(require (only-in racket/contract/base -> contract-out)
         (only-in polars/private/json
                  json-reader json-reader/c json-writer ndjson-reader ndjson-reader/c
                  ndjson-scanner ndjson-writer ndjson-writer/c)
         (only-in polars/private/generic/core
                  dataframe? define-wrapped lazyframe? wrap-dataframe wrap-lazyframe))

(provide (contract-out
          [read-json (json-reader/c dataframe?)]
          [write-json (-> dataframe? path-string? void?)]
          [read-ndjson (ndjson-reader/c dataframe?)]
          [scan-ndjson (ndjson-reader/c lazyframe?)]
          [write-ndjson (ndjson-writer/c dataframe?)]))

(module+ internal
  (provide read-json read-ndjson scan-ndjson write-json write-ndjson))

(define-wrapped read-json wrap-dataframe (json-reader 'read-json))
(define-wrapped read-ndjson wrap-dataframe (ndjson-reader 'read-ndjson))
(define-wrapped scan-ndjson wrap-lazyframe (ndjson-scanner 'scan-ndjson))
(define write-json (json-writer 'write-json))
(define write-ndjson (ndjson-writer 'write-ndjson))
