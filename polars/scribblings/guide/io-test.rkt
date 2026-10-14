#lang racket/base

;; The raw-file blocks of io.scrbl, io-json.scrbl and nycflights.scrbl: what
;; `shell-head` and `shell-tail` render against the bytes on disk.

(module+ test
  (require rackunit
           racket/runtime-path
           (only-in racket/match match-define)
           (only-in racket/file file->bytes)
           (only-in racket/list drop-right last take take-right)
           (only-in scribble/core
                    content->string
                    nested-flow-blocks
                    paragraph-content
                    table-blockss)
           "../utils.rkt")

  (define-runtime-path data-dir "../data")

  (define (rendered block)
    (for/list ([row (table-blockss (car (nested-flow-blocks block)))])
      (content->string (paragraph-content (car row)))))

  (define (disk-lines file)
    (define lines
      (for/list ([line (regexp-split #rx#"\n" (file->bytes (build-path data-dir file)))])
        (bytes->string/utf-8 line #\uFFFD)))
    (cond
      [(equal? (last lines) "") (drop-right lines 1)]
      [else lines]))

  (define (check-head file n)
    (define lines (disk-lines file))
    (check-equal? (rendered (shell-head file n #:directory data-dir))
                  (cons (format "$ head -n ~a ~a" n file)
                        (take lines (min n (length lines))))))

  (define (check-tail file n)
    (check-equal? (rendered (shell-tail file n #:directory data-dir))
                  (cons (format "$ tail -n ~a ~a" n file)
                        (take-right (disk-lines file) n))))

  (check-head "flights.tsv" 5)
  (check-tail "flights.tsv" 2)
  (match-define (list _ header) (rendered (shell-head "flights.tsv" 1 #:directory data-dir)))
  (check-equal? header
                (string-append "year\tmonth\tday\tdep_time\tsched_dep_time\tdep_delay\t"
                               "arr_time\tsched_arr_time\tarr_delay\tcarrier\tflight\t"
                               "tailnum\torigin\tdest\tair_time\tdistance\thour\tminute\t"
                               "time_hour"))
  (match-define (list _ last-line) (rendered (shell-tail "flights.tsv" 1 #:directory data-dir)))
  (check-equal? last-line
                (string-append "2013\t1\t1\tNA\t1630\tNA\tNA\t1815\tNA\tEV\t4308\tN18120\t"
                               "EWR\tRDU\tNA\t416\t16\t30\t2013-01-01 16:00:00"))

  (check-head "notes.csv" 5)
  (check-equal? (rendered (shell-head "notes.csv" #:directory data-dir))
                '("$ head -n 5 notes.csv"
                  "# carrier notes, typed up by hand"
                  "carrier;note"
                  "UA;'late; weather'"
                  "AA;on time"))

  (check-head "latin1.csv" 5)
  (check-equal? (rendered (shell-head "latin1.csv" #:directory data-dir))
                '("$ head -n 5 latin1.csv" "carrier,name" "B6,JetBlue" "ZZ,Caf\uFFFD Air"))

  (check-head "parts/part-1.csv" 5)
  (check-head "stations.csv" 6)
  (check-head "apple_stock.csv" 5)
  (check-head "stations.json" 6)
  (check-head "stations.ndjson" 5)
  (check-equal? (length (rendered (shell-head "stations.ndjson" #:directory data-dir))) 5)
  (check-tail "stations.ndjson" 1)

  (check-head "nycflights-sample.tsv" 3)
  (check-tail "nycflights-sample.tsv" 1)
  (check-equal? (rendered (shell-head "nycflights-sample.tsv" 0 #:directory data-dir))
                '("$ head -n 0 nycflights-sample.tsv")))
