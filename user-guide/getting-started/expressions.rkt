#lang racket/base

;; rkt-polars user guide — Expressions
;; Mirrors https://docs.pola.rs/user-guide/getting-started/ (the "Expressions"
;; section: select / with_columns / filter / group_by) and expressions.py.
;;
;; Inside `nix develop`:
;;   racket user-guide/getting-started/expressions.rkt

(require polars)

;; `col` references a column; expr combinators build derived expressions;
;; `expr-alias` names a result.  These are the same expressions whether used
;; in select, with_columns, filter, or group_by/agg "contexts".
(define df
  (dataframe-new
   (list (series '("a" "a" "b" "b" "c") #:name "group")
         (series '(10 25 7 30 18) #:name "value" #:dtype 'i32)
         (series '(1.2 2.4 0.5 3.1 1.8) #:name "cost"))))

(displayln "input:")
(display-dataframe df)
(newline)

;; --- select: choose and transform columns ------------------------------
(displayln "select(group, value*cost as spend):")
(display-dataframe
 (dataframe-select-exprs
  df
  (list (col "group")
        (expr-alias (expr-mul (col "value") (col "cost")) "spend"))))
(newline)

;; --- with_columns: add derived columns in one pass ---------------------
(displayln "with_columns(double_value, cost_plus_1):")
(display-dataframe
 (dataframe-with-columns
  df
  (list (expr-alias (expr-mul (col "value") 2) "double_value")
        (expr-alias (expr-add (col "cost") 1.0) "cost_plus_1"))))
(newline)

;; --- filter: keep rows matching a predicate ----------------------------
(displayln "filter(value > 15 AND cost < 3.0):")
(display-dataframe
 (dataframe-filter-expr
  df
  (expr-and (expr-gt (col "value") 15)
            (expr-lt (col "cost") 3.0))))
(newline)

;; --- group_by + agg: aggregate per group -------------------------------
(displayln "group_by(group).agg(sum_value, mean_value, n):")
(display-dataframe
 (dataframe-group-by-agg
  df
  '("group")
  (list (expr-alias (expr-sum   (col "value")) "sum_value")
        (expr-alias (expr-mean  (col "value")) "mean_value")
        (expr-alias (expr-count (col "value")) "n"))))
