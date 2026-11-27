#lang racket/base

;; DataFrame asof join by-groups and tolerance.
;;
;; join-asof matches each left row to the nearest-earlier right row by a
;; sorted key; #:tolerance bounds the allowed gap and #:by joins within groups.
;;
;; Inside `nix develop`:
;;   racket examples/29-dataframe-asof-options.rkt

(require polars)

(define observations
  (dataframe ["time" '(1 3 5) #:dtype 'i32]
             [reading '(100 300 500) #:dtype 'i32]))

(define calibrations
  (dataframe ["time" '(1 2 4) #:dtype 'i32]
             [offset '(10 20 40) #:dtype 'i32]))

(displayln "asof with exact-match tolerance:")
(displayln (~> observations
               (join-asof calibrations #:on "time" #:strategy 'backward #:tolerance 0)))
(newline)

(define grouped-observations
  (dataframe [sensor '("a" "a" "b" "b")]
             ["time" '(3 5 3 5) #:dtype 'i32]
             [reading '(300 500 30 50) #:dtype 'i32]))

(define grouped-calibrations
  (dataframe [sensor '("a" "a" "b" "b")]
             ["time" '(1 4 1 4) #:dtype 'i32]
             [offset '(10 40 100 400) #:dtype 'i32]))

(displayln "asof by sensor:")
(displayln (~> grouped-observations
               (join-asof grouped-calibrations
                          #:on "time" #:by '("sensor") #:strategy 'backward)))
