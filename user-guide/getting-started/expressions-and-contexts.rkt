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
             (~> (col "birthdate") dt-year (alias "birth_year"))
             (~> (col "weight") (/ (pow (col "height") 2)) (alias "bmi")))))

;; API gap: no multi-column col("weight", "height") and no name.suffix, so
;; each column is spelled out.
(displayln
 (~> df
     (select "name"
             (~> (col "weight") (* 0.95) (round #:decimals 2) (alias "weight-5%"))
             (~> (col "height") (* 0.95) (round #:decimals 2) (alias "height-5%")))))

;; --- with-columns --------------------------------------------------------
(displayln
 (~> df
     (with-columns (~> (col "birthdate") dt-year (alias "birth_year"))
                   (~> (col "weight") (/ (pow (col "height") 2)) (alias "bmi")))))

;; --- filter --------------------------------------------------------------
(displayln
 (~> df (filter (< (dt-year "birthdate") 1990))))

;; API gaps: no date literals (cast a string instead), and filter takes a
;; single predicate, so the two conditions are joined with `and`.
(displayln
 (~> df
     (filter (and (is-between "birthdate"
                              (str-to-date (lit "1982-12-31"))
                              (str-to-date (lit "1996-01-01")))
                  (> (col "height") 1.7)))))

;; --- group-by ------------------------------------------------------------
;; `/` on an integer column is integer division, so Python's `// 10 * 10` is
;; `(* (/ ... 10) 10)`.  API gaps: no maintain_order, no pl.len().
(define decade
  (~> (col "birthdate") dt-year (/ 10) (* 10) (alias "decade")))

(displayln
 (~> df (group-by decade) (agg (~> (col "name") count (alias "len")))))

(displayln
 (~> df
     (group-by decade)
     (agg (~> (col "name") count (alias "sample_size"))
          (~> (col "weight") mean (round #:decimals 2) (alias "avg_weight"))
          (~> (col "height") max (alias "tallest")))))

;; --- more complex queries ------------------------------------------------
;; API gaps: no str.split / list.first (str-extract with a regex instead), no
;; name.prefix (alias each column).
(displayln
 (~> df
     (with-columns decade
                   (str-extract "name" "^(\\S+)"))
     (select (exclude (all) "birthdate"))
     (group-by "decade")
     (agg (col "name")
          (~> (col "weight") mean (round #:decimals 2) (alias "avg_weight"))
          (~> (col "height") mean (round #:decimals 2) (alias "avg_height")))))
