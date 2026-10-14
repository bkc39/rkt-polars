#lang racket/base

;; The examples of interop.scrbl's "Data for a plot", on its fixture.

(module+ test
  (require rackunit
           racket/runtime-path
           (only-in file/convertible convert)
           (only-in plot/pict plot points)
           polars)

  (define-runtime-path iris-csv "iris.csv")

  (define iris (read-csv iris-csv))
  (define sepals
    (map vector
         (~> iris (ref "sepal_width") series->list)
         (~> iris (ref "sepal_length") series->list)))
  (check-equal? (length sepals) 15)
  (check-equal? (for/list ([p sepals] [_ 3]) p) '(#(3.5 5.1) #(3.0 4.9) #(3.2 4.7)))
  (check-pred bytes?
              (convert (plot (points sepals) #:x-label "sepal_width" #:y-label "sepal_length")
                       'png-bytes)))
