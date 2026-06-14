#lang racket/base

;; DataFrame aggregations + dedup / null cleanup, in the fluent `~>` style:
;; df.group_by("group").agg(col("value").sum(), ...) maps onto
;; (~> df (group-by "group") (agg (sum (col "value")) ...)).
;;
;; Inside `nix develop`:
;;   racket examples/09-aggregations.rkt

(require racket/file              ; make-temporary-file
         polars)

(define df
  (dataframe
   (list (series '("a" "a" "b" "b" "c") #:name "group")
         (series '(10 25 7 30 18)        #:name "value" #:dtype 'i32)
         (series '(1.2 2.4 0.5 3.1 1.8)  #:name "cost"))))

(displayln "input:")
(displayln df)
(newline)

(displayln "group-by sum (value, cost):")
(displayln (~> df (group-by "group") (agg (sum (col "value")) (sum (col "cost")))))
(newline)

(displayln "group-by mean:")
(displayln (~> df (group-by "group") (agg (mean (col "value")) (mean (col "cost")))))
(newline)

(displayln "group-by min:")
(displayln (~> df (group-by "group") (agg (min (col "value")))))
(newline)

(displayln "group-by max:")
(displayln (~> df (group-by "group") (agg (max (col "value")))))
(newline)

(displayln "group-by count:")
(displayln (~> df (group-by "group") (agg (count (col "value")))))
(newline)

;; Dedup
(define dup-df
  (dataframe
   (list (series '(1 2 1 3 2 1)            #:name "x" #:dtype 'i32)
         (series '("a" "b" "a" "c" "b" "a") #:name "y"))))

(displayln "duplicates:")
(displayln dup-df)
(newline)

(displayln "unique rows:")
(displayln (unique dup-df))
(newline)

;; Null cleanup via CSV
(define csv-path (make-temporary-file "rkt-polars-dropnulls-~a.csv"))
(with-output-to-file csv-path #:exists 'replace
  (lambda ()
    (displayln "name,score")
    (displayln "alice,10")
    (displayln "bob,")
    (displayln "carol,30")
    (displayln ",40")))
(define np-df (read-csv csv-path))

(displayln "with nulls:")
(displayln np-df)
(newline)

(displayln "after drop-nulls:")
(displayln (drop-nulls np-df))
(delete-file csv-path)
