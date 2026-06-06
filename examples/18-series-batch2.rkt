#lang racket/base

;; Series batch 2: cast, std/var, series-series comparisons, arithmetic — all
;; prefix-free on eager series.
;;
;; Inside `nix develop`:
;;   racket examples/18-series-batch2.rkt

(require polars)

(define x (series (list 1 2 polars-null 4) #:name "x" #:dtype 'i32))
(define y (series '(10 20 30 40)            #:name "y" #:dtype 'i32))

(define x64 (cast x 'float64))

(printf "x dtype=~a x64 dtype=~a\n" (dtype x) (dtype x64))
(printf "x64[0]=~a x64[2]=~a\n" (ref x64 0) (ref x64 2))

(define stats (series '(1.0 2.0 3.0 4.0) #:name "stats"))

(printf "sample variance=~a population std=~a\n"
        (var stats)
        (std stats #:ddof 0))

(define eq-mask (= x y))
(define xy-sum  (+ x y))
(define ratio   (/ (cast y 'float64) (cast x 'float64)))

(printf "x == y at row 0? ~a\n" (ref eq-mask 0))
(printf "x + y at row 1 = ~a\n" (ref xy-sum 1))
(printf "x + y at row 2 = ~a\n" (ref xy-sum 2))
(printf "y / x at row 1 = ~a\n" (ref ratio 1))
