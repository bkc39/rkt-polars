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
  (dataframe (list (series '(1 3 5)       #:name "time"    #:dtype 'i32)
                   (series '(100 300 500) #:name "reading" #:dtype 'i32))))

(define calibrations
  (dataframe (list (series '(1 2 4)    #:name "time"   #:dtype 'i32)
                   (series '(10 20 40) #:name "offset" #:dtype 'i32))))

(displayln "asof with exact-match tolerance:")
(displayln (~> observations
               (join-asof calibrations #:on "time" #:strategy 'backward #:tolerance 0)))
(newline)

(define grouped-observations
  (dataframe (list (series '("a" "a" "b" "b") #:name "sensor")
                   (series '(3 5 3 5)         #:name "time"    #:dtype 'i32)
                   (series '(300 500 30 50)   #:name "reading" #:dtype 'i32))))

(define grouped-calibrations
  (dataframe (list (series '("a" "a" "b" "b") #:name "sensor")
                   (series '(1 4 1 4)         #:name "time"   #:dtype 'i32)
                   (series '(10 40 100 400)   #:name "offset" #:dtype 'i32))))

(displayln "asof by sensor:")
(displayln (~> grouped-observations
               (join-asof grouped-calibrations
                          #:on "time" #:by '("sensor") #:strategy 'backward)))
