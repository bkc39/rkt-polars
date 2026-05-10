#lang racket/base

;; DataFrame asof join by-groups and tolerance.
;;
;; Inside `nix develop`:
;;   racket examples/29-dataframe-asof-options.rkt

(require polars)

(define observations
  (dataframe-new
   (list (series-new-i32 "time" '(1 3 5))
         (series-new-i32 "reading" '(100 300 500)))))

(define calibrations
  (dataframe-new
   (list (series-new-i32 "time" '(1 2 4))
         (series-new-i32 "offset" '(10 20 40)))))

(define exact
  (dataframe-join-asof observations calibrations
                       #:on "time"
                       #:strategy 'backward
                       #:tolerance 0))

(displayln "asof with exact-match tolerance:")
(display-dataframe exact)
(newline)

(define grouped-observations
  (dataframe-new
   (list (series-new-str "sensor" '("a" "a" "b" "b"))
         (series-new-i32 "time" '(3 5 3 5))
         (series-new-i32 "reading" '(300 500 30 50)))))

(define grouped-calibrations
  (dataframe-new
   (list (series-new-str "sensor" '("a" "a" "b" "b"))
         (series-new-i32 "time" '(1 4 1 4))
         (series-new-i32 "offset" '(10 40 100 400)))))

(define by-sensor
  (dataframe-join-asof grouped-observations grouped-calibrations
                       #:on "time"
                       #:by '("sensor")
                       #:strategy 'backward))

(displayln "asof by sensor:")
(display-dataframe by-sensor)
