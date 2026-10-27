#lang racket/base

(require (only-in racket/contract/base contract-out)
         (only-in polars/private/csv
                  csv-reader csv-reader/c csv-scanner csv-scanner/c csv-writer csv-writer/c)
         (only-in polars/private/generic/core
                  dataframe? define-wrapped lazyframe? wrap-dataframe wrap-lazyframe))

(provide (contract-out
          [read-csv (csv-reader/c dataframe?)]
          [scan-csv (csv-scanner/c lazyframe?)]
          [write-csv (csv-writer/c dataframe?)]))

(module+ internal
  (provide read-csv scan-csv write-csv))

(define-wrapped read-csv wrap-dataframe (csv-reader 'read-csv))
(define-wrapped scan-csv wrap-lazyframe (csv-scanner 'scan-csv))
(define write-csv (csv-writer 'write-csv))
