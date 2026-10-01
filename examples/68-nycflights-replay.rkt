#lang racket/base

;; The nycflights case study: https://aliquote.org/post/racket-data-frames/
;; replayed step by step, as the guide's "Case study: nycflights" chapter does.
;;
;; It reads the manual's fixture, nycflights-sample.tsv: every flight on the
;; first day of each odd month of the post's nycflights.tsv (nycflights13,
;; CC0), 5,434 rows. `nix run .#bench` runs the same steps on the full file.
;;
;; Inside `nix develop`:
;;   racket examples/68-nycflights-replay.rkt

(require racket/runtime-path
         polars)

(define-runtime-path sample-tsv "../polars/scribblings/data/nycflights-sample.tsv")

(define (report thunk)
  (with-handlers ([exn:fail? (lambda (e) (printf "raises: ~a\n" (exn-message e)))])
    (thunk)))

(displayln "load, with the tab and the NA marker named:")
(define flights (read-csv sample-tsv #:separator #\tab #:null-values "NA"))
(displayln (shape flights))

(displayln "select:")
(define subset (select flights "distance" "dep_delay" "dest"))
(displayln (head subset 3))

(printf "distinct destinations: ~a\n" (~> subset (select "dest") unique height))

(displayln "non-null count and mean delay by destination:")
(displayln (~> subset
               (group-by "dest")
               (agg (alias (count "dep_delay") "departed")
                    (alias (mean "dep_delay") "mean_delay"))
               (filter (is-in "dest" '("ATL" "IAH" "LAX")))
               (sort "dest")))

(define xs (~> flights (ref "dep_delay") drop-nulls series->list))
(printf "delays in Racket: ~a values, the largest ~a, the mean ~a\n"
        (length xs)
        (apply max xs)
        (/ (round (* 100 (/ (apply + xs) (length xs)))) 100.0))

(printf "more than an hour late: ~a\n"
        (~> flights (filter (> (col "dep_delay") 60)) height))

(printf "largest delays, nulls last: ~a\n"
        (~> flights
            (sort "dep_delay" #:descending #t #:nulls-last #t)
            (head 5)
            (ref "dep_delay")
            series->list))

(displayln "the TSV with the default separator:")
(report (lambda () (read-csv sample-tsv)))

(define-enum nyc-airport EWR JFK LGA)
(define coded
  (with-columns flights
    (cast "carrier" 'categorical)
    (cast "dest" 'categorical)
    (cast "origin" nyc-airport)))
(printf "dtypes: ~s\n" (for/list ([name '("carrier" "dest" "origin")])
                         (dtype (ref coded name))))
(printf "first destinations: ~s\n" (~> coded (ref "dest") (head 3) series->list))
(displayln (~> coded
               (group-by "origin")
               (agg (alias (mean "dep_delay") "mean_delay"))
               (sort "origin")))
(displayln "a value outside the Enum:")
(report (lambda () (cast (series '(EWR TEB)) nyc-airport)))

(displayln (~> flights
               (with-columns (str->datetime "time_hour"))
               (select "carrier" "dest" "time_hour")
               describe))
