#lang racket/base

(require polars/private/facade)

(define-facade
  #:parts (polars/private/compat-dtype polars/private/compat-ffi polars/private/compat-opt
           polars/private/dataframe-core polars/private/dataframe-ops polars/private/owned
           polars/private/reason polars/private/series-core polars/private/series-new
           polars/private/series-ops polars/private/series-ref)
  #:internal-parts (polars/private/compat-ffi polars/private/dataframe-core
                    polars/private/dataframe-ops polars/private/owned polars/private/reason
                    polars/private/series-core polars/private/series-new
                    polars/private/series-ops polars/private/series-ref)
  #:hide-internal (call/reason define-frame-op/reason strings->series))
