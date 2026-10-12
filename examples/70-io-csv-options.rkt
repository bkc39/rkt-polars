#lang racket/base

;; CSV options: the rest of read_csv's keywords, and write_csv's.
;;
;; Reading: #:columns picks columns by name or position, in the file's order;
;; #:new-columns renames the first ones, and the keywords that name a column
;; then use the new name; #:row-index-name / #:row-index-offset add a row
;; number. #:null-values takes an association list for markers that apply to
;; one column only. #:skip-lines skips lines without parsing them,
;; #:decimal-comma reads 1,5 as 1.5, #:truncate-ragged-lines drops a line's
;; extra fields, #:eol-char ends lines with another character, and
;; #:raise-if-empty #f reads an empty file as an empty frame.
;;
;; Writing: write-csv takes the separator, quoting, line ends and the way
;; nulls, floats and temporal values are written.
;;
;; Inside `nix develop`:
;;   racket examples/70-io-csv-options.rkt

(require racket/file
         racket/runtime-path
         polars)

(define-runtime-path data-dir "../polars/scribblings/data")
(define (data name) (build-path data-dir name))

(define (report thunk)
  (with-handlers ([exn:fail? (lambda (e) (displayln (exn-message e)))])
    (thunk)))

(displayln "#:columns, #:row-index-name and #:row-index-offset:")
(displayln (read-csv (data "flights.tsv") #:separator #\tab #:null-values "NA"
                     #:columns '("carrier" "flight" "dep_delay")
                     #:row-index-name "row" #:row-index-offset 1 #:n-rows 3))
(displayln "#:new-columns on a file read without its header:")
(displayln (read-csv (data "parts/part-1.csv") #:has-header #f #:skip-rows 1
                     #:new-columns '("from" "to" "delay")))
(displayln "a row index named like a column is refused:")
(report (lambda () (read-csv (data "parts/part-1.csv") #:row-index-name "origin")))
(newline)

(displayln "stations.csv, with a stray first line and a ragged last one:")
(display (file->string (data "stations.csv")))
(define stations
  (read-csv (data "stations.csv") #:skip-lines 1 #:separator #\; #:decimal-comma #t
            #:null-values '(("temp" . "-") ("rain" . "n/a"))
            #:truncate-ragged-lines #t #:try-parse-dates #t))
(displayln stations)
(displayln "the same markers for every column also null the note \"-\":")
(displayln (~> (read-csv (data "stations.csv") #:skip-lines 1 #:separator #\;
                         #:null-values '("-" "n/a") #:truncate-ragged-lines #t)
               (select "station" "note")))
(newline)

(define scratch (make-temporary-directory "rkt-polars-csv-options-~a"))
(define lines (build-path scratch "lines.csv"))
(call-with-output-file lines (lambda (out) (void (write-string "a,b;1,x;2,y;" out))))
(displayln "#:eol-char #\\; on a;b-terminated lines:")
(displayln (read-csv lines #:eol-char #\;))
(define nothing (build-path scratch "nothing.csv"))
(call-with-output-file nothing void)
(displayln "an empty file:")
(report (lambda () (read-csv nothing)))
(displayln (shape (read-csv nothing #:raise-if-empty #f)))
(newline)

(define out (build-path scratch "out.csv"))
(define (show-written frame . options)
  (keyword-apply write-csv (map car options) (map cdr options) (list frame out))
  (display (file->string out)))
(displayln "write-csv, European style:")
(show-written stations '(#:date-format . "%d.%m.%Y") '(#:decimal-comma . #t)
              '(#:null-value . "-") '(#:separator . #\;) '(#:time-format . "%H:%M"))
(displayln "#:quote-style 'non-numeric #:float-precision 2:")
(show-written (select stations "station" "temp")
              '(#:float-precision . 2) '(#:quote-style . non-numeric))
(displayln "#:float-scientific #t #:include-header #f #:line-terminator \" |\\n\":")
(show-written (select stations "station" "temp")
              '(#:float-scientific . #t) '(#:include-header . #f)
              '(#:line-terminator . " |\n"))
(displayln "a format the column cannot take:")
(report (lambda () (write-csv stations out #:date-format "%H")))
(delete-directory/files scratch)
