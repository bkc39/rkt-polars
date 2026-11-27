#lang racket/base

;; rkt-polars user guide — Getting started: Combining dataframes
;; Mirrors https://docs.pola.rs/user-guide/getting-started/#combining-dataframes
;; and combining.py.
;;
;; Inside `nix develop`:
;;   racket user-guide/getting-started/combining.rkt

(require gregor
         polars)

(define df
  (dataframe [name '("Alice Archer" "Ben Brown" "Chloe Cooper" "Daniel Donovan")]
             [birthdate (list (date 1997 1 10) (date 1985 2 15) (date 1983 3 22) (date 1981 4 30))]
             [weight '(57.9 72.5 53.6 83.1)]
             ["height" '(1.56 1.77 1.65 1.75)]))

;; --- joining -------------------------------------------------------------
(define df2
  (dataframe [name '("Ben Brown" "Daniel Donovan" "Alice Archer" "Chloe Cooper")]
             [parent '(#t #f #f #f)]
             [siblings '(1 2 3 4)]))

;; API gap: #:on takes a list of names, not a bare name.
(displayln (join df df2 #:on '("name") #:how 'left))

;; --- concatenating -------------------------------------------------------
(define df3
  (dataframe [name '("Ethan Edwards" "Fiona Foster" "Grace Gibson" "Henry Harris")]
             [birthdate (list (date 1977 5 10) (date 1975 6 23) (date 1973 7 22) (date 1971 8 3))]
             [weight '(67.9 72.5 57.6 93.1)]
             ["height" '(1.76 1.6 1.66 1.8)]))

;; API gap: no n-ary concat with a #:how; vstack is pairwise vertical concat.
(displayln (vstack df df3))
