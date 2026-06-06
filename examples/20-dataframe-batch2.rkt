#lang racket/base

;; DataFrame Batch 2: asof join, pivot, and unpivot — all prefix-free and
;; data-first, so they thread.
;;
;; Inside `nix develop`:
;;   racket examples/20-dataframe-batch2.rkt

(require polars)

(define observations
  (dataframe (list (series '(1 3 5)       #:name "time" #:dtype 'i32)
                   (series '(100 300 500) #:name "reading" #:dtype 'i32))))

(define calibrations
  (dataframe (list (series '(1 2 4)    #:name "time" #:dtype 'i32)
                   (series '(10 20 40) #:name "offset" #:dtype 'i32))))

(displayln "asof join:")
(displayln (~> observations (join-asof calibrations #:on "time" #:strategy 'backward)))
(newline)

(define sales
  (dataframe (list (series '("a" "a" "b" "b")     #:name "store")
                   (series '("q1" "q2" "q1" "q2") #:name "quarter")
                   (series '(10 20 30 40)         #:name "sales" #:dtype 'i32))))

(define pivoted
  (~> sales (pivot #:on '("quarter") #:index '("store") #:values '("sales") #:agg 'sum)))

(displayln "pivot:")
(displayln pivoted)
(newline)

(displayln "unpivot:")
(displayln (~> pivoted (unpivot #:on '("q1" "q2") #:index '("store"))))
