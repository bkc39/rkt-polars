#lang racket/base

;; Series reshaping — head/tail/slice/reverse/unique/sort/drop-nulls.
;;
;; Inside `nix develop`:
;;   racket examples/07-reshaping.rkt

(require racket/file
         polars)

(define df
  (dataframe-new
   (list (series-new-str "city" '("Boston" "New York" "Chicago" "Houston"
                                  "Phoenix" "Philadelphia" "San Antonio"
                                  "San Diego"))
         (series-new-i32 "founded" '(1630 1624 1837 1837 1881 1682 1718 1769)))))

(displayln "input:")
(display-dataframe df)
(newline)

(define founded (dataframe-column df "founded"))

(printf "founded head 3 sum: ~a\n" (series-sum-i32 (series-head founded 3)))
(printf "founded tail 3 sum: ~a\n" (series-sum-i32 (series-tail founded 3)))
(printf "founded slice (offset=2 length=3) sum: ~a\n"
        (series-sum-i32 (series-slice founded 2 3)))
(printf "founded reverse first: ~a\n"
        (series-min-i32 (series-head (series-reverse founded) 1)))
(printf "founded n_unique: ~a\n" (series-n-unique founded))
(printf "founded unique len: ~a\n" (series-len (series-unique founded)))
(newline)

;; Sort: ascending then descending
(define sorted-asc  (series-sort founded))
(define sorted-desc (series-sort founded #:descending #t))
(printf "earliest founded: ~a (sort ascending, head 1 min)\n"
        (series-min-i32 (series-head sorted-asc 1)))
(printf "latest founded:   ~a (sort descending, head 1 max)\n"
        (series-max-i32 (series-head sorted-desc 1)))

;; drop-nulls: round-trip a CSV with an empty cell to demonstrate.
(define csv-path (build-path (find-system-path 'temp-dir)
                             "rkt-polars-reshape-demo.csv"))
(with-output-to-file csv-path #:exists 'replace
  (lambda ()
    (displayln "name,score")
    (displayln "alice,10")
    (displayln "bob,")
    (displayln "carol,30")))

(define csv-df (dataframe-read-csv csv-path))
(define score (dataframe-column csv-df "score"))
(printf "\nscore from csv (with one empty cell):\n")
(printf "  series-len:        ~a\n" (series-len score))
(printf "  series-null-count: ~a\n" (series-null-count score))
(printf "  after drop-nulls:  ~a\n" (series-len (series-drop-nulls score)))
(delete-file csv-path)
