#lang racket/base

;; The nycflights ratio table (#86): each operation timed in rkt-polars and, by
;; perf.py, in Python polars on the same file, as the median of 5 runs after a
;; warm-up.
;;
;;   nix run .#bench                  ; fetches the data, then runs blog-test.rkt and this
;;   racket bench/perf.rkt            ; inside `nix develop`, once the data is fetched
;;   racket bench/perf.rkt --strict   ; exits 1 unless every op is within its allowance

(require racket/runtime-path
         (only-in racket/cmdline command-line)
         (only-in racket/file file->string)
         (only-in racket/format ~a ~r)
         (only-in racket/future processor-count)
         (only-in racket/match match match-define)
         (only-in racket/port with-output-to-string)
         (only-in racket/string string-join string-split)
         (only-in racket/system system*)
         polars
         "harness.rkt"
         "strict.rkt")

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
  (define categorical-frame
    (with-handlers ([exn:fail? values])
      (with-columns df (cast "dest" 'categorical))))
  (define ((on-categorical proc))
    (if (exn? categorical-frame)
        (raise categorical-frame)
        (proc categorical-frame)))
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
         ((polars-export 'dataframe->f64vector) (select df numeric-columns) #:null +nan.0)))
   (op "cast-categorical" "cast 3 to categorical"
       (lambda ()
         (with-columns df (cast "carrier" 'categorical) (cast "dest" 'categorical)
           (cast "origin" 'categorical))))
   (op "group-by-categorical" "group-by on categorical"
       (on-categorical
        (lambda (frame)
          (~> frame
              (group-by "dest")
              (agg (alias (count "dest") "n") (alias (mean "dep_delay") "mean_delay"))))))
   (op "categorical-list" "categorical -> list"
       (on-categorical (lambda (frame) (series->list (ref frame #:columns "dest")))))))

(struct timing (ms note))

(define (measure o)
  (with-handlers ([exn:fail? (lambda (e) (timing #f (first-line e)))])
    (timing (median-ms (operation-run o)) (operation-note o))))

(define (python-timings source [keys '()])
  (define python (find-executable-path "python3"))
  (define lines
    (if python
        (~> (with-output-to-string
              (lambda () (apply system* python perf.py (symbol->string source) keys)))
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
     (format "load average ~a / ~a (1 / 5 min)" one-minute five-minutes)]
    [_ #f]))

(define (cell v width)
  (~a v #:min-width width #:align 'right))

(define (ms->string ms)
  (if ms (~r ms #:precision '(= 1)) "n/a"))

(define missing-python (timing #f "perf.py printed nothing"))

(define (ratio-of rkt py)
  (and (timing-ms rkt) (timing-ms py) (positive? (timing-ms py)) (/ (timing-ms rkt) (timing-ms py))))

(define ((retime ops source) keys)
  (define-values (_version py) (python-timings source keys))
  (for/hash ([key (in-list keys)])
    (define o (findf (lambda (o) (equal? (operation-key o) key)) ops))
    (values key (ratio-of (measure o) (hash-ref py key missing-python)))))

(define (strict-perf ops source reason outcomes load)
  (define (label-of key)
    (define o (findf (lambda (o) (equal? (operation-key o) key)) ops))
    (if o (operation-label o) key))
  (printf "strict: ~a\n" (allowance-line label-of))
  (define settled (retime-over-allowance outcomes (retime ops source)))
  (for ([o (in-list settled)]
        #:when (pair? (cdr (op-outcome-ratios o))))
    (printf "strict: re-timed ~a: ~a\n"
            (op-outcome-label o)
            (string-join (map ratio->string (op-outcome-ratios o)) " then ")))
  (define inputs
    (if (eq? source 'original)
        '()
        (list (format "inputs: the NA-stripped copies; the original file does not load: ~a (#79)"
                      reason))))
  (print-verdict (append inputs (op-violations settled))
                 "every op is within its allowance"
                 (format "~a on ~a cpus" (or load "load average unknown") (processor-count))))

(define (row label rkt-ms py-ms ratio notes)
  (printf "~a ~a ~a ~a~a\n"
          (~a label #:min-width 24)
          (cell rkt-ms 9)
          (cell py-ms 9)
          (cell ratio 8)
          (if (null? notes) "" (string-join notes "; " #:before-first "   "))))

(module+ main
  (define strict? (make-parameter #f))
  (command-line
   #:program "perf.rkt"
   #:once-each
   [("--strict") "Exit 1 unless every op's rkt/py ratio is within its allowance"
                 (strict? #t)])
  (ensure-data)
  (match-define (loaded frame source reason) (load-frame))
  (unless frame
    (raise-user-error 'perf "no frame loads: ~a" reason))
  (define ops (operations frame source))
  (define rkt (map measure ops))
  (define-values (py-version py) (python-timings source))
  (define load (load-average))
  (printf "nycflights perf in ms, median of 5 runs after a warm-up: ~a vs ~a; ~a cpus~a\n"
          (format "rkt-polars (polars crate ~a, Racket ~a)" (crate-version) (version))
          (format "Python polars ~a" py-version)
          (processor-count)
          (if load (string-append ", " load) ""))
  (printf "inputs: ~a\n"
          (if (eq? source 'original)
              "the original files"
              (format "the NA-stripped copies; the original file does not load: ~a" reason)))
  (row "op" "rkt ms" "py ms" "rkt/py" '())
  (define outcomes
    (for/list ([o (in-list ops)] [measured (in-list rkt)])
      (match-define (timing rkt-ms rkt-note) measured)
      (define python (hash-ref py (operation-key o) missing-python))
      (match-define (timing py-ms py-note) python)
      (define ratio (ratio-of measured python))
      (row (operation-label o)
           (ms->string rkt-ms)
           (ms->string py-ms)
           (if ratio (ratio->string ratio) "-")
           (append (if rkt-note (list rkt-note) '())
                   (if py-ms '() (list (format "py: ~a" py-note)))))
      (op-outcome (operation-key o)
                  (operation-label o)
                  (list ratio)
                  (if rkt-ms (format "py: ~a" py-note) rkt-note))))
  (define within
    (for/list ([o (in-list outcomes)])
      (ratio-within? (car (op-outcome-ratios o)) 1.2)))
  (printf "ratio <= 1.2×: ~a of ~a ops\n" (length (filter values within)) (length within))
  (when (and (strict?) (not (strict-perf ops source reason outcomes load)))
    (exit 1)))
