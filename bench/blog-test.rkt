#lang racket/base

;; The nycflights scoreboard (#86): the steps and complaints of
;; https://aliquote.org/post/racket-data-frames/ as PASS/FAIL checks on its own
;; file, with no preprocessing.
;;
;;   nix run .#bench                  ; fetches the data, then runs this and perf.rkt
;;   racket bench/blog-test.rkt       ; inside `nix develop`, once the data is fetched

(require (only-in gregor [date gregor-date])
         (only-in racket/format ~a ~r)
         (only-in racket/match match match-define match-lambda)
         polars
         "harness.rkt")

(define (fail! fmt . args)
  (error (apply format fmt args)))

(define (expect what got want [same? equal?])
  (unless (same? got want)
    (fail! "~a: got ~a, expected ~a" what got want)))

(define (column-values frame name)
  (series-values (ref frame #:columns name)))

(define (cell frame name)
  (~> frame (ref #:columns name) (ref 0)))

(define (same-number? got want)
  (and (real? got) (= got want)))

(define (close? got want)
  (and (real? got) (<= (abs (- got want)) (* 1e-12 (abs want)))))

(define (dtype-kind? kind dt)
  (match dt
    [(cons head _) (eq? head kind)]
    [_ (eq? dt kind)]))

(define integer-dtypes '(int8 int16 int32 int64 uint8 uint16 uint32 uint64))

(define (t1-load df)
  (expect "shape" (shape df) '(336776 19))
  (define delays (ref df #:columns "dep_delay"))
  (unless (memq (dtype delays) integer-dtypes)
    (fail! "dep_delay is ~a, not an integer column" (dtype delays)))
  (expect "dep_delay nulls" (null-count delays) 8255)
  (format "336776 × 19; dep_delay ~a with 8255 nulls" (dtype delays)))

(define (t2-select df)
  (define subset (select df "distance" "dep_delay" "dest"))
  (expect "columns" (column-names subset) '("distance" "dep_delay" "dest"))
  (expect "rows" (height subset) 336776)
  "distance, dep_delay, dest")

(define (t3-distinct df)
  (expect "distinct dest" (~> df (select "dest") unique height) 105)
  "105 destinations")

(define t4-expected
  '(("IAH" 7198 7103 10.84217936083345)
    ("ATL" 17215 16898 12.509823647768966)
    ("LAX" 16174 16076 9.401343617815376)))

(define (t4-group-by df)
  (define groups
    (~> df
        (group-by "dest")
        (agg (alias (count "dest") "rows")
             (alias (count "dep_delay") "non_null")
             (alias (mean "dep_delay") "mean_delay"))))
  (expect "groups" (height groups) 105)
  (for ([row (in-list t4-expected)])
    (match-define (list dest rows non-null mean-delay) row)
    (define group (filter groups (= (col "dest") dest)))
    (expect (format "~a rows" dest) (cell group "rows") rows)
    (expect (format "~a non-null dep_delay" dest) (cell group "non_null") non-null)
    (expect (format "~a mean dep_delay" dest) (cell group "mean_delay") mean-delay close?))
  "IAH, ATL, LAX rows, non-null count and mean")

(define (t5-to-racket df)
  (define series->list (polars-export 'series->list))
  (define (delays)
    (~> df (ref #:columns "dep_delay") drop-nulls series->list))
  (define xs (delays))
  (expect "values" (length xs) 328521)
  (expect "largest" (apply max xs) 1301 same-number?)
  (define ms (median-ms delays #:runs 3))
  (unless (< ms 100)
    (fail! "~a ms; the target is tens of milliseconds" (~r ms #:precision 0)))
  (format "328521 values in ~a ms" (~r ms #:precision '(= 1))))

(define (t6-filter df)
  (expect "rows" (~> df (filter (> (col "dep_delay") 60)) height) 26581)
  "26581 rows")

(define (t7-top-delays df)
  (require-keywords 'sort sort '(#:nulls-last))
  (expect "top 5"
          (~> df
              (sort "dep_delay" #:descending #t #:nulls-last #t)
              (head 5)
              (column-values "dep_delay"))
          '(1301 1137 1126 1014 1005))
  "1301 1137 1126 1014 1005")

(define (c1-separator)
  (define attempt
    (with-handlers ([exn:fail? values])
      (read-csv (data-file 'original "tsv"))))
  (when (dataframe? attempt)
    (fail! "read-csv returned a ~a × ~a frame" (height attempt) (width attempt)))
  (unless (regexp-match? #rx"(?i:separator)" (exn-message attempt))
    (fail! "read-csv raises without naming the separator: ~a" (first-line attempt)))
  (format "raises: ~a" (first-line attempt)))

(define categorical-columns '(("carrier" UA) ("dest" IAH) ("origin" EWR)))

(define (c2-categorical df)
  (define cast-frame
    (with-columns df (map (match-lambda [(list name _) (cast name 'categorical)])
                          categorical-columns)))
  (for ([entry (in-list categorical-columns)])
    (match-define (list name first-value) entry)
    (define s (ref cast-frame #:columns name))
    (unless (dtype-kind? 'categorical (dtype s))
      (fail! "~a is ~a after the cast" name (dtype s)))
    (expect (format "~a row 0" name) (ref s 0) first-value))
  "carrier, dest, origin categorical; row 0 reads back as 'UA, 'IAH, 'EWR")

(define (c3-dates)
  (require-keywords 'read-csv read-csv '(#:separator #:null-values #:try-parse-dates))
  (define df
    (read-csv (data-file 'original "tsv")
              #:separator #\tab #:null-values "NA" #:try-parse-dates #t))
  (define time-hour (dtype (ref df #:columns "time_hour")))
  (unless (dtype-kind? 'datetime time-hour)
    (fail! "time_hour loads as ~a, not a datetime" time-hour))
  (define days
    (~> df (group-by "year" "month" "day") (agg (alias (min "time_hour") "time_hour"))))
  (define dates
    (map gregor-date
         (column-values days "year")
         (column-values days "month")
         (column-values days "day")))
  (expect "calendar days" (length dates) 365)
  (define ymd (series dates #:name "ymd"))
  (expect "dtype of a series of gregor dates" (dtype ymd) 'date)
  (expect "gregor dates read back" (series-values ymd) dates)
  (expect "days whose time_hour date is not year/month/day"
          (~> days (with-column ymd) (filter (!= (dt-date "time_hour") (col "ymd"))) height)
          0)
  "time_hour loads as a datetime; 365 year/month/day dates round-trip through gregor")

(define c4-expected
  '(("carrier" "9E" "YV")
    ("dest" "ABQ" "XNA")
    ("time_hour" "2013-01-01 05:00:00" "2013-12-31 23:00:00")))

(define (c4-describe df)
  (define summary (describe df))
  (define (stat column name)
    (~> summary (filter (= (col "statistic") name)) (cell column)))
  (define (as-number v)
    (if (string? v) (string->number v) v))
  (for ([row (in-list c4-expected)])
    (match-define (list column lowest highest) row)
    (expect (format "~a count" column) (as-number (stat column "count")) 336776 same-number?)
    (expect (format "~a null_count" column) (as-number (stat column "null_count")) 0 same-number?)
    (expect (format "~a min" column) (~a (stat column "min")) lowest)
    (expect (format "~a max" column) (~a (stat column "max")) highest))
  "count, null_count, min, max for carrier, dest, time_hour as Python's")

(struct check (id label issue on-frame? body))

(define checks
  (list (check 'T1 "load" 79 #t t1-load)
        (check 'T2 "select" 79 #t t2-select)
        (check 'T3 "distinct" 79 #t t3-distinct)
        (check 'T4 "group-by" 79 #t t4-group-by)
        (check 'T5 "to Racket" 78 #t t5-to-racket)
        (check 'T6 "filter" 79 #t t6-filter)
        (check 'T7 "top delays" 82 #t t7-top-delays)
        (check 'C1 "separator" 79 #f c1-separator)
        (check 'C2 "categorical" 43 #t c2-categorical)
        (check 'C3 "dates" 63 #f c3-dates)
        (check 'C4 "describe" 79 #t c4-describe)))

(struct result (pass? text))

(define (outcome thunk)
  (with-handlers ([exn:fail? (lambda (e) (result #f (first-line e)))])
    (result #t (thunk))))

(define (run-check c data)
  (match-define (loaded frame source reason) data)
  (define body (check-body c))
  (cond
    [(not (check-on-frame? c)) (outcome body)]
    [(not frame) (result #f (format "no frame loads: ~a" reason))]
    [(eq? source 'original) (outcome (lambda () (body frame)))]
    [else
     (match-define (result pass? text) (outcome (lambda () (body frame))))
     (result #f (format "~a; on the NA-stripped copy: ~a"
                        (if (eq? (check-id c) 'T1) reason "the original file does not load (T1)")
                        (if pass? (format "PASS (~a)" text) text)))]))

(define (report c r)
  (match-define (result pass? text) r)
  (printf "~a  ~a  ~a  ~a~a\n"
          (if pass? "PASS" "FAIL")
          (check-id c)
          (~a (check-label c) #:min-width 11)
          text
          (if pass? "" (format "  (#~a)" (check-issue c))))
  pass?)

(module+ main
  (ensure-data)
  (define data (load-frame))
  (printf "nycflights scoreboard: https://aliquote.org/post/racket-data-frames/ on ~a\n"
          (data-file 'original "tsv"))
  (define passes
    (for/list ([c (in-list checks)])
      (report c (run-check c data))))
  (printf "~a of ~a PASS\n" (length (filter values passes)) (length checks)))
