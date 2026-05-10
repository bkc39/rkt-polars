#lang racket/base

;; Series batch 2: cast, std/var, series-series comparisons, arithmetic.
;;
;; Inside `nix develop`:
;;   racket examples/18-series-batch2.rkt

(require polars)

(define x
  (series-new-i32 "x" (list 1 2 polars-null 4)))

(define y
  (series-new-i32 "y" '(10 20 30 40)))

(define x64 (series-cast x 'float64))

(printf "x dtype=~a x64 dtype=~a\n"
        (series-dtype x)
        (series-dtype x64))
(printf "x64[0]=~a x64[2]=~a\n"
        (series-ref x64 0)
        (series-ref x64 2))

(define stats
  (series-new-f64 "stats" '(1.0 2.0 3.0 4.0)))

(printf "sample variance=~a population std=~a\n"
        (series-var stats)
        (series-std stats #:ddof 0))

(define eq-mask (series-eq x y))
(define sum (series-add x y))
(define ratio (series-div (series-cast y 'float64)
                          (series-cast x 'float64)))

(printf "x == y at row 0? ~a\n" (series-ref eq-mask 0))
(printf "x + y at row 1 = ~a\n" (series-ref sum 1))
(printf "x + y at row 2 = ~a\n" (series-ref sum 2))
(printf "y / x at row 1 = ~a\n" (series-ref ratio 1))
