#lang racket/base

(module+ test
  (require rackunit
           racket/runtime-path
           (only-in racket/contract exn:fail:contract:blame?)
           (only-in racket/file delete-directory/files file->bytes-lines make-temporary-directory)
           (only-in racket/list take take-right)
           (only-in racket/match match match-define)
           (only-in racket/string string-join)
           (only-in scribble/core
                    content->string
                    nested-flow-blocks
                    paragraph-content
                    table-blockss)
           (only-in polars/private/test-helpers scratch-file)
           "../utils.rkt")

  (define-runtime-path data-dir "../data")

  (define (rendered block)
    (for/list ([row (table-blockss (car (nested-flow-blocks block)))])
      (content->string (paragraph-content (car row)))))

  (define (disk-lines directory file)
    (for/list ([line (file->bytes-lines (build-path directory file) #:line-mode 'linefeed)])
      (bytes->string/utf-8 line #\uFFFD)))

  (define (expected directory command)
    (match-define (list verb file n) command)
    (define lines (disk-lines directory file))
    (define pick (match verb ['head take] ['tail take-right]))
    (cons (format "$ ~a -n ~a ~a" verb n file)
          (for/list ([line (pick lines (min n (length lines)))])
            (cond
              [(string=? line "") " "]
              [else line]))))

  (define (check-command directory command)
    (check-equal? (rendered ((make-shell #:directory directory) command))
                  (expected directory command)
                  (format "~s" command)))

  (define shell (make-shell #:directory data-dir))

  (for ([command (in-list '((head "flights.tsv" 5)
                            (tail "flights.tsv" 2)
                            (head "parts/part-1.csv" 5)
                            (head "stations.csv" 6)
                            (head "apple_stock.csv" 5)
                            (head "stations.json" 6)
                            (head "stations.ndjson" 6)
                            (head "nycflights-sample.tsv" 3)
                            (tail "nycflights-sample.tsv" 1)
                            (head "nycflights-sample.tsv" 0)))])
    (check-command data-dir command))

  (check-equal? (rendered (shell '(head "nycflights-sample.tsv" 3)
                                 '(tail "nycflights-sample.tsv" 1)))
                (append (expected data-dir '(head "nycflights-sample.tsv" 3))
                        (expected data-dir '(tail "nycflights-sample.tsv" 1))))

  (check-equal? (cadr (rendered (shell '(head "flights.tsv" 1))))
                (string-join '("year" "month" "day" "dep_time" "sched_dep_time" "dep_delay"
                               "arr_time" "sched_arr_time" "arr_delay" "carrier" "flight"
                               "tailnum" "origin" "dest" "air_time" "distance" "hour" "minute"
                               "time_hour")
                             "\t"))
  (check-equal? (cadr (rendered (shell '(tail "flights.tsv" 1))))
                (string-join '("2013" "1" "1" "NA" "1630" "NA" "NA" "1815" "NA" "EV" "4308"
                               "N18120" "EWR" "RDU" "NA" "416" "16" "30" "2013-01-01 16:00:00")
                             "\t"))

  (check-equal? (rendered (shell '(head "notes.csv")))
                '("$ head -n 5 notes.csv"
                  "# carrier notes, typed up by hand"
                  "carrier;note"
                  "UA;'late; weather'"
                  "AA;on time"))

  (check-equal? (rendered (shell '(head "latin1.csv" 5)))
                '("$ head -n 5 latin1.csv" "carrier,name" "B6,JetBlue" "ZZ,Caf\uFFFD Air"))

  (define scratch (make-temporary-directory "rkt-polars-shell-~a"))
  (for ([file (in-list '(("unterminated.txt" "one\ntwo\nthree")
                         ("empty.txt" "")
                         ("blank.txt" "one\n\nthree\n")))])
    (apply scratch-file scratch file))

  (define scratch-shell (make-shell #:directory scratch))
  (for ([case (in-list '(((tail "unterminated.txt" 2)
                          ("$ tail -n 2 unterminated.txt" "two" "three"))
                         ((head "empty.txt" 3)
                          ("$ head -n 3 empty.txt"))
                         ((tail "blank.txt" 2)
                          ("$ tail -n 2 blank.txt" " " "three"))))])
    (match-define (list command lines) case)
    (check-equal? (rendered (scratch-shell command)) lines))
  (for ([command (in-list '((tail "unterminated.txt" 5)
                            (head "empty.txt" 0)
                            (tail "empty.txt" 2)
                            (head "blank.txt" 2)))])
    (check-command scratch command))
  (check-exn exn:fail:contract:blame?
             (lambda () (shell (list 'head (path->string (build-path scratch "blank.txt")) 1))))

  (delete-directory/files scratch))
