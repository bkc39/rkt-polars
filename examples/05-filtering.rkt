#lang racket/base

;; Filter recipes — exercises the comparison suite (Phase 2) and
;; boolean Series ops (Phase 3) on the example-3 dataframe.
;;
;; Inside `nix develop`:
;;   racket examples/05-filtering.rkt

(require polars/private/foreign)

(define df
  (dataframe-new
   (list (series-new-str "group" '("a" "a" "b" "b" "c"))
         (series-new-i32 "value" '(10 25 7 30 18))
         (series-new-f64 "cost"  '(1.2 2.4 0.5 3.1 1.8)))))

(displayln "input:")
(display-dataframe df)
(newline)

;; Recipe 1: numeric range — value between 10 and 25 inclusive
(define lo (series-ge-i32 (dataframe-column df "value") 10))
(define hi (series-le-i32 (dataframe-column df "value") 25))
(displayln "value in [10, 25]:")
(display-dataframe (dataframe-filter df (series-and lo hi)))
(newline)

;; Recipe 2: string equality
(displayln "group == \"b\":")
(display-dataframe
 (dataframe-filter df (series-eq-str (dataframe-column df "group") "b")))
(newline)

;; Recipe 3: f64 comparison
(displayln "cost > 2.0:")
(display-dataframe
 (dataframe-filter df (series-gt-f64 (dataframe-column df "cost") 2.0)))
(newline)

;; Recipe 4: multi-clause — (value > 15) AND (group == "a")
(define big-value (series-gt-i32 (dataframe-column df "value") 15))
(define group-a   (series-eq-str (dataframe-column df "group") "a"))
(displayln "value > 15 AND group == \"a\":")
(display-dataframe (dataframe-filter df (series-and big-value group-a)))
(newline)

;; Recipe 5: negation — NOT (group == "a")
(displayln "NOT group == \"a\":")
(display-dataframe (dataframe-filter df (series-not group-a)))
