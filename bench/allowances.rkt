#lang racket/base

;; The rkt/py ratio each op of perf.rkt may reach under `--strict` (#90); an op
;; the table does not name gets the default.  An entry names the issue that
;; owns the gap and the measurement it was set from.

(provide (struct-out allowance)
         default-allowance
         allowances)

(struct allowance (op ratio issue basis) #:transparent)

(define default-allowance
  (allowance #f 1.2 88 "the nycflights arc's bound: within 20% of Python polars"))

(define allowances
  (list (allowance "f64-matrix" 1.75 115
                   "1.52–1.67× (1.63× over the rounds) in four quiet-host runs of 0.55.2, 2026-09-29")))
