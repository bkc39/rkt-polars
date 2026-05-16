#lang racket/base

;; expr-std / expr-var with #:ddof — sample (default) vs population
;; statistics, both at top-level and inside group_by_agg.  Mirrors the
;; canonical Polars Python flow:
;;   df.select([col("v").std().alias("sample_std"),       # ddof=1
;;              col("v").std(ddof=0).alias("pop_std")])
;;   df.group_by("g").agg(col("v").std().alias("std_v"))
;;
;; Inside `nix develop`:
;;   racket examples/17-expr-std-var.rkt

(require polars)

(define df
  (dataframe-new
   (list (series-new-f64 "v" '(2.0 4.0 4.0 6.0)))))

(displayln "input:")
(display-dataframe df)
(newline)

;; mean=4, deviations {-2,0,0,2}
;;   sample variance (ddof=1) = 8/3 ≈ 2.6667, sample std ≈ 1.6330
;;   population (ddof=0)      = 8/4 = 2.0,    pop std    ≈ 1.4142
(define stats
  (dataframe-select-exprs
   df
   (list (expr-alias (expr-std (col "v"))           "sample_std")
         (expr-alias (expr-var (col "v"))           "sample_var")
         (expr-alias (expr-std (col "v") #:ddof 0)  "pop_std")
         (expr-alias (expr-var (col "v") #:ddof 0)  "pop_var"))))

(displayln "select(std, var, std ddof=0, var ddof=0):")
(display-dataframe stats)
(newline)

;; std/var inside a group_by_agg pipeline.
(define df-grp
  (dataframe-new
   (list (series-new-str "g" '("a" "a" "a" "b" "b" "b"))
         (series-new-f64 "v" '(1.0 2.0 3.0 10.0 20.0 30.0)))))

(define per-group
  (dataframe-group-by-agg
   df-grp
   '("g")
   (list (expr-alias (expr-mean (col "v"))         "mean_v")
         (expr-alias (expr-std  (col "v"))         "std_v")
         (expr-alias (expr-var  (col "v") #:ddof 0) "pop_var_v"))))

(displayln "group_by(g).agg(mean, sample std, pop var):")
(display-dataframe per-group)
