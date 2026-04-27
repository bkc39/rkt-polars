#lang racket/base

;; DataFrame row + column shaping — head/tail/slice and
;; select/drop/rename/with-column.
;;
;; Inside `nix develop`:
;;   racket examples/08-dataframe-shaping.rkt

(require polars/private/foreign)

(define df
  (dataframe-new
   (list (series-new-str "city" '("Boston" "New York" "Chicago" "Houston"
                                  "Phoenix" "Philadelphia" "San Antonio"
                                  "San Diego"))
         (series-new-f64 "population_millions"
                         '(0.65 8.8 2.7 2.3 1.6 1.6 1.5 1.4))
         (series-new-i32 "founded"
                         '(1630 1624 1837 1837 1881 1682 1718 1769)))))

(displayln "input:")
(display-dataframe df)
(newline)

(printf "column names: ~a\n" (dataframe-column-names df))
(printf "shape: ~a x ~a\n" (dataframe-height df) (dataframe-width df))
(newline)

(displayln "head 3:")
(display-dataframe (dataframe-head df 3))
(newline)

(displayln "tail 3:")
(display-dataframe (dataframe-tail df 3))
(newline)

(displayln "slice (offset=2, length=3):")
(display-dataframe (dataframe-slice df 2 3))
(newline)

(displayln "select [city, founded]:")
(display-dataframe (dataframe-select df '("city" "founded")))
(newline)

(displayln "drop [population_millions]:")
(display-dataframe (dataframe-drop-columns df '("population_millions")))
(newline)

(displayln "rename founded -> year_founded:")
(display-dataframe (dataframe-rename df "founded" "year_founded"))
(newline)

;; with-column: derive a new column from an existing one.  We don't
;; have arithmetic yet, but we can construct a new Series independently.
(define century
  (series-new-i32 "century" '(17 17 19 19 19 17 18 18)))
(displayln "with-column century:")
(display-dataframe (dataframe-with-column df century))
