#lang racket/base

;; Lazy head / tail / slice — slice a lazy plan without an intermediate
;; .collect().  Mirrors the canonical Polars Python flow:
;;   df.lazy()
;;     .filter(col("score") > 50)
;;     .sort("score", descending=True)
;;     .head(3)
;;     .collect()
;;
;; Inside `nix develop`:
;;   racket examples/14-lazy-head-tail-slice.rkt

(require polars)

(define df
  (dataframe-new
   (list (series-new-str "name"  '("a" "b" "c" "d" "e" "f" "g"))
         (series-new-i32 "score" '(42 91 17 73 60 88 24)))))

(displayln "input:")
(display-dataframe df)
(newline)

;; Top 3 by score, all in one lazy plan.
(define top3
  (lazyframe-collect
   (lazyframe-head
    (lazyframe-sort
     (lazyframe-filter (dataframe-lazy df)
                       (expr-gt (col "score") 50))
     '("score") #:descending #t)
    3)))

(displayln "filter(score>50).sort(score desc).head(3):")
(display-dataframe top3)
(newline)

;; Bottom 2 of original.
(define bot2
  (lazyframe-collect (lazyframe-tail (dataframe-lazy df) 2)))

(displayln "tail(2):")
(display-dataframe bot2)
(newline)

;; Middle window: skip 2, take 3.
(define mid
  (lazyframe-collect (lazyframe-slice (dataframe-lazy df) 2 3)))

(displayln "slice(offset=2, len=3):")
(display-dataframe mid)
