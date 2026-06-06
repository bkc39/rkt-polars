#lang racket/base

;; Lazy head / tail / slice — slice a lazy plan with no intermediate collect:
;;   df.lazy().filter(col("score") > 50).sort("score", descending=True).head(3).collect()
;;
;; Inside `nix develop`:
;;   racket examples/14-lazy-head-tail-slice.rkt

(require polars)

(define df
  (dataframe
   (list (series '("a" "b" "c" "d" "e" "f" "g") #:name "name")
         (series '(42 91 17 73 60 88 24)         #:name "score" #:dtype 'i32))))

(displayln "input:")
(displayln df)
(newline)

;; Top 3 by score, all in one lazy plan.
(displayln "filter(score>50).sort(score desc).head(3):")
(displayln (~> df
               lazy
               (filter (> (col "score") 50))
               (sort "score" #:descending #t)
               (head 3)
               collect))
(newline)

;; Bottom 2 of original.
(displayln "tail(2):")
(displayln (~> df lazy (tail 2) collect))
(newline)

;; Middle window: skip 2, take 3.
(displayln "slice(offset=2, len=3):")
(displayln (~> df lazy (slice 2 3) collect))
