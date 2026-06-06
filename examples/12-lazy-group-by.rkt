#lang racket/base

;; group-by with multiple aggregations over the same keys in one pass.  Each
;; aggregation threads to mirror Polars' method chain:
;;   col("value").sum().alias("sum_value")  ->  (~> (col "value") sum (alias "sum_value"))
;;   lf.group_by("group").agg(...)          ->  (~> df (group-by "group") (agg ...))
;;
;; Inside `nix develop`:
;;   racket examples/12-lazy-group-by.rkt

(require polars)

(define df
  (dataframe
   (list (series '("a" "a" "a" "b" "b" "c") #:name "group")
         (series '(10 25 7 30 18 4)          #:name "value" #:dtype 'i32)
         (series '(1.2 2.4 0.5 3.1 1.8 0.9)  #:name "cost"))))

(displayln "input:")
(displayln df)
(newline)

;; Per-group aggregations on `value` and `cost` in one shot.
(displayln "group_by(group).agg(sum_value, mean_value, max_value, n, sum_cost):")
(displayln (~> df
               (group-by "group")
               (agg (~> (col "value") sum   (alias "sum_value"))
                    (~> (col "value") mean  (alias "mean_value"))
                    (~> (col "value") max   (alias "max_value"))
                    (~> (col "value") count (alias "n"))
                    (~> (col "cost")  sum   (alias "sum_cost")))))
(newline)

;; Aggregating an Expr derived from columns: spend = value * cost.
(displayln "group_by(group).agg(sum(value*cost) as total_spend, n):")
(displayln (~> df
               (group-by "group")
               (agg (~> (col "value") (* (col "cost")) sum (alias "total_spend"))
                    (~> (col "value") count (alias "n")))))
