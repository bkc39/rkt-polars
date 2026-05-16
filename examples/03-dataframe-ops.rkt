#lang racket/base

;; Mirror of rust/examples/03_dataframe_ops.rs.
;;
;; Inside `nix develop`:
;;   racket examples/03-dataframe-ops.rkt

(require polars)

(define df
  (dataframe-new
   (list (series-new-str "group" '("a" "a" "b" "b" "c"))
         (series-new-i32 "value" '(10 25 7 30 18))
         (series-new-f64 "cost"  '(1.2 2.4 0.5 3.1 1.8)))))

(displayln "input:")
(display-dataframe df)
(newline)

;; filter value > 15
(define value-mask (series-gt-i32 (dataframe-column df "value") 15))
(define filtered (dataframe-filter df value-mask))
(displayln "filtered value > 15:")
(display-dataframe filtered)
(newline)

;; sort by group asc, value desc
(define sorted (dataframe-sort df '("group" "value") #:descending '(#f #t)))
(displayln "sorted by group asc, value desc:")
(display-dataframe sorted)
(newline)

;; group by group, sum(value)
(define grouped (dataframe-group-by-sum df #:by '("group") #:agg '("value")))
(displayln "grouped sum(value):")
(display-dataframe grouped)
