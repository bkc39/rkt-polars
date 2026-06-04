#lang racket/base

;; DataFrame row + column shaping — head / tail / slice and
;; select / drop / rename / with-column, all prefix-free and data-first, so
;; every step threads with `~>`.  The select section mirrors the examples on
;; the Polars `DataFrame.select` page.
;;
;; Inside `nix develop`:
;;   racket examples/08-dataframe-shaping.rkt

(require polars)

(define df
  (dataframe
   (list (series '("Boston" "New York" "Chicago" "Houston"
                   "Phoenix" "Philadelphia" "San Antonio" "San Diego")
                 #:name "city")
         (series '(0.65 8.8 2.7 2.3 1.6 1.6 1.5 1.4)
                 #:name "population_millions")
         (series '(1630 1624 1837 1837 1881 1682 1718 1769)
                 #:name "founded" #:dtype 'i32))))

(displayln "input:")
(displayln df)
(newline)

(printf "column names: ~a\n" (column-names df))
(printf "shape: ~a x ~a\n" (height df) (width df))
(newline)

(displayln "head 3:")
(displayln (~> df (head 3)))
(newline)

(displayln "tail 3:")
(displayln (~> df (tail 3)))
(newline)

(displayln "slice (offset=2, length=3):")
(displayln (~> df (slice 2 3)))
(newline)

(displayln "select [city, founded]:")
(displayln (~> df (select '("city" "founded"))))
(newline)

(displayln "drop [population_millions]:")
(displayln (~> df (drop '("population_millions"))))
(newline)

(displayln "rename founded -> year_founded:")
(displayln (~> df (rename "founded" "year_founded")))
(newline)

;; with-column: attach a separately-built Series as a new column.
(define century (series '(17 17 19 19 19 17 18 18) #:name "century" #:dtype 'i32))
(displayln "with-column century:")
(displayln (~> df (with-column century)))
(newline)

;; ---------------------------------------------------------------------------
;; select recipes — parity with Polars' DataFrame.select examples.
;; `select` is variadic and expression-aware: names, lists of names, and Exprs.

(define sdf
  (dataframe (list (series '(1 2 3)       #:name "foo" #:dtype 'i32)
                   (series '(6 7 8)       #:name "bar" #:dtype 'i32)
                   (series '("a" "b" "c") #:name "ham"))))

;; 1. a single column by name           df.select("foo")
(displayln "select \"foo\":")
(displayln (~> sdf (select "foo")))
(newline)

;; 2. multiple columns by a list         df.select(["foo", "bar"])
(displayln "select '(\"foo\" \"bar\"):")
(displayln (~> sdf (select '("foo" "bar"))))
(newline)

;; 3. positional columns + an expression  df.select(pl.col("foo"), pl.col("bar") + 1)
(displayln "select (col foo) (bar + 1):")
(displayln (~> sdf (select (col "foo") (alias (+ (col "bar") 1) "bar"))))
(newline)

;; 4. a named when/then expression
;;    df.select(threshold = pl.when(pl.col("foo") > 2).then(10).otherwise(0))
(displayln "select threshold = when foo>2 then 10 else 0:")
(displayln (~> sdf (select (~> (when (> (col "foo") 2))
                               (then 10)
                               (otherwise 0)
                               (alias "threshold")))))
