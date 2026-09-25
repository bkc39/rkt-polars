#lang racket/base

;; The nycflights ratio table (#86): each operation timed in rkt-polars and, by
;; perf.py, in Python polars on the same file, as the median of 5 runs after a
;; warm-up.
;;
;;   nix run .#bench                  ; fetches the data, then runs blog-test.rkt and this
;;   racket bench/perf.rkt            ; inside `nix develop`, once the data is fetched

(require racket/runtime-path
         (only-in racket/format ~a ~r)
         (only-in racket/future processor-count)
         (only-in racket/match match match-define match-lambda)
         (only-in racket/port port->string with-output-to-string)
         (only-in racket/string string-join string-split)
         (only-in racket/system system*)
         polars
         "harness.rkt")

(define-runtime-path perf.py "perf.py")
(define-runtime-path cargo-lock "../rust/Cargo.lock")

(define numeric-columns
  '("year" "month" "day" "dep_time" "sched_dep_time" "dep_delay" "arr_time"
    "sched_arr_time" "arr_delay" "flight" "air_time" "distance" "hour" "minute"))

(define (timed thunk)
  (lambda () (values thunk #f)))

(define (reader who proc path options [finish values])
  (lambda ()
    (define gap (keyword-gap who proc (map car options)))
    (if gap
        (values #f gap)
        (values (lambda () (finish (keyword-call proc options path))) #f))))

(define (sort-top5 df)
  (lambda ()
    (if (keyword-gap 'sort sort '(#:nulls-last))
        (values (lambda () (~> df (sort "dep_delay" #:descending #t) (head 5)))
                "nulls first: sort has no #:nulls-last")
        (values (lambda () (~> df (sort "dep_delay" #:descending #t #:nulls-last #t) (head 5)))
                #f))))

(define (column->list df)
  (lambda ()
    (define series->list (polars-export 'series->list))
    (if series->list
        (values (lambda () (series->list (ref df #:columns "dep_delay"))) #f)
        (values (lambda ()
                  (define delays (ref df #:columns "dep_delay"))
                  (for/list ([i (in-range (len delays))]) (ref delays i)))
                "ref per element: polars has no series->list"))))

(define (f64-matrix df)
  (lambda ()
    (define dataframe->f64vector (polars-export 'dataframe->f64vector))
    (if dataframe->f64vector
        (values (lambda () (dataframe->f64vector (select df numeric-columns) #:null +nan.0)) #f)
        (values #f "polars has no dataframe->f64vector"))))

(define (operations df source)
  (define tsv (data-file source "tsv"))
  (define csv (data-file source "csv"))
  (define tab (reader-options source #:tab? #t))
  (define comma (reader-options source #:tab? #f))
  (list
   (list "load-tsv" "load TSV" (reader 'read-csv read-csv tsv tab))
   (list "load-csv" "load CSV" (reader 'read-csv read-csv csv comma))
   (list "scan-collect" "lazy scan + collect" (reader 'scan-csv scan-csv tsv tab collect))
   (list "select" "select"
         (timed (lambda () (select df "distance" "dep_delay" "dest"))))
   (list "distinct" "distinct"
         (timed (lambda () (~> df (select "dest") unique))))
   (list "group-by" "group-by count + mean"
         (timed (lambda ()
                  (~> df
                      (group-by "dest")
                      (agg (alias (count "dest") "n") (alias (mean "dep_delay") "mean_delay"))))))
   (list "filter" "filter"
         (timed (lambda () (filter df (> (col "dep_delay") 60)))))
   (list "sort-top5" "sort + top 5" (sort-top5 df))
   (list "describe" "describe" (timed (lambda () (describe df))))
   (list "column-list" "column -> list" (column->list df))
   (list "f64-matrix" "dataframe -> f64 matrix" (f64-matrix df))))

(define (measure make)
  (with-handlers ([exn:fail? (lambda (e) (cons #f (first-line e)))])
    (define-values (thunk note) (make))
    (cons (and thunk (median-ms thunk)) note)))

(define (python-timings source)
  (define python (find-executable-path "python3"))
  (define out
    (if python
        (with-output-to-string (lambda () (system* python perf.py (symbol->string source))))
        ""))
  (for/fold ([timings (hash)]) ([line (in-list (string-split out "\n"))])
    (match (string-split line "\t" #:trim? #f)
      [(list key "n/a" reason) (hash-set timings key (cons #f reason))]
      [(list key value) (hash-set timings key (cons (string->number value) value))]
      [_ timings])))

(define (crate-version)
  (match (regexp-match #px"name = \"polars\"\nversion = \"([^\"]+)\""
                       (call-with-input-file cargo-lock port->string))
    [(list _ v) v]
    [#f "?"]))

(define (load-average)
  (if (file-exists? "/proc/loadavg")
      (match (call-with-input-file "/proc/loadavg" port->string)
        [(pregexp #px"^(\\S+) (\\S+)" (list _ one-minute five-minutes))
         (format ", load average ~a / ~a (1 / 5 min)" one-minute five-minutes)]
        [_ ""])
      ""))

(define (cell v width)
  (~a v #:min-width width #:align 'right))

(define (ms->string ms)
  (if ms (~r ms #:precision '(= 1)) "n/a"))

(define (row label rkt-ms py-ms ratio notes)
  (printf "~a ~a ~a ~a~a\n"
          (~a label #:min-width 24)
          (cell rkt-ms 9)
          (cell py-ms 9)
          (cell ratio 8)
          (if (null? notes) "" (string-append "   " (string-join notes "; ")))))

(module+ main
  (match-define (loaded frame source reason) (load-frame))
  (unless frame
    (error 'perf "no frame loads: ~a" reason))
  (define ops (operations frame source))
  (define rkt (map (match-lambda [(list _ _ make) (measure make)]) ops))
  (define py (python-timings source))
  (printf "nycflights perf in ms, median of 5 runs after a warm-up: rkt-polars (polars crate ~a, Racket ~a) vs Python polars ~a; ~a cpus~a\n"
          (crate-version)
          (version)
          (cdr (hash-ref py "version" (cons #f "?")))
          (processor-count)
          (load-average))
  (printf "inputs: ~a\n"
          (if (eq? source 'original)
              "the original files"
              (format "the NA-stripped copies; the original file does not load: ~a" reason)))
  (row "op" "rkt ms" "py ms" "rkt/py" '())
  (define within
    (for/list ([op (in-list ops)] [measured (in-list rkt)])
      (match-define (list key label _) op)
      (match-define (cons rkt-ms rkt-note) measured)
      (match-define (cons py-ms py-note) (hash-ref py key (cons #f "perf.py printed nothing")))
      (define ratio (and rkt-ms py-ms (/ rkt-ms py-ms)))
      (row label
           (ms->string rkt-ms)
           (ms->string py-ms)
           (if ratio (string-append (~r ratio #:precision '(= 2)) "×") "-")
           (append (if rkt-note (list rkt-note) '())
                   (if py-ms '() (list (string-append "py: " py-note)))))
      (and ratio (<= ratio 1.2))))
  (printf "ratio <= 1.2×: ~a of ~a ops\n"
          (for/sum ([ok? (in-list within)]) (if ok? 1 0))
          (length within)))
