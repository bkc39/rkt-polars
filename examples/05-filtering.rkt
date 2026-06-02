#lang racket/base

;; Filter recipes — the comparison suite (`> < >= <= = !=`) and the logical
;; combinators (`and` / `or` / `not`) expressed as Polars-style `~>` / `filter`
;; pipelines over Expr predicates, on the same frame as example 03.  Each recipe
;; mirrors `df.filter(expr)` in Polars Python:
;;
;;   df.filter(pl.col("value") > 15)              (~> df (filter (> (col "value") 15)))
;;   df.filter((a >= 10) & (a <= 25))             (~> df (filter (and ...)))
;;   df.filter(~(pl.col("group") == "a"))         (~> df (filter (not ...)))
;;
;; `~>`, `col`, `filter`, the comparison operators, and the `and`/`or`/`not`
;; combinators all come from `(require polars)` — no `expr-`/`series-` prefixes.
;;
;; Inside `nix develop`:
;;   racket examples/05-filtering.rkt

(require polars)

(define df
  (dataframe
   (list (series '("a" "a" "b" "b" "c") #:name "group")
         (series '(10 25 7 30 18)        #:name "value" #:dtype 'i32)
         (series '(1.2 2.4 0.5 3.1 1.8)  #:name "cost"))))

(displayln "input:")
(displayln df)
(newline)

;; Recipe 1: numeric range — value between 10 and 25 inclusive
;;   df.filter((pl.col("value") >= 10) & (pl.col("value") <= 25))
(displayln "value in [10, 25]:")
(displayln (~> df (filter (and (>= (col "value") 10)
                               (<= (col "value") 25)))))
(newline)

;; Recipe 2: string equality — df.filter(pl.col("group") == "b")
(displayln "group == \"b\":")
(displayln (~> df (filter (= (col "group") "b"))))
(newline)

;; Recipe 3: f64 comparison — df.filter(pl.col("cost") > 2.0)
(displayln "cost > 2.0:")
(displayln (~> df (filter (> (col "cost") 2.0))))
(newline)

;; Recipe 4: multi-clause — (value > 15) AND (group == "a")
;;   df.filter((pl.col("value") > 15) & (pl.col("group") == "a"))
(displayln "value > 15 AND group == \"a\":")
(displayln (~> df (filter (and (> (col "value") 15)
                               (= (col "group") "a")))))
(newline)

;; Recipe 5: negation — NOT (group == "a")
;;   df.filter(~(pl.col("group") == "a"))
(displayln "NOT group == \"a\":")
(displayln (~> df (filter (~> (= (col "group") "a") not))))
