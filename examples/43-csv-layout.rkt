#lang racket/base

;; CSV layout: quoting, comments, encoding, header and row window.
;;
;; #:quote-char sets the character that wraps a field holding the separator
;; (#\" by default, #f for none; it must differ from the separator);
;; #:comment-prefix skips lines that start with it (one character or more);
;; #:encoding 'utf8-lossy reads invalid UTF-8 as U+FFFD instead of failing;
;; #:has-header, #:skip-rows and #:n-rows choose the header and the rows to
;; read, on the eager reader as on scan-csv.
;;
;; Inside `nix develop`:
;;   racket examples/43-csv-layout.rkt

(require racket/file
         polars)

(define (report thunk)
  (with-handlers ([exn:fail? (lambda (e)
                               (displayln (car (regexp-split #rx"\n  in:" (exn-message e)))))])
    (thunk)))

(define (scratch name . lines)
  (define path (make-temporary-file (string-append "rkt-polars-layout-~a-" name)))
  (display-lines-to-file lines path #:exists 'replace)
  path)

(define quoted (scratch "quoted.csv" "carrier,note" "UA,\"late, weather\"" "AA,on time"))
(displayln "default #:quote-char #\\\":")
(displayln (read-csv quoted))
(displayln "#:quote-char #f keeps the quotes, and the comma splits the field:")
(report (lambda () (read-csv quoted #:quote-char #f)))
(newline)

(define primed (scratch "primed.csv" "carrier;note" "UA;'late; weather'" "AA;on time"))
(displayln "#:separator #\\; #:quote-char #\\':")
(displayln (read-csv primed #:separator #\; #:quote-char #\'))
(displayln "a quote character equal to the separator is refused:")
(report (lambda () (read-csv primed #:separator #\; #:quote-char #\;)))
(newline)

(define commented (scratch "commented.csv" "# exported by hand" "x,y" "1,2" "# checked" "3,4"))
(displayln "#:comment-prefix \"#\":")
(displayln (read-csv commented #:comment-prefix "#"))
(define slashed (scratch "slashed.csv" "x,y" "// header note" "5,6"))
(displayln "#:comment-prefix \"//\":")
(displayln (read-csv slashed #:comment-prefix "//"))
(newline)

(define latin (make-temporary-file "rkt-polars-layout-~a-latin1.csv"))
(call-with-output-file latin #:exists 'replace
  (lambda (out) (void (write-bytes #"carrier,name\nZZ,Caf\351 Air\n" out))))
(displayln "Latin-1 bytes, default #:encoding 'utf8:")
(report (lambda () (read-csv latin)))
(displayln "#:encoding 'utf8-lossy:")
(displayln (read-csv latin #:encoding 'utf8-lossy))
(newline)

(define framed (scratch "framed.csv" "exported 2013-01-02" "1,a" "2,b" "3,c" "4,d"))
(displayln "#:skip-rows 1 #:has-header #f #:n-rows 2:")
(displayln (read-csv framed #:skip-rows 1 #:has-header #f #:n-rows 2))

(for-each delete-file (list quoted primed commented slashed latin framed))
