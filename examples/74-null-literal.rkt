#lang racket/base

;; polars-null as a literal, Python's pl.lit(None); is-in with an empty
;; list; and reductions of an empty or all-null series.
;;
;; Inside `nix develop`:
;;   racket examples/74-null-literal.rkt

(require polars (only-in racket/match match-define))

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
(for ([named (list (cons 'sum sum) (cons 'mean mean) (cons 'min min) (cons 'max max)
                   (cons 'std std) (cons 'var var) (cons 'n-unique n-unique))])
  (match-define (cons name reduce) named)
  (printf "~a: ~v ~v\n" name (reduce no-rows) (reduce all-null)))
