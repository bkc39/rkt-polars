#lang racket/base

;; rkt-polars user guide — Concepts: Data types and structures
;; Mirrors https://docs.pola.rs/user-guide/concepts/data-types-and-structures/
;; and data_types_and_structures.py.
;;
;; Inside `nix develop`:
;;   racket user-guide/concepts/data-types-and-structures.rkt

(require gregor
         polars)

;; --- series --------------------------------------------------------------
(define s (series '(1 2 3 4 5) #:name "ints"))
(displayln s)

(define s1 (series '(1 2 3 4 5) #:name "ints"))
(define s2 (series '(1 2 3 4 5) #:name "uints" #:dtype 'u64))
(printf "~a ~a\n" (dtype s1) (dtype s2))

;; --- dataframe -----------------------------------------------------------
(define df
  (dataframe
   (list (series '("Alice Archer" "Ben Brown" "Chloe Cooper" "Daniel Donovan")
                 #:name "name")
         (series (list (date 1997 1 10) (date 1985 2 15) (date 1983 3 22) (date 1981 4 30))
                 #:name "birthdate")
         (series '(57.9 72.5 53.6 83.1) #:name "weight")
         (series '(1.56 1.77 1.65 1.75) #:name "height"))))

(displayln df)

;; --- inspecting a dataframe ----------------------------------------------
(displayln (head df 3))

;; API gap: no glimpse.

(displayln (tail df 3))

;; API gap: no sample / set_random_seed.

(displayln (describe df))

;; --- schema --------------------------------------------------------------
;; API gap: no schema accessor; pair column-names with each column's dtype.
(for ([name (column-names df)])
  (printf "~a: ~a\n" name (dtype (ref df #:columns name))))

;; The #:dtype of each series plays the role of schema / schema_overrides.
(define df-u8
  (dataframe
   (list (series '("Alice" "Ben" "Chloe" "Daniel") #:name "name")
         (series '(27 39 41 43) #:name "age" #:dtype 'u8))))

(displayln df-u8)
