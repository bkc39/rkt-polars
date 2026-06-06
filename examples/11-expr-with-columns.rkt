#lang racket/base

;; Expr DSL — one-pass column derivation, prefix-free and threaded.  Each derived
;; column is itself a thread: (~> (col "value") (* 2) (alias "double_value")).
;;   df.with_columns(...)  ->  (~> df (with-columns ...))
;;   df.select(...)        ->  (~> df (select ...))
;;   df.filter(expr)       ->  (~> df (filter ...))
;;
;; Inside `nix develop`:
;;   racket examples/11-expr-with-columns.rkt

(require polars)

(define df
  (dataframe
   (list (series '("a" "a" "b" "b" "c") #:name "group")
         (series '(10 25 7 30 18)        #:name "value" #:dtype 'i32)
         (series '(1.2 2.4 0.5 3.1 1.8)  #:name "cost"))))

(displayln "input:")
(displayln df)
(newline)

;; Derive two new columns in one pass:
;;   double_value = value * 2
;;   cost_plus_1  = cost + 1.0
(displayln "with_columns(double_value, cost_plus_1):")
(displayln (~> df
               (with-columns
                 (~> (col "value") (* 2)   (alias "double_value"))
                 (~> (col "cost")  (+ 1.0) (alias "cost_plus_1")))))
(newline)

;; select + transform in one pass
(displayln "select(group, value*cost as spend):")
(displayln (~> df
               (select (col "group")
                       (~> (col "value") (* (col "cost")) (alias "spend")))))
(newline)

;; filter via Expr predicate:  (value > 15) AND (cost < 3.0)
(displayln "filter(value>15 AND cost<3.0):")
(displayln (~> df (filter (and (> (col "value") 15) (< (col "cost") 3.0)))))
