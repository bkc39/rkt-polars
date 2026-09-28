#lang racket/base

;; Iterating over a series: a series is a Racket sequence, and in-series takes
;; #:null.
;;
;; Rows are converted 4096 at a time, so the loop streams and one that stops
;; early converts little more than it reads. in-dataframe-columns walks a
;; frame's columns as series.
;;
;; Inside `nix develop`:
;;   racket examples/49-series-iteration.rkt

(require racket/sequence
         polars)

(define temps (series (list 21.5 polars-null 19.0 23.5) #:name "temp"))

;; a series in a for clause
(for ([t temps] [i (in-naturals)])
  (printf "row ~a: ~a\n" i t))

;; in-series with a null replacement
(writeln (for/sum ([t (in-series temps #:null 0.0)]) t))
(writeln (for/list ([t (in-series temps #:null 'skip)] #:unless (eq? t 'skip)) t))

;; the sequence operations see it too
(writeln (sequence? temps))
(writeln (sequence->list temps))
(writeln (sequence-length temps))

;; an early exit over a million rows touches only the first block
(define big (series (build-list 1000000 values) #:name "n"))
(writeln (for/first ([n (in-series big)] #:when (> (* n n) 1000)) n))

;; a dataframe is not a sequence: iterate over its columns, or one of them
(define df (dataframe (list temps (series '("mon" "tue" "wed" "thu") #:name "day"))))
(for ([column (in-dataframe-columns df)])
  (printf "~a: ~a\n" (series-name column) (dtype column)))
(for ([day (ref df "day")] [t (ref df "temp")])
  (printf "~a ~a\n" day t))
