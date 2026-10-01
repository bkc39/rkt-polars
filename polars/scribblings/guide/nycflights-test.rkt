#lang racket/base

;; The examples of nycflights.scrbl, on its fixture.  They need `polars`
;; itself, which a generic module's test submodule cannot require (a cycle).

(module+ test
  (require rackunit
           racket/runtime-path
           (only-in racket/string string-contains?)
           (only-in ffi/vector f64vector->list)
           (only-in file/convertible convert)
           (prefix-in pl: polars)
           polars
           plot/pict)

  (define-runtime-path sample-tsv "../data/nycflights-sample.tsv")

  (define (message-of thunk)
    (with-handlers ([exn:fail? exn-message]) (thunk) #f))
  (define (column d name) (series->list (ref d name)))
  (define (renders? p) (bytes? (convert p 'png-bytes)))

  ;; nycflights-require
  (check-equal? (filter even? '(1 2 3 4)) '(2 4))
  (check-equal? (sort '(3 1 2) <) '(1 2 3))
  (check-equal? (max 3 7) 7)
  (check-equal? (pl:~> (pl:series '(3 1 2)) pl:sort pl:series->list) '(1 2 3))

  ;; nycflights-load
  (define flights (read-csv sample-tsv #:separator #\tab #:null-values "NA"))
  (check-equal? (shape flights) '(5434 19))
  (check-equal?
   (for/list ([name (column-names flights)])
     (list name (dtype (ref flights name)) (null-count (ref flights name))))
   '(("year" int64 0) ("month" int64 0) ("day" int64 0) ("dep_time" int64 142)
     ("sched_dep_time" int64 0) ("dep_delay" int64 142) ("arr_time" int64 154)
     ("sched_arr_time" int64 0) ("arr_delay" int64 172) ("carrier" string 0)
     ("flight" int64 0) ("tailnum" string 34) ("origin" string 0) ("dest" string 0)
     ("air_time" int64 172) ("distance" int64 0) ("hour" int64 0) ("minute" int64 0)
     ("time_hour" string 0)))
  (check-equal?
   (for/list ([name (column-names flights)]) (ref (ref flights name) 0))
   '(2013 1 1 517 515 2 830 819 11 "UA" 1545 "N14228" "EWR" "IAH" 227 1400 5 15
     "2013-01-01 05:00:00"))

  (define unparsed (message-of (lambda () (read-csv sample-tsv #:separator #\tab))))
  (check-regexp-match
   #rx"^dataframe-read-csv: failed to read csv from [^:]*nycflights-sample.tsv: could not parse `NA` as dtype `i64` at column 'arr_delay'"
   unparsed)
  (check-true (string-contains? unparsed "`NA` to #:null-values"))

  ;; nycflights-select
  (define subset (select flights "distance" "dep_delay" "dest"))
  (check-equal? (column-names subset) '("distance" "dep_delay" "dest"))
  (check-equal? (shape subset) '(5434 3))
  (check-equal? (for/list ([name (column-names subset)]) (ref (ref subset name) 5433))
                (list 254 polars-null "ROC"))

  ;; nycflights-distinct
  (check-equal? (~> subset (select "dest") unique height) 96)
  (define n-dest (~> subset (select (n-unique "dest"))))
  (check-equal? (shape n-dest) '(1 1))
  (check-equal? (column n-dest "dest") '(96))
  (define firsts (~> subset (group-by "dest") (agg (first "distance") (first "dep_delay"))))
  (check-equal? (shape firsts) '(96 3))
  (check-equal? (column-names firsts) '("dest" "distance" "dep_delay"))

  ;; nycflights-group-by
  (define by-dest
    (~> subset
        (group-by "dest")
        (agg (alias (count "dep_delay") "departed")
             (alias (mean "dep_delay") "mean_delay"))
        (sort "dest")))
  (check-equal? (column-names by-dest) '("dest" "departed" "mean_delay"))
  (check-equal? (height by-dest) 96)
  (define first-five (head by-dest 5))
  (check-equal? (column first-five "dest") '("ABQ" "ACK" "ALB" "ATL" "AUS"))
  (check-equal? (column first-five "departed") '(4 4 8 271 41))
  (for ([got (column first-five "mean_delay")]
        [want '(-3.0 9.25 20.375 15.254612546125461 13.439024390243903)])
    (check-= got want 1e-9))

  ;; nycflights-plot
  (define xs (~> flights (ref "dep_delay") drop-nulls series->list))
  (check-equal? (length xs) 5292)
  (check-equal? (apply max xs) 853)
  (check-true (renders? (plot (density xs) #:x-max 180
                              #:x-label "Departure delay (minutes)" #:y-label "Density")))
  (define delays (~> flights (ref "dep_delay") drop-nulls))
  (check-true (renders? (plot (density (series->vector delays)))))
  (check-false (sequence? (series->f64vector delays)))
  (check-exn exn:fail:contract? (lambda () (density (series->f64vector delays))))
  (check-true (renders? (plot (density (f64vector->list (series->f64vector delays))))))

  ;; nycflights-filter
  (check-equal? (~> flights (filter (> (col "dep_delay") 60)) height) 572)

  ;; nycflights-top-delays
  (define nulls-first
    (~> flights (sort "dep_delay" #:descending #t) (select "dep_delay") (head 3)))
  (check-equal? (column-names nulls-first) '("dep_delay"))
  (check-equal? (column nulls-first "dep_delay") (list polars-null polars-null polars-null))
  (define top-five
    (~> flights
        (sort "dep_delay" #:descending #t #:nulls-last #t)
        (select "dep_delay" "carrier" "dest")
        (head 5)))
  (check-equal? (column top-five "dep_delay") '(853 434 379 368 363))
  (check-equal? (column top-five "carrier") '("MQ" "VX" "EV" "AA" "EV"))
  (check-equal? (column top-five "dest") '("BWI" "LAX" "MCI" "DFW" "IAD"))

  ;; nycflights-separator
  (define guard (message-of (lambda () (read-csv sample-tsv))))
  (check-regexp-match #rx"^dataframe-read-csv: [^:]*nycflights-sample.tsv reads as one column"
                      guard)
  (check-regexp-match #rx"pass #:separator #\\\\tab" guard)

  ;; nycflights-categorical
  (define-enum nyc-airport EWR JFK LGA)
  (define coded
    (with-columns flights
      (cast "carrier" 'categorical)
      (cast "dest" 'categorical)
      (cast "origin" nyc-airport)))
  (check-equal? (for/list ([name '("carrier" "dest" "origin")])
                  (dtype (ref coded name)))
                '(categorical categorical (enum EWR JFK LGA)))
  (check-equal? (~> coded (ref "dest") (head 3) series->list) '(IAH IAH MIA))
  (check-equal? (~> coded (filter (= (col "origin") 'JFK)) height) 1819)
  (define by-origin
    (~> coded
        (group-by "origin")
        (agg (alias (mean "dep_delay") "mean_delay"))
        (sort "origin")))
  (check-equal? (column by-origin "origin") '(EWR JFK LGA))
  (for ([got (column by-origin "mean_delay")]
        [want '(18.297525013164822 16.61114237478897 14.715965346534654)])
    (check-= got want 1e-9))
  (check-exn #rx"^series-cast: cannot convert to '\\(enum EWR JFK LGA\\): .*\"TEB\""
             (lambda () (cast (series '(EWR TEB)) nyc-airport)))

  ;; nycflights-describe
  (define described
    (~> flights
        (with-columns (str->datetime "time_hour"))
        (select "carrier" "dest" "time_hour")
        describe))
  (check-equal? (column-names described) '("statistic" "carrier" "dest" "time_hour"))
  (check-equal? (column described "statistic")
                '("count" "null_count" "mean" "std" "min" "25%" "50%" "75%" "max"))
  (define (string-summary low high)
    (list "5434" "0" polars-null polars-null low polars-null polars-null polars-null high))
  (check-equal? (column described "carrier") (string-summary "9E" "YV"))
  (check-equal? (column described "dest") (string-summary "ABQ" "XNA"))
  (check-equal? (column described "time_hour")
                (list "5434" "0" "2013-06-01 16:28:23.938167" polars-null "2013-01-01 05:00:00"
                      "2013-03-01 14:00:00" "2013-05-01 20:00:00" "2013-09-01 13:00:00"
                      "2013-11-01 23:00:00"))
  (define carriers
    (~> coded
        (group-by "carrier")
        (agg (alias (count "carrier") "flights"))
        (sort "flights" #:descending #t)
        (head 5)))
  (check-equal? (column carriers "carrier") '(UA B6 EV DL AA))
  (check-equal? (column carriers "flights") '(960 920 838 754 547)))
