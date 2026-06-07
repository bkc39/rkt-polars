#lang racket/base

;; Expr conditional: when / then / else-when / otherwise.
;;
;; The threading builder mirrors Polars' chained when().then()...otherwise():
;; `when` starts it, `then` supplies a value, `else-when` adds a branch, and
;; `otherwise` closes it with the fallback.  then/otherwise auto-lift scalars.
;;
;; Inside `nix develop`:
;;   racket examples/34-expr-when-then.rkt

(require polars)

(define df
  (dataframe (list (series '(-3 0 4 12 7) #:name "x" #:dtype 'i32))))

(define out
  (~> df
      (with-columns
        ;; single when / then / otherwise
        (alias (~> (when (> (col "x") 0)) (then "pos") (otherwise "non-pos")) "sign")
        ;; chained when / then / else-when ... / otherwise
        (alias (~> (when (< (col "x") 0)) (then 0)
                   (else-when (= (col "x") 0)) (then 1)
                   (else-when (< (col "x") 10)) (then 2)
                   (otherwise 3))
               "bucket"))))

(displayln out)
