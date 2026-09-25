#lang racket/base

;; The nycflights scoreboard (#86): the steps and complaints of
;; https://aliquote.org/post/racket-data-frames/ as PASS/FAIL checks on its own
;; file, with no preprocessing.
;;
;;   nix run .#bench                  ; fetches the data, then runs this and perf.rkt
;;   racket bench/blog-test.rkt       ; inside `nix develop`, once the data is fetched

(require (only-in gregor date)
         (only-in racket/format ~a ~r)
         (only-in racket/list index-of)
         (only-in racket/match match match-define)
         polars
         "harness.rkt")

(struct failure (reason))

(define (fail! fmt . args)
  (raise (failure (apply format fmt args))))

(define (expect what got want [same? equal?])
  (unless (same? got want)
    (fail! "~a: got ~a, expected ~a" what got want)))

(define (need-keywords who proc keywords)
  (define gap (keyword-gap who proc keywords))
  (when gap (fail! "~a" gap)))

(define (need-export name)
  (or (polars-export name) (fail! "polars has no ~a" name)))

(define (series-values s)
  (for/list ([i (in-range (len s))]) (ref s i)))

(define (column-values frame name)
  (series-values (ref frame #:columns name)))

(define (cell frame name)
  (~> frame (ref #:columns name) (ref 0)))

(define (same-number? got want)
  (and (real? got) (= got want)))

(define (close? got want)
  (and (real? got) (<= (abs (- got want)) (* 1e-12 (abs want)))))

(define (datetime-dtype? dt)
  (match dt [(or 'datetime (cons 'datetime _)) #t] [_ #f]))

(define (categorical-dtype? dt)
  (match dt [(or 'categorical (cons 'categorical _)) #t] [_ #f]))

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
  (define series->list (need-export 'series->list))
  (define (delays)
    (~> df (ref #:columns "dep_delay") drop-nulls series->list))
  (define xs (delays))
  (expect "values" (length xs) 328521)
  (expect "largest" (apply max xs) 1301 same-number?)
  (define ms (median-ms delays #:runs 3))
  (unless (< ms 100)
    (fail! "~a ms; the target is tens of milliseconds" (~r ms #:precision 0)))
  (format "328521 values in ~a ms" (~r ms #:precision 1)))

(define (t6-filter df)
  (expect "rows" (~> df (filter (> (col "dep_delay") 60)) height) 26581)
  "26581 rows")

(define (t7-top-delays df)
  (need-keywords 'sort sort '(#:nulls-last))
  (expect "top 5"
          (~> df
              (sort "dep_delay" #:descending #t #:nulls-last #t)
              (head 5)
              (column-values "dep_delay"))
          '(1301 1137 1126 1014 1005))
  "1301 1137 1126 1014 1005")

(define (c1-separator)
  (define result
    (with-handlers ([exn:fail? values])
      (read-csv (data-file 'original "tsv"))))
  (when (dataframe? result)
    (fail! "read-csv returned a ~a × ~a frame" (height result) (width result)))
  (format "raises: ~a" (first-line result)))

(define categorical-columns '(("carrier" . UA) ("dest" . IAH) ("origin" . EWR)))

(define (c2-categorical df)
  (define cast-frame
    (with-columns df (map (lambda (entry) (cast (car entry) 'categorical)) categorical-columns)))
  (for ([entry (in-list categorical-columns)])
    (match-define (cons name first-value) entry)
    (define s (ref cast-frame #:columns name))
    (unless (categorical-dtype? (dtype s))
      (fail! "~a is ~a after the cast" name (dtype s)))
    (expect (format "~a row 0" name) (ref s 0) first-value))
  "carrier, dest, origin categorical; row 0 reads back as 'UA, 'IAH, 'EWR")

(define (c3-dates)
  (define parse-dates
    (or (findf (lambda (k) (not (keyword-gap 'read-csv read-csv (list k))))
               '(#:try-parse-dates #:try-parse-dates?))
        (fail! "read-csv has no #:try-parse-dates")))
  (define options (cons (cons parse-dates #t) (reader-options 'original #:tab? #t)))
  (need-keywords 'read-csv read-csv (map car options))
  (define df (keyword-call read-csv options (data-file 'original "tsv")))
  (define time-hour (dtype (ref df #:columns "time_hour")))
  (unless (datetime-dtype? time-hour)
    (fail! "time_hour loads as ~a, not a datetime" time-hour))
  (define days
    (~> df (group-by "year" "month" "day") (agg (alias (min "time_hour") "time_hour"))))
  (define dates
    (for/list ([y (in-list (column-values days "year"))]
               [m (in-list (column-values days "month"))]
               [d (in-list (column-values days "day"))])
      (date y m d)))
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
  (define statistics (column-values summary "statistic"))
  (define (stat column name)
    (~> summary (ref #:columns column) (ref (index-of statistics name))))
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

(define (outcome thunk)
  (with-handlers ([failure? (lambda (f) (list #f (failure-reason f)))]
                  [exn:fail? (lambda (e) (list #f (first-line e)))])
    (list #t (thunk))))

(define (run-check c data)
  (match-define (loaded frame source reason) data)
  (define body (check-body c))
  (cond
    [(not (check-on-frame? c)) (outcome body)]
    [(not frame) (list #f (format "the file does not load: ~a" reason))]
    [(eq? source 'original) (outcome (lambda () (body frame)))]
    [else
     (match-define (list pass? text) (outcome (lambda () (body frame))))
     (list #f (format "~a; on the NA-stripped copy: ~a"
                      (if (eq? (check-id c) 'T1) reason "the original file does not load (T1)")
                      (if pass? (format "PASS (~a)" text) text)))]))

(define (report c result)
  (match-define (list pass? text) result)
  (printf "~a  ~a  ~a  ~a~a\n"
          (if pass? "PASS" "FAIL")
          (check-id c)
          (~a (check-label c) #:min-width 11)
          text
          (if pass? "" (format "  (#~a)" (check-issue c))))
  pass?)

(module+ main
  (define data (load-frame))
  (printf "nycflights scoreboard: https://aliquote.org/post/racket-data-frames/ on ~a\n"
          (data-file 'original "tsv"))
  (define passed
    (for/sum ([c (in-list checks)])
      (if (report c (run-check c data)) 1 0)))
  (printf "~a of ~a PASS\n" passed (length checks)))
