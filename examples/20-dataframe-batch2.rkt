#lang racket/base

;; DataFrame Batch 2: asof join, pivot, and unpivot — all prefix-free and
;; data-first, so they thread.
;;
;; Inside `nix develop`:
;;   racket examples/20-dataframe-batch2.rkt

(require polars)

(define observations
  (dataframe ["time" '(1 3 5) #:dtype 'i32]
             [reading '(100 300 500) #:dtype 'i32]))

(define calibrations
  (dataframe ["time" '(1 2 4) #:dtype 'i32]
             [offset '(10 20 40) #:dtype 'i32]))

(displayln "asof join:")
(displayln (~> observations (join-asof calibrations #:on "time" #:strategy 'backward)))
(newline)

(define sales
  (dataframe [store '("a" "a" "b" "b")]
             [quarter '("q1" "q2" "q1" "q2")]
             ["sales" '(10 20 30 40) #:dtype 'i32]))

(define pivoted
  (~> sales (pivot #:on '("quarter") #:index '("store") #:values '("sales") #:agg 'sum)))

(displayln "pivot:")
(displayln pivoted)
(newline)

(displayln "unpivot:")
(displayln (~> pivoted (unpivot #:on '("q1" "q2") #:index '("store"))))
