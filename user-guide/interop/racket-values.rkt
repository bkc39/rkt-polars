#lang racket/base

;; rkt-polars user guide — Interoperability: Series to Racket values,
;; iterating, and columns as Racket data.
;; Mirrors https://docs.pola.rs/user-guide/misc/arrow/ (handing a frame's data
;; to another library), through Series.to_list and DataFrame.to_dict, and
;; racket_values.py.
;;
;; Inside `nix develop`:
;;   racket user-guide/interop/racket-values.rkt

(require gregor
         polars)

(define df
  (dataframe (list (series '(1 2 3) #:name "foo")
                   (series '("ham" "spam" "jam") #:name "bar"))))

;; --- series to Racket values ---------------------------------------------
(writeln (~> df (ref "foo") series->list))
(writeln (~> df (ref "bar") series->vector))

(define gappy (series (list 1 polars-null 3) #:name "value"))
(writeln (series->list gappy))
(writeln (series->list gappy #:null 0))

;; every dtype family comes out as the value `ref` returns
(define people
  (~> (dataframe
       (list (series '("Alice Archer" "Ben Brown") #:name "name")
             (series (list (datetime 1997 1 10 8 30 0) (datetime 1985 2 15 17 0 0))
                     #:name "birthdate")
             (series '(57.9 72.5) #:name "weight")
             (series '(#t #f) #:name "parent")))
      (with-columns (alias (cast "birthdate" 'date) "birthday")
                    (alias (cast "birthdate" 'time) "clock"))))
(for ([name (column-names people)])
  (printf "~a: ~s\n" name (~> people (ref name) series->list)))
;; API gap: datetimes are floored to the whole second; binary has no value.

;; --- iterating -----------------------------------------------------------
(writeln (for/list ([word (ref df "bar")]) (string-upcase word)))
(writeln (for/sum ([v (in-series gappy #:null 0)]) v))
(writeln (for/first ([v (in-series (series (build-list 1000000 values)))]
                     #:when (> v 41))
           v))

;; --- columns as Racket data ----------------------------------------------
(writeln (dataframe->columns df))
(writeln (dataframe->columns people #:columns '("weight" "name")))
