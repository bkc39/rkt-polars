#lang racket/base

;; rkt-polars user guide — Getting started: Expressions and contexts
;; Mirrors https://docs.pola.rs/user-guide/getting-started/#expressions-and-contexts
;; and expressions_and_contexts.py.
;;
;; Inside `nix develop`:
;;   racket user-guide/getting-started/expressions-and-contexts.rkt

(require gregor
         polars)

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

;; --- select --------------------------------------------------------------
(displayln
 (~> df
     (select "name"
             (alias (dt-year "birthdate") "birth_year")
             (alias (/ (col "weight") (pow (col "height") 2)) "bmi"))))

;; API gap: no multi-column col("weight", "height") and no name.suffix, so
;; each column is spelled out.
(displayln
 (~> df
     (select "name"
             (alias (round (* (col "weight") 0.95) #:decimals 2) "weight-5%")
             (alias (round (* (col "height") 0.95) #:decimals 2) "height-5%"))))

;; --- with-columns --------------------------------------------------------
(displayln
 (~> df
     (with-columns (alias (dt-year "birthdate") "birth_year")
                   (alias (/ (col "weight") (pow (col "height") 2)) "bmi"))))

;; --- filter --------------------------------------------------------------
(displayln
 (~> df (filter (< (dt-year "birthdate") 1990))))

;; API gaps: no date literals (cast a string instead), and filter takes a
;; single predicate, so the two conditions are joined with `and`.
(displayln
 (~> df
     (filter (and (is-between "birthdate"
                              (cast (lit "1982-12-31") 'date)
                              (cast (lit "1996-01-01") 'date))
                  (> (col "height") 1.7)))))

;; --- group-by ------------------------------------------------------------
;; `/` on an integer column is integer division, so Python's `// 10 * 10` is
;; `(* (/ ... 10) 10)`.  API gaps: no maintain_order, no pl.len().
(define decade (alias (* (/ (dt-year "birthdate") 10) 10) "decade"))

(displayln
 (~> df (group-by decade) (agg (alias (count "name") "len"))))

(displayln
 (~> df
     (group-by decade)
     (agg (alias (count "name") "sample_size")
          (alias (round (mean "weight") #:decimals 2) "avg_weight")
          (alias (max "height") "tallest"))))

;; --- more complex queries ------------------------------------------------
;; API gaps: no str.split / list.first (str-extract with a regex instead), no
;; all().exclude (drop instead), no name.prefix (alias each column).
(displayln
 (~> df
     (with-columns decade
                   (str-extract "name" "^(\\S+)"))
     (drop "birthdate")
     (group-by "decade")
     (agg (col "name")
          (alias (round (mean "weight") #:decimals 2) "avg_weight")
          (alias (round (mean "height") #:decimals 2) "avg_height"))))
