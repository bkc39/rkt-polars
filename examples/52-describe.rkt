#lang racket/base

;; Summary statistics with `describe`, the Racket spelling of Polars'
;; df.describe() and s.describe().
;;
;; A dataframe gets the nine-row table: numeric and boolean columns as floats,
;; string and temporal columns as strings, with the mean and quartiles of a
;; date, datetime or duration column written as Python prints them.  A series
;; keeps only the rows its dtype has.  A lazy query is collected first.
;;
;; Inside `nix develop`:
;;   racket examples/52-describe.rkt

(require gregor
         polars)

(define flights
  (~> (dataframe [carrier (list "UA" "AA" "UA" polars-null "DL")]
                 [distance (list 1400 733 polars-null 1089 762)]
                 [on_time (list #t #f #t #t polars-null)]
                 [scheduled
                  (list (datetime 2013 1 1 5)
                        (datetime 2013 1 1 6)
                        (datetime 2013 1 2 7)
                        (datetime 2013 1 3 8)
                        (datetime 2013 1 3 9))]
                 [departed
                  (list (datetime 2013 1 1 5 12)
                        (datetime 2013 1 1 5 57)
                        polars-null
                        (datetime 2013 1 3 9 30)
                        (datetime 2013 1 3 9 4))])
      (with-columns (alias (- (col "departed") (col "scheduled")) "delay")
                    (alias (cast "scheduled" 'date) "day"))))

(displayln "flights:")
(displayln flights)
(newline)

(displayln "describe: numeric, string, boolean and temporal columns, with nulls")
(displayln (describe flights))
(newline)

(displayln "describe on a series: a number column, then a date column")
(displayln (describe (ref flights "distance")))
(displayln (describe (ref flights "day")))
(newline)

(displayln "describe on a collected lazy query: the flights that left late")
(displayln
 (~> flights
     lazy
     (filter (> (col "departed") (col "scheduled")))
     (select "carrier" "distance" "delay")
     collect
     describe))
