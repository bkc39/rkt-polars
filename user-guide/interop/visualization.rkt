#lang racket/base

;; rkt-polars user guide — Interoperability: Data for a plot.
;; Mirrors the Matplotlib scatter of
;; https://docs.pola.rs/user-guide/misc/visualization/ and visualization.py.
;; Racket's `plot` is not a dependency, so this builds the points a
;; `(plot (points sepals))` call takes and prints the first few.
;;
;; Inside `nix develop`:
;;   racket user-guide/interop/visualization.rkt

(require racket/runtime-path
         polars)

(define-runtime-path iris-csv "../data/iris.csv")

(define iris (read-csv iris-csv))

(define sepals
  (map vector
       (~> iris (ref "sepal_width") series->list)
       (~> iris (ref "sepal_length") series->list)))

(writeln (length sepals))
(writeln (for/list ([p sepals] [_ 3]) p))
;; API gap: no plotting namespace (df.plot, hvPlot).
