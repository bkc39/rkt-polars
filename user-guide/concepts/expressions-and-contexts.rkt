#lang racket/base

;; rkt-polars user guide — Concepts: Expressions and contexts
;; Mirrors https://docs.pola.rs/user-guide/concepts/expressions-and-contexts/
;; and expressions_and_contexts.py.
;;
;; Inside `nix develop`:
;;   racket user-guide/concepts/expressions-and-contexts.rkt

(require gregor
         polars)

;; --- expressions ---------------------------------------------------------
(define bmi-expr (/ (col "weight") (pow (col "height") 2)))

;; API gap: an expression prints as an opaque pointer, not as its plan.
(displayln bmi-expr)

;; --- contexts ------------------------------------------------------------
(define df
  (~> (dataframe
       (list (series '("Alice Archer" "Ben Brown" "Chloe Cooper" "Daniel Donovan")
                     #:name "name")
             (series (list (datetime 1997 1 10) (datetime 1985 2 15)
                           (datetime 1983 3 22) (datetime 1981 4 30))
                     #:name "birthdate")
             (series '(57.9 72.5 53.6 83.1) #:name "weight")
             (series '(1.56 1.77 1.65 1.75) #:name "height")))
      (with-columns (cast "birthdate" 'date))))

(displayln df)

;; select
(displayln
 (~> df
     (select (alias bmi-expr "bmi")
             (alias (mean bmi-expr) "avg_bmi")
             (alias (lit 25) "ideal_max_bmi"))))

(displayln
 (~> df
     (select (alias (/ (- bmi-expr (mean bmi-expr)) (std bmi-expr)) "deviation"))))

;; with-columns
(displayln
 (~> df
     (with-columns (alias bmi-expr "bmi")
                   (alias (mean bmi-expr) "avg_bmi")
                   (alias (lit 25) "ideal_max_bmi"))))

;; filter
;; API gaps: no date literals (cast a string instead), and filter takes a
;; single predicate, so the two conditions are joined with `and`.
(displayln
 (~> df
     (filter (and (is-between "birthdate"
                              (cast (lit "1982-12-31") 'date)
                              (cast (lit "1996-01-01") 'date))
                  (> (col "height") 1.7)))))

;; group-by and aggregations
;; `/` on an integer column is integer division, so Python's `// 10 * 10` is
;; `(* (/ ... 10) 10)`.
(define decade (alias (* (/ (dt-year "birthdate") 10) 10) "decade"))

(displayln
 (~> df (group-by decade) (agg (col "name"))))

(displayln
 (~> df
     (group-by decade (alias (< (col "height") 1.7) "short?"))
     (agg (col "name"))))

;; API gaps: no pl.len() (count a column instead), no multi-column col(...)
;; and no name.prefix (alias each column).
(displayln
 (~> df
     (group-by decade (alias (< (col "height") 1.7) "short?"))
     (agg (alias (count "name") "len")
          (alias (max "height") "tallest")
          (alias (mean "weight") "avg_weight")
          (alias (mean "height") "avg_height"))))

;; --- expression expansion ------------------------------------------------
;; API gap: no dtype selector col(pl.Float64) and no name.suffix, so there is
;; no expression that expands over "all float columns"; spell them out.
(displayln
 (~> df
     (select (alias (* (col "weight") 1.1) "weight*1.1")
             (alias (* (col "height") 1.1) "height*1.1"))))
