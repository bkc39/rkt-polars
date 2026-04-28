#lang racket/base

;; DataFrame aggregations + dedup/null cleanup (DF Phases 3-4).
;;
;; Inside `nix develop`:
;;   racket examples/09-aggregations.rkt

(require racket/file
         polars/private/foreign)

(define df
  (dataframe-new
   (list (series-new-str "group" '("a" "a" "b" "b" "c"))
         (series-new-i32 "value" '(10 25 7 30 18))
         (series-new-f64 "cost"  '(1.2 2.4 0.5 3.1 1.8)))))

(displayln "input:")
(display-dataframe df)
(newline)

(displayln "group-by sum (value, cost):")
(display-dataframe
 (dataframe-group-by-sum df #:by '("group") #:agg '("value" "cost")))
(newline)

(displayln "group-by mean:")
(display-dataframe
 (dataframe-group-by-mean df #:by '("group") #:agg '("value" "cost")))
(newline)

(displayln "group-by min:")
(display-dataframe
 (dataframe-group-by-min df #:by '("group") #:agg '("value")))
(newline)

(displayln "group-by max:")
(display-dataframe
 (dataframe-group-by-max df #:by '("group") #:agg '("value")))
(newline)

(displayln "group-by count:")
(display-dataframe
 (dataframe-group-by-count df #:by '("group") #:agg '("value")))
(newline)

;; Dedup
(define dup-df
  (dataframe-new
   (list (series-new-i32 "x" '(1 2 1 3 2 1))
         (series-new-str "y" '("a" "b" "a" "c" "b" "a")))))

(displayln "duplicates:")
(display-dataframe dup-df)
(newline)

(displayln "unique rows:")
(display-dataframe (dataframe-unique dup-df))
(newline)

;; Null cleanup via CSV
(define csv-path (build-path (find-system-path 'temp-dir)
                             "rkt-polars-dropnulls.csv"))
(with-output-to-file csv-path #:exists 'replace
  (lambda ()
    (displayln "name,score")
    (displayln "alice,10")
    (displayln "bob,")
    (displayln "carol,30")
    (displayln ",40")))
(define np-df (dataframe-read-csv csv-path))

(displayln "with nulls:")
(display-dataframe np-df)
(newline)

(displayln "after drop-nulls:")
(display-dataframe (dataframe-drop-nulls np-df))
(delete-file csv-path)
