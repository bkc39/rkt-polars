#lang racket/base

;; Lazy group-by — Polars-idiomatic
;;   lf.group_by([col("group")])
;;     .agg([col("value").sum().alias("sum_value"), ...])
;;     .collect()
;;
;; Unlike the eager dataframe-group-by-{sum,mean,...} helpers which run
;; one aggregation per call, this lets us fan out multiple aggregations
;; over the same group keys in a single pass.
;;
;; Inside `nix develop`:
;;   racket examples/12-lazy-group-by.rkt

(require polars)

(define df
  (dataframe-new
   (list (series-new-str "group" '("a" "a" "a" "b" "b" "c"))
         (series-new-i32 "value" '(10 25 7 30 18 4))
         (series-new-f64 "cost"  '(1.2 2.4 0.5 3.1 1.8 0.9)))))

(displayln "input:")
(display-dataframe df)
(newline)

;; Per-group aggregations on `value` and `cost` in one shot.
(define rolled-up
  (dataframe-group-by-agg
   df
   '("group")
   (list (expr-alias (expr-sum  (col "value")) "sum_value")
         (expr-alias (expr-mean (col "value")) "mean_value")
         (expr-alias (expr-max  (col "value")) "max_value")
         (expr-alias (expr-count (col "value")) "n")
         (expr-alias (expr-sum  (col "cost"))  "sum_cost"))))

(displayln "group_by(group).agg(sum_value, mean_value, max_value, n, sum_cost):")
(display-dataframe rolled-up)
(newline)

;; Aggregating an Expr derived from columns, not just a raw column.
;; spend = value * cost; report total spend and #rows per group.
(define spend
  (dataframe-group-by-agg
   df
   '("group")
   (list (expr-alias (expr-sum (expr-mul (col "value") (col "cost")))
                     "total_spend")
         (expr-alias (expr-count (col "value")) "n"))))

(displayln "group_by(group).agg(sum(value*cost) as total_spend, n):")
(display-dataframe spend)
