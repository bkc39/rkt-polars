#lang racket/base

;; Expr / lazy DSL — with_columns, select_exprs, filter_expr.
;; Mirrors the kind of one-pass column derivation that Polars Python
;; users get with `df.with_columns(...)`.
;;
;; Inside `nix develop`:
;;   racket examples/11-expr-with-columns.rkt

(require polars/private/foreign
         polars/private/expr)

(define df
  (dataframe-new
   (list (series-new-str "group" '("a" "a" "b" "b" "c"))
         (series-new-i32 "value" '(10 25 7 30 18))
         (series-new-f64 "cost"  '(1.2 2.4 0.5 3.1 1.8)))))

(displayln "input:")
(display-dataframe df)
(newline)

;; Derive two new columns in one pass:
;;   double_value = value * 2
;;   cost_plus_1  = cost + 1.0
(define df2
  (dataframe-with-columns
   df
   (list (expr-alias (expr-mul (col "value") 2) "double_value")
         (expr-alias (expr-add (col "cost") 1.0) "cost_plus_1"))))

(displayln "with_columns(double_value, cost_plus_1):")
(display-dataframe df2)
(newline)

;; select-exprs: project + transform in one pass
(define df3
  (dataframe-select-exprs
   df
   (list (col "group")
         (expr-alias (expr-mul (col "value") (col "cost")) "spend"))))

(displayln "select(group, value*cost as spend):")
(display-dataframe df3)
(newline)

;; filter via Expr predicate:  (value > 15) AND (cost < 3.0)
(define df4
  (dataframe-filter-expr
   df
   (expr-and (expr-gt (col "value") 15)
             (expr-lt (col "cost") 3.0))))

(displayln "filter(value>15 AND cost<3.0):")
(display-dataframe df4)
