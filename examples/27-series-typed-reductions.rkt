#lang racket/base

;; Series typed reductions for i64/u32/u64.
;;
;; Inside `nix develop`:
;;   racket examples/27-series-typed-reductions.rkt

(require polars)

(define wide
  (series-new-i64 "wide" (list 1099511627776 polars-null 4)))
(define count
  (series-new-u32 "count" (list 1 2 polars-null 7)))
(define big
  (series-new-u64 "big" '(10 20 4294967296)))

(printf "wide sum=~a min=~a max=~a mean=~a\n"
        (series-sum-i64 wide)
        (series-min-i64 wide)
        (series-max-i64 wide)
        (series-mean-i64 wide))

(printf "count sum=~a min=~a max=~a mean=~a\n"
        (series-sum-u32 count)
        (series-min-u32 count)
        (series-max-u32 count)
        (series-mean-u32 count))

(printf "big sum=~a min=~a max=~a mean=~a\n"
        (series-sum-u64 big)
        (series-min-u64 big)
        (series-max-u64 big)
        (series-mean-u64 big))
