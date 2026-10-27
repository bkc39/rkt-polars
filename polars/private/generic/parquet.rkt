#lang racket/base

(require (only-in racket/contract/base contract-out)
         (only-in polars/private/parquet
                  parquet-reader parquet-reader/c parquet-scanner parquet-scanner/c
                  parquet-writer parquet-writer/c)
         (only-in polars/private/generic/core
                  dataframe? define-wrapped lazyframe? wrap-dataframe wrap-lazyframe))

(provide (contract-out
          [read-parquet (parquet-reader/c dataframe?)]
          [scan-parquet (parquet-scanner/c lazyframe?)]
          [write-parquet (parquet-writer/c dataframe?)]))

(module+ internal
  (provide read-parquet scan-parquet write-parquet))

(define-wrapped read-parquet wrap-dataframe (parquet-reader 'read-parquet))
(define-wrapped scan-parquet wrap-lazyframe (parquet-scanner 'scan-parquet))
(define write-parquet (parquet-writer 'write-parquet))
