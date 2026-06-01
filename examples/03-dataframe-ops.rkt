#lang racket/base

;; Mirror of rust/examples/03_dataframe_ops.rs.
;;
;; Polars' Python method chaining maps onto Racket's thread-first `~>`:
;;
;;   df.filter(pl.col("value") > 15)            (~> df (filter (> (col "value") 15)))
;;   df.sort(["group","value"], ...)            (~> df (sort '("group" "value") ...))
;;   df.group_by("group").agg(col("value")...)  (~> df (group-by "group") (agg ...))
;;
;; `~>`, the comparison operators, `filter`/`sort`/`group-by`/`agg`, and the
;; aggregators (`sum`, …) all come from `(require polars)`.
;;
;; Inside `nix develop`:
;;   racket examples/03-dataframe-ops.rkt

(require polars)

;; Build the frame with the smart `series` / `dataframe` constructors (example 02).
(define df
  (dataframe
   (list (series '("a" "a" "b" "b" "c")     #:name "group")
         (series '(10 25 7 30 18)           #:name "value" #:dtype 'i32)
         (series '(1.2 2.4 0.5 3.1 1.8)     #:name "cost"))))

(displayln "input:")
(displayln df)
(newline)

;; filter value > 15  —  df.filter(pl.col("value") > 15)
(displayln "filtered value > 15:")
(displayln (~> df (filter (> (col "value") 15))))
(newline)

;; sort by group asc, value desc  —  df.sort([...], descending=[False, True])
(displayln "sorted by group asc, value desc:")
(displayln (~> df (sort '("group" "value") #:descending '(#f #t))))
(newline)

;; group by group, sum(value)  —  df.group_by("group").agg(pl.col("value").sum())
(displayln "grouped sum(value):")
(displayln (~> df
               (group-by "group")
               (agg (sum (col "value")))))
