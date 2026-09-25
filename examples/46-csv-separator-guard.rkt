#lang racket/base

;; The separator guard: a TSV read with the default comma.
;;
;; Read with the default comma, a tab- or semicolon-separated file comes back
;; as one column named after the whole header line; Python's read_csv returns
;; exactly that. read-csv is stricter: when #:separator is not given and the
;; one column's header and first row both split on a tab, ; or |, it raises
;; and names the separator to pass. Passing any #:separator, even #\, for a
;; file that really is one column, turns the check off; a genuine one-column
;; file never trips it; and scan-csv does not check.
;;
;; Inside `nix develop`:
;;   racket examples/46-csv-separator-guard.rkt

(require racket/file
         racket/runtime-path
         polars)

(define-runtime-path flights-tsv "../polars/scribblings/data/flights.tsv")

(define (report thunk)
  (with-handlers ([exn:fail? (lambda (e) (displayln (exn-message e)))])
    (thunk)))

(displayln "the TSV with the default separator:")
(report (lambda () (read-csv flights-tsv)))
(displayln "the fix, #:separator #\\tab:")
(displayln (shape (read-csv flights-tsv #:separator #\tab #:null-values "NA")))
(newline)

(define (scratch name . lines)
  (define path (make-temporary-file (string-append "rkt-polars-guard-~a-" name)))
  (display-lines-to-file lines path #:exists 'replace)
  path)

(define semicolons (scratch "semi.csv" "carrier;flight" "UA;1545" "AA;1141"))
(report (lambda () (read-csv semicolons)))
(displayln (read-csv semicolons #:separator #\;))

(define names (scratch "names.csv" "name" "alice" "bob"))
(displayln "a genuine one-column file reads as usual:")
(displayln (read-csv names))

(define key-value (scratch "key-value.csv" "entry" "k;v" "x;y"))
(displayln "a one-column file whose values hold ; but whose header does not:")
(displayln (read-csv key-value))

(displayln "#:separator #\\, keeps one column on purpose:")
(displayln (shape (read-csv flights-tsv #:separator #\,)))
(displayln "scan-csv does not check:")
(displayln (shape (collect (scan-csv flights-tsv))))

(for-each delete-file (list semicolons names key-value))
