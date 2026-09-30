#lang racket/base

;; Iterating over a dataframe's rows: in-dataframe-rows, Polars' iter_rows.
;;
;; A row is a vector of the selected columns' values, or, with #:named? #t, an
;; immutable hash from column name to value (Polars' named=True). Each value is
;; what `ref` returns. Rows are converted #:buffer-size at a time (512, as
;; Polars' buffer_size), with one bulk copy per column, so a loop over a large
;; frame holds one buffer of values, and one that stops early converts at most
;; one buffer beyond what it reads.
;;
;; Inside `nix develop`:
;;   racket examples/66-dataframe-row-iteration.rkt

(require gregor
         polars)

(define flights
  (dataframe
   (list (series '(UA AA UA DL B6) #:name "carrier")
         (series '("EWR" "LGA" "EWR" "JFK" "JFK") #:name "origin")
         (series (list 2 polars-null -3 15 0) #:name "dep_delay")
         (cast (series (list (datetime 2013 1 1) (datetime 2013 1 1) (datetime 2013 1 2)
                             (datetime 2013 1 2) (datetime 2013 1 3))
                       #:name "day")
               'date))))

;; --- a vector per row ----------------------------------------------------
(for ([row (in-dataframe-rows flights)])
  (writeln row))

;; a row of known width destructures with vector->values
(for ([row (in-dataframe-rows flights #:columns '("carrier" "dep_delay"))])
  (define-values (carrier delay) (vector->values row))
  (printf "~a ~a\n" carrier (if (polars-null? delay) "no departure" delay)))

;; --- a hash per row ------------------------------------------------------
(for ([row (in-dataframe-rows flights #:named? #t #:columns '("origin" "day"))])
  (printf "~a on ~a\n" (hash-ref row "origin") (date->iso8601 (hash-ref row "day"))))
(writeln (for/sum ([row (in-dataframe-rows flights #:named? #t #:null 0)])
           (hash-ref row "dep_delay")))

;; --- buffering -----------------------------------------------------------
;; a smaller buffer makes more copies and holds fewer values; the rows agree
(writeln (equal? (for/list ([row (in-dataframe-rows flights #:buffer-size 2)]) row)
                 (for/list ([row (in-dataframe-rows flights)]) row)))

;; an early exit over a million rows converts only the first buffer
(define squares
  (dataframe (list (series (build-list 1000000 values) #:name "n")
                   (series (build-list 1000000 (lambda (n) (* n n))) #:name "square"))))
(writeln (for/first ([row (in-dataframe-rows squares)]
                     #:when (> (vector-ref row 1) 1000))
           row))

;; the columns are checked when the sequence is made, before any row
(displayln
 (with-handlers ([exn:fail:contract? exn-message])
   (in-dataframe-rows flights #:columns '("carrier" "carrier"))))
