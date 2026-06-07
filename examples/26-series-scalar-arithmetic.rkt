#lang racket/base

;; Series scalar arithmetic.
;;
;; The arithmetic operators (+ - * / mod) dispatch on series: a scalar
;; right-hand side is broadcast across the elements, and nulls stay null.
;;
;; Inside `nix develop`:
;;   racket examples/26-series-scalar-arithmetic.rkt

(require polars)

(define x (series (list 1 2 polars-null 4) #:name "x" #:dtype 'i32))
(define f (series '(3.0 7.5 11.0)         #:name "f" #:dtype 'f64))

(define shifted   (+ x 5))
(define scaled    (* x 3))
(define ratio     (/ f 2.5))
(define remainder (mod f 2.0))

(printf "shifted dtype=~a row0=~a row2=~a\n"
        (dtype shifted)
        (ref shifted 0)
        (ref shifted 2))
(printf "scaled row3=~a\n" (ref scaled 3))
(printf "ratio row1=~a\n" (ref ratio 1))
(printf "remainder row1=~a\n" (ref remainder 1))
