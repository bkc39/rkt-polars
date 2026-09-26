#lang racket/base

;; CSV null values: #:null-values, one marker or a list of them.
;;
;; The nycflights file marks a missing value with NA. Types are inferred from
;; the first 100 rows and the first NA comes later, so the default read fails
;; with Polars' own advice, spelled with the Racket keywords. #:null-values
;; takes one marker (a string) or several (a list); every listed marker, in
;; any column, reads as null. It works the same on read-csv and scan-csv.
;;
;; Inside `nix develop`:
;;   racket examples/40-csv-null-values.rkt

(require racket/file
         racket/runtime-path
         polars)

(define-runtime-path flights-tsv "../polars/scribblings/data/flights.tsv")

(define (report thunk)
  (with-handlers ([exn:fail? (lambda (e) (displayln (exn-message e)))])
    (thunk)))

(displayln "default read, NA in an integer column:")
(report (lambda () (read-csv flights-tsv #:separator #\tab)))
(newline)

(define flights (read-csv flights-tsv #:separator #\tab #:null-values "NA"))
(displayln "#:null-values \"NA\", null count per column:")
(for ([name (column-names flights)])
  (define nulls (null-count (ref flights #:columns name)))
  (when (positive? nulls)
    (printf "  ~a: ~a nulls (~a)\n" name nulls (dtype (ref flights #:columns name)))))
(displayln (~> flights (select "carrier" "dep_delay" "arr_delay") (tail 3)))
(newline)

(define readings (make-temporary-file "rkt-polars-null-values-~a.csv"))
(display-lines-to-file '("station,reading" "A,1" "B,NA" "C,-" "D,4") readings
                       #:exists 'replace)

(displayln "#:null-values '(\"NA\" \"-\"), several markers:")
(displayln (read-csv readings #:null-values '("NA" "-")))

(displayln "the same markers on a lazy scan:")
(displayln (~> (scan-csv readings #:null-values '("NA" "-"))
               (filter (is-not-null (col "reading")))
               collect))
(delete-file readings)
