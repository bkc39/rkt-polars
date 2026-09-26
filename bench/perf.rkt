#lang racket/base

;; The nycflights ratio table (#86): each operation timed in rkt-polars and, by
;; perf.py, in Python polars on the same file, as the median of 5 runs after a
;; warm-up.
;;
;;   nix run .#bench                  ; fetches the data, then runs blog-test.rkt and this
;;   racket bench/perf.rkt            ; inside `nix develop`, once the data is fetched

(require racket/runtime-path
         (only-in racket/file file->string)
         (only-in racket/format ~a ~r)
         (only-in racket/future processor-count)
         (only-in racket/match match match-define)
         (only-in racket/port with-output-to-string)
         (only-in racket/string string-join string-split)
         (only-in racket/system system*)
         polars
         "harness.rkt")

(define-runtime-path perf.py "perf.py")
(define-runtime-path cargo-lock "../rust/Cargo.lock")

(define numeric-columns
  '("year" "month" "day" "dep_time" "sched_dep_time" "dep_delay" "arr_time"
    "sched_arr_time" "arr_delay" "flight" "air_time" "distance" "hour" "minute"))

(struct operation (key label run note))

(define (op key label run #:note [note #f])
  (operation key label run note))

(define (operations df source)
  (define series->list (polars-export 'series->list (lambda () #f)))
  (list
   (op "load-tsv" "load TSV" (lambda () (read-frame source "tsv")))
   (op "load-csv" "load CSV" (lambda () (read-frame source "csv")))
   (op "scan-collect" "lazy scan + collect" (lambda () (scan-frame source)))
   (op "select" "select" (lambda () (select df "distance" "dep_delay" "dest")))
   (op "distinct" "distinct" (lambda () (~> df (select "dest") unique)))
   (op "group-by" "group-by count + mean"
       (lambda ()
         (~> df
             (group-by "dest")
             (agg (alias (count "dest") "n") (alias (mean "dep_delay") "mean_delay")))))
   (op "filter" "filter" (lambda () (filter df (> (col "dep_delay") 60))))
   (op "sort-top5" "sort + top 5"
       (lambda ()
         (require-keywords 'sort sort '(#:nulls-last))
         (~> df (sort "dep_delay" #:descending #t #:nulls-last #t) (head 5))))
   (op "describe" "describe" (lambda () (describe df)))
   (if series->list
       (op "column-list" "column -> list"
           (lambda () (series->list (ref df #:columns "dep_delay"))))
       (op "column-list" "column -> list"
           (lambda () (series-values (ref df #:columns "dep_delay")))
           #:note "ref per element: polars has no series->list"))
   (op "f64-matrix" "dataframe -> f64 matrix"
       (lambda ()
         ((polars-export 'dataframe->f64vector) (select df numeric-columns) #:null +nan.0)))))

(struct timing (ms note))

(define (measure o)
  (with-handlers ([exn:fail? (lambda (e) (timing #f (first-line e)))])
    (timing (median-ms (operation-run o)) (operation-note o))))

(define (python-timings source)
  (define python (find-executable-path "python3"))
  (define lines
    (if python
        (~> (with-output-to-string (lambda () (system* python perf.py (symbol->string source))))
            (string-split "\n"))
        '()))
  (for/fold ([version "?"] [timings (hash)]) ([line (in-list lines)])
    (match (string-split line "\t" #:trim? #f)
      [(list "version" v) (values v timings)]
      [(list key "n/a" reason) (values version (hash-set timings key (timing #f reason)))]
      [(list key ms) (values version (hash-set timings key (timing (string->number ms) ms)))]
      [_ (values version timings)])))

(define (crate-version)
  (match (file->string cargo-lock)
    [(pregexp #px"name = \"polars\"\nversion = \"([^\"]+)\"" (list _ v)) v]
    [_ "?"]))

(define (load-average)
  (match (and (file-exists? "/proc/loadavg") (file->string "/proc/loadavg"))
    [(pregexp #px"^(\\S+) (\\S+)" (list _ one-minute five-minutes))
     (format ", load average ~a / ~a (1 / 5 min)" one-minute five-minutes)]
    [_ ""]))

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
  (ensure-data)
  (match-define (loaded frame source reason) (load-frame))
  (unless frame
    (raise-user-error 'perf "no frame loads: ~a" reason))
  (define ops (operations frame source))
  (define rkt (map measure ops))
  (define-values (py-version py) (python-timings source))
  (printf "nycflights perf in ms, median of 5 runs after a warm-up: ~a vs ~a; ~a cpus~a\n"
          (format "rkt-polars (polars crate ~a, Racket ~a)" (crate-version) (version))
          (format "Python polars ~a" py-version)
          (processor-count)
          (load-average))
  (printf "inputs: ~a\n"
          (if (eq? source 'original)
              "the original files"
              (format "the NA-stripped copies; the original file does not load: ~a" reason)))
  (row "op" "rkt ms" "py ms" "rkt/py" '())
  (define within
    (for/list ([o (in-list ops)] [measured (in-list rkt)])
      (match-define (timing rkt-ms rkt-note) measured)
      (match-define (timing py-ms py-note)
        (hash-ref py (operation-key o) (timing #f "perf.py printed nothing")))
      (define ratio (and rkt-ms py-ms (/ rkt-ms py-ms)))
      (row (operation-label o)
           (ms->string rkt-ms)
           (ms->string py-ms)
           (if ratio (string-append (~r ratio #:precision '(= 2)) "×") "-")
           (append (if rkt-note (list rkt-note) '())
                   (if py-ms '() (list (format "py: ~a" py-note)))))
      (and ratio (<= ratio 1.2))))
  (printf "ratio <= 1.2×: ~a of ~a ops\n" (length (filter values within)) (length within)))
