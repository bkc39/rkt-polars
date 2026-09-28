#lang racket/base

;; Series to Racket values: series->list and series->vector.
;;
;; A whole column is copied out in one foreign call, into a buffer Racket
;; allocates and frees (not one call per element). A null comes out as
;; polars-null, or as the #:null value.
;;
;; Inside `nix develop`:
;;   racket examples/47-series-to-racket.rkt

(require polars)

(define scores (series (list 10 polars-null 30 polars-null 50) #:name "score"))

(writeln (series->list scores))
(writeln (series->list scores #:null 0))
(writeln (series->vector scores))
(writeln (series->vector scores #:null 'missing))

;; the list and vector are ordinary Racket values
(writeln (apply + (series->list scores #:null 0)))
(define v (series->vector scores #:null 0))
(vector-set! v 0 -1)
(writeln v)

;; a column of a dataframe converts the same way
(define df
  (dataframe (list (series '("a" "b" "c") #:name "key")
                   (series '(1.5 2.5 3.5) #:name "value"))))
(writeln (~> df (ref "value") series->list))
(writeln (~> df (ref "key") series->vector))
