#lang racket/base

;; polars-null as a literal, Python's pl.lit(None); is-in with an empty
;; list; and reductions of an empty or all-null series.
;;
;; Inside `nix develop`:
;;   racket examples/74-null-literal.rkt

(require polars)

(define df
  (dataframe (list (series (list 1 polars-null 3) #:name "x"))))

(displayln
 (~> df
     (with-columns
       (alias (lit polars-null) "nothing")
       (alias (= (col "x") polars-null) "eq_null")
       (alias (+ (col "x") polars-null) "plus_null")
       (alias (is-in "x" '()) "in_empty")
       (alias (~> (when (> (col "x") 1)) (then polars-null) (otherwise (col "x")))
              "small_only"))))

(define no-rows (series '() #:dtype 'int64))
(define all-null (series (list polars-null polars-null) #:dtype 'float64))
(for ([reduce (list sum mean min max std var n-unique)]
      [name '(sum mean min max std var n-unique)])
  (printf "~a: ~v ~v\n" name (reduce no-rows) (reduce all-null)))
