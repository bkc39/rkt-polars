#lang racket/base

;; Fluent lazy pipeline mirroring Polars:
;;   df.lazy().filter(col("value") > 5)
;;     .group_by("group").agg(col("value").sum().alias("sum_value"), ...)
;;     .sort("sum_value", descending=True).collect()
;;
;; Inside `nix develop`:
;;   racket examples/13-lazy-pipeline.rkt

(require polars)

(define df
  (dataframe
   (list (series '("a" "a" "a" "b" "b" "c" "c") #:name "group")
         (series '(10 25 7 30 18 4 22)            #:name "value" #:dtype 'i32)
         (series '(1.2 2.4 0.5 3.1 1.8 0.9 2.0)   #:name "cost"))))

(displayln "input:")
(displayln df)
(newline)

;; One lazy plan, one collect.
(displayln "filter(value>5).group_by(group).agg(...).sort(sum_value desc):")
(displayln (~> df
               lazy
               (filter (> (col "value") 5))
               (group-by "group")
               (agg (~> (col "value") sum   (alias "sum_value"))
                    (~> (col "value") mean  (alias "mean_value"))
                    (~> (col "value") count (alias "n"))
                    (~> (col "cost")  sum   (alias "sum_cost")))
               (sort "sum_value" #:descending #t)
               collect))
(newline)

;; sort by cost desc (the eager dataframe sort).
(displayln "sort by cost desc:")
(displayln (~> df (sort '("cost") #:descending #t)))
