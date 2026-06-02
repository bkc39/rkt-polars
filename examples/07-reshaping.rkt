#lang racket/base

;; Series reshaping — head / tail / slice / reverse / unique / sort / drop-nulls.
;; All prefix-free and data-first, so each reshaping step threads with `~>`:
;;   s.head(3).sum()   ->  (~> founded (head 3) sum)
;;
;; Inside `nix develop`:
;;   racket examples/07-reshaping.rkt

(require polars)

(define df
  (dataframe
   (list (series '("Boston" "New York" "Chicago" "Houston"
                   "Phoenix" "Philadelphia" "San Antonio" "San Diego")
                 #:name "city")
         (series '(1630 1624 1837 1837 1881 1682 1718 1769)
                 #:name "founded" #:dtype 'i32))))

(displayln "input:")
(displayln df)
(newline)

(define founded (ref df #:columns "founded"))

(printf "founded head 3 sum: ~a\n"                    (~> founded (head 3) sum))
(printf "founded tail 3 sum: ~a\n"                    (~> founded (tail 3) sum))
(printf "founded slice (offset=2 length=3) sum: ~a\n" (~> founded (slice 2 3) sum))
(printf "founded reverse first: ~a\n"                 (~> founded reverse (head 1) min))
(printf "founded n_unique: ~a\n"                      (n-unique founded))
(printf "founded unique len: ~a\n"                    (~> founded unique len))
(newline)

;; Sort: ascending then descending
(printf "earliest founded: ~a (sort ascending, head 1 min)\n"
        (~> founded sort (head 1) min))
(printf "latest founded:   ~a (sort descending, head 1 max)\n"
        (~> founded (sort #:descending #t) (head 1) max))

;; drop-nulls: round-trip a CSV with an empty cell to demonstrate.
(define csv-path (build-path (find-system-path 'temp-dir)
                             "rkt-polars-reshape-demo.csv"))
(with-output-to-file csv-path #:exists 'replace
  (lambda ()
    (displayln "name,score")
    (displayln "alice,10")
    (displayln "bob,")
    (displayln "carol,30")))

(define score (ref (read-csv csv-path) #:columns "score"))
(printf "\nscore from csv (with one empty cell):\n")
(printf "  len:        ~a\n" (len score))
(printf "  null-count: ~a\n" (null-count score))
(printf "  drop-nulls: ~a\n" (~> score drop-nulls len))
(delete-file csv-path)
