#lang racket/base

;; Series typed reductions for i64/u32/u64.
;;
;; sum / min / max / mean dispatch on the series dtype, so the same four
;; verbs cover every integer width.
;;
;; Inside `nix develop`:
;;   racket examples/27-series-typed-reductions.rkt

(require polars)

(define wide  (series (list 1099511627776 polars-null 4) #:name "wide"  #:dtype 'i64))
(define count (series (list 1 2 polars-null 7)           #:name "count" #:dtype 'u32))
(define big   (series '(10 20 4294967296)                #:name "big"   #:dtype 'u64))

(printf "wide sum=~a min=~a max=~a mean=~a\n"
        (sum wide) (min wide) (max wide) (mean wide))

(printf "count sum=~a min=~a max=~a mean=~a\n"
        (sum count) (min count) (max count) (mean count))

(printf "big sum=~a min=~a max=~a mean=~a\n"
        (sum big) (min big) (max big) (mean big))
