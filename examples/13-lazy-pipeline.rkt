#lang racket/base

;; Fluent lazy pipeline: filter → group_by_agg → sort.
;; Mirrors the canonical Polars Python flow:
;;   df.lazy()
;;     .filter(col("value") > 5)
;;     .group_by("group").agg([col("value").sum().alias("sum_value"),
;;                             col("value").mean().alias("mean_value"),
;;                             col("value").count().alias("n")])
;;     .sort("sum_value", descending=True)
;;     .collect()
;;
;; Inside `nix develop`:
;;   racket examples/13-lazy-pipeline.rkt

(require polars)

(define df
  (dataframe-new
   (list (series-new-str "group" '("a" "a" "a" "b" "b" "c" "c"))
         (series-new-i32 "value" '(10 25 7 30 18 4 22))
         (series-new-f64 "cost"  '(1.2 2.4 0.5 3.1 1.8 0.9 2.0)))))

(displayln "input:")
(display-dataframe df)
(newline)

;; One lazy plan, one .collect().
(define ranked
  (lazyframe-collect
   (lazyframe-sort
    (lazyframe-group-by-agg
     (lazyframe-filter (dataframe-lazy df)
                       (expr-gt (col "value") 5))
     '("group")
     (list (expr-alias (expr-sum  (col "value")) "sum_value")
           (expr-alias (expr-mean (col "value")) "mean_value")
           (expr-alias (expr-count (col "value")) "n")
           (expr-alias (expr-sum  (col "cost"))  "sum_cost")))
    '("sum_value") #:descending #t)))

(displayln "filter(value>5).group_by(group).agg(...).sort(sum_value desc):")
(display-dataframe ranked)
(newline)

;; dataframe-sort-exprs: lazy sort but eager-feeling at the call site.
(define top-cost
  (dataframe-sort-exprs df '("cost") #:descending #t))

(displayln "sort by cost desc (eager-feeling lazy):")
(display-dataframe top-cost)
