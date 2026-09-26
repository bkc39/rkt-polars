#lang racket/base

;; Sorting with nulls last: the "five longest delays" question from the
;; nycflights data, on a small fixture with cancelled flights (null delays).
;;
;;   df.sort("dep_delay", descending=True, nulls_last=True).head(5)
;;   df.sort(["carrier", "dep_delay"], descending=[False, True],
;;           nulls_last=[False, True], maintain_order=True)
;;   pl.col("dep_delay").sort(descending=True, nulls_last=True)
;;
;; Inside `nix develop`:
;;   racket examples/57-sort-nulls-last.rkt

(require polars)

(define flights
  (dataframe
   (list (series '("UA" "AA" "UA" "B6" "AA" "B6" "UA" "AA" "B6" "UA") #:name "carrier")
         (series '("IAH" "MIA" "ORD" "BOS" "DFW" "FLL" "SFO" "ORD" "MCO" "DEN") #:name "dest")
         (series (list 2 polars-null 1301 -5 137 polars-null 44 1014 polars-null 9)
                 #:name "dep_delay"))))

;; Descending puts the nulls first, as in Python: the top rows are cancellations.
(displayln (~> flights (sort "dep_delay" #:descending #t) (head 5)))

;; #:nulls-last answers the question.
(displayln (~> flights (sort "dep_delay" #:descending #t #:nulls-last #t) (head 5)))

;; Per-key flags: carrier ascending, then delay descending with its nulls
;; last; ties keep their input order.
(displayln (sort flights '("carrier" "dep_delay")
                 #:descending '(#f #t) #:nulls-last '(#f #t) #:maintain-order #t))

;; The expression sort, per carrier: the worst delay and the delays in order.
(displayln
 (~> flights
     (group-by "carrier")
     (agg (alias (first (sort "dep_delay" #:descending #t #:nulls-last #t)) "worst")
          (alias (sort "dep_delay" #:nulls-last #t) "delays"))
     (sort "carrier")))

;; The same top five from a lazy plan.
(displayln (~> flights lazy (sort "dep_delay" #:descending #t #:nulls-last #t) (head 5) collect))
