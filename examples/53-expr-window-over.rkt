#lang racket/base

;; Window functions: over.
;;
;; (over e key ...) computes e within each group of the keys and maps the
;; result back onto the group's rows, so the frame keeps its height, where
;; group-by / agg would collapse each group to one row.  Keys are column names
;; or expressions, as group-by takes them:
;;   col("v").sum().over("g")         ->  (~> (col "v") sum (over "g"))
;;   col("v").rank().over("g", "h")   ->  (~> (col "v") rank (over "g" "h"))
;;
;; Inside `nix develop`:
;;   racket examples/53-expr-window-over.rkt

(require polars)

(define sales
  (dataframe
   (list (series '("north" "north" "north" "south" "south" "south") #:name "region")
         (series '("a" "b" "a" "a" "b" "b")                         #:name "product")
         (series '(10 25 7 30 18 4)                                #:name "units"))))

(displayln "input:")
(displayln sales)

(displayln "an aggregate broadcast to every row of its group:")
(displayln
 (~> sales
     (with-columns (~> (col "units") sum (over "region") (alias "region_total"))
                   (~> (col "units") mean (over "region") (alias "region_mean")))))

(displayln "the same sums from group-by / agg, one row per group:")
(displayln
 (~> sales (group-by "region") (agg (~> (col "units") sum (alias "region_total"))) (sort "region")))

(displayln "several keys:")
(displayln
 (~> sales
     (with-columns (~> (col "units") sum (over "region" "product") (alias "cell_total")))))

(displayln "a per-group operation that keeps one value per row (rank within region):")
(displayln
 (~> sales
     (with-columns (~> (col "units")
                       (rank #:method 'dense #:descending #t)
                       (over "region")
                       (alias "rank_in_region")))))

(displayln "an expression as the key (units above 15 vs the rest):")
(displayln
 (~> sales
     (with-columns (~> (col "units") max (over (> (col "units") 15)) (alias "max_in_band")))))

;; `/` on two integer columns is integer division, so cast first.
(displayln "share of the region's total, lazily:")
(displayln
 (~> sales
     lazy
     (with-columns (~> (cast "units" 'float64)
                       (/ (~> (col "units") sum (over "region")))
                       (round #:decimals 3)
                       (alias "share")))
     collect))
