#lang racket/base

;; rkt-polars user guide — Concepts: Lazy API
;; Mirrors https://docs.pola.rs/user-guide/concepts/lazy-api/ and lazy_api.py.
;;
;; Inside `nix develop`:
;;   racket user-guide/concepts/lazy-api.rkt

(require racket/runtime-path
         polars)

(define-runtime-path iris-csv "../data/iris.csv")

;; --- eager ---------------------------------------------------------------
(define df (read-csv iris-csv))
(define df-small (filter df (> (col "sepal_length") 5)))
(define df-agg (~> df-small (group-by "species") (agg (mean "sepal_width"))))
(displayln df-agg)

;; --- lazy ----------------------------------------------------------------
(define q
  (~> (scan-csv iris-csv)
      (filter (> (col "sepal_length") 5))
      (group-by "species")
      (agg (mean "sepal_width"))))

(displayln (collect q))

;; API gaps: no explain (query plan preview) and no schema-only LazyFrame.
