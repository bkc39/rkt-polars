#lang racket/base

;; DataFrame Batch 2: asof join, pivot, and unpivot.
;;
;; Inside `nix develop`:
;;   racket examples/20-dataframe-batch2.rkt

(require polars)

(define observations
  (dataframe-new
   (list (series-new-i32 "time" '(1 3 5))
         (series-new-i32 "reading" '(100 300 500)))))

(define calibrations
  (dataframe-new
   (list (series-new-i32 "time" '(1 2 4))
         (series-new-i32 "offset" '(10 20 40)))))

(displayln "asof join:")
(display-dataframe
 (dataframe-join-asof observations calibrations
                      #:on "time"
                      #:strategy 'backward))
(newline)

(define sales
  (dataframe-new
   (list (series-new-str "store" '("a" "a" "b" "b"))
         (series-new-str "quarter" '("q1" "q2" "q1" "q2"))
         (series-new-i32 "sales" '(10 20 30 40)))))

(define pivoted
  (dataframe-pivot sales
                   #:on '("quarter")
                   #:index '("store")
                   #:values '("sales")
                   #:agg 'sum))

(displayln "pivot:")
(display-dataframe pivoted)
(newline)

(displayln "unpivot:")
(display-dataframe
 (dataframe-unpivot pivoted
                    #:on '("q1" "q2")
                    #:index '("store")))
