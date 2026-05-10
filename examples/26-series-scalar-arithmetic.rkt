#lang racket/base

;; Series scalar arithmetic.
;;
;; Inside `nix develop`:
;;   racket examples/26-series-scalar-arithmetic.rkt

(require polars)

(define x
  (series-new-i32 "x" (list 1 2 polars-null 4)))

(define f
  (series-new-f64 "f" '(3.0 7.5 11.0)))

(define shifted (series-add-i32 x 5))
(define scaled (series-mul-i32 x 3))
(define ratio (series-div-f64 f 2.5))
(define remainder (series-mod-f64 f 2.0))

(printf "shifted dtype=~a row0=~a row2=~a\n"
        (series-dtype shifted)
        (series-ref shifted 0)
        (series-ref shifted 2))
(printf "scaled row3=~a\n" (series-ref scaled 3))
(printf "ratio row1=~a\n" (series-ref ratio 1))
(printf "remainder row1=~a\n" (series-ref remainder 1))
