#lang racket/base

;; Every row at once: dataframe->rows, Polars' rows(), and with #:named? #t
;; rows(named=True), which is to_dicts().
;;
;; The rows are those in-dataframe-rows gives, collected into a list, so plain
;; Racket code can take a frame as a list of vectors or of hashes.
;;
;; Inside `nix develop`:
;;   racket examples/67-dataframe-rows.rkt

(require polars)

(define flights
  (dataframe (list (series '(UA AA UA DL AA) #:name "carrier")
                   (series (list 2 polars-null -3 15 7) #:name "dep_delay")
                   (series '(1400 1089 1400 762 1089) #:name "distance"))))

;; --- rows() and to_dicts() -----------------------------------------------
(writeln (dataframe->rows flights))
(for-each writeln (dataframe->rows flights #:named? #t))
(writeln (dataframe->rows flights #:columns '("distance" "carrier")))

;; --- plain Racket over the rows ------------------------------------------
;; total delay per carrier, a missing delay counted as 0
(define totals
  (for/fold ([acc (hash)]) ([row (in-list (dataframe->rows flights #:named? #t #:null 0))])
    (hash-update acc (hash-ref row "carrier") (lambda (t) (+ t (hash-ref row "dep_delay"))) 0)))
(for ([carrier '(AA DL UA)])
  (printf "~a: ~a\n" carrier (hash-ref totals carrier)))

;; the same totals from Polars, read back as rows
(define summed (~> flights (group-by "carrier") (agg (sum "dep_delay"))))
(writeln (equal? totals
                 (for/hash ([row (in-list (dataframe->rows summed))])
                   (values (vector-ref row 0) (vector-ref row 1)))))

;; a frame with no rows gives no rows; a bad name is refused
(writeln (dataframe->rows (head flights 0)))
(displayln
 (with-handlers ([exn:fail:contract? exn-message])
   (dataframe->rows flights #:columns '("nope"))))
