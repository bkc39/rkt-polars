#lang racket/base

;; CSV parse errors: #:ignore-errors.
;;
;; A field that does not parse as its column's type stops the read. With
;; #:ignore-errors #t it reads as null instead, whatever the text is; when the
;; markers are known, #:null-values names them and keeps every other parse
;; error an error.
;;
;; Inside `nix develop`:
;;   racket examples/42-csv-ignore-errors.rkt

(require racket/file
         polars)

(define (report thunk)
  (with-handlers ([exn:fail? (lambda (e) (displayln (exn-message e)))])
    (thunk)))

(define sensor (make-temporary-file "rkt-polars-ignore-errors-~a.csv"))
(display-lines-to-file (append '("sensor,reading")
                               (for/list ([i (in-range 120)]) (format "s~a,~a" i i))
                               '("s120,n/a" "s121,??" "s122,122"))
                       sensor #:exists 'replace)

(displayln "default read:")
(report (lambda () (read-csv sensor)))
(newline)

(define ignored (read-csv sensor #:ignore-errors #t))
(printf "#:ignore-errors #t: ~a rows, ~a nulls, dtype ~a\n"
        (height ignored)
        (null-count (ref ignored #:columns "reading"))
        (dtype (ref ignored #:columns "reading")))
(displayln (tail ignored 3))

(define named (read-csv sensor #:null-values '("n/a" "??")))
(printf "#:null-values '(\"n/a\" \"??\"): ~a nulls\n"
        (null-count (ref named #:columns "reading")))
(delete-file sensor)
