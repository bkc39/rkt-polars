#lang racket/base

;; std / var with #:ddof — sample (default ddof=1) vs population (ddof=0), at
;; top level and inside group-by/agg.  Mirrors:
;;   col("v").std().alias("sample_std")  ->  (~> (col "v") std (alias "sample_std"))
;;   col("v").std(ddof=0)                ->  (~> (col "v") (std #:ddof 0) ...)
;;
;; Inside `nix develop`:
;;   racket examples/17-expr-std-var.rkt

(require polars)

(define df
  (dataframe (list (series '(2.0 4.0 4.0 6.0) #:name "v"))))

(displayln "input:")
(displayln df)
(newline)

;; mean=4, deviations {-2,0,0,2}; sample var=8/3, pop var=2.0.
(displayln "select(std, var, std ddof=0, var ddof=0):")
(displayln (~> df
               (select (~> (col "v") std (alias "sample_std"))
                       (~> (col "v") var (alias "sample_var"))
                       (~> (col "v") (std #:ddof 0) (alias "pop_std"))
                       (~> (col "v") (var #:ddof 0) (alias "pop_var")))))
(newline)

;; std/var inside a group-by/agg pipeline.
(define df-grp
  (dataframe (list (series '("a" "a" "a" "b" "b" "b")   #:name "g")
                   (series '(1.0 2.0 3.0 10.0 20.0 30.0) #:name "v"))))

(displayln "group_by(g).agg(mean, sample std, pop var):")
(displayln (~> df-grp
               (group-by "g")
               (agg (~> (col "v") mean (alias "mean_v"))
                    (~> (col "v") std  (alias "std_v"))
                    (~> (col "v") (var #:ddof 0) (alias "pop_var_v")))))
