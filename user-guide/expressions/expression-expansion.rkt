#lang racket/base

;; rkt-polars user guide — Expressions: Expression expansion
;; Mirrors https://docs.pola.rs/user-guide/expressions/expression-expansion/
;; and expression_expansion.py.
;;
;; Inside `nix develop`:
;;   racket user-guide/expressions/expression-expansion.rkt

(require polars)

(define df
  (dataframe
   (list (series '("AAPL" "NVDA" "MSFT" "GOOG" "AMZN") #:name "ticker")
         (series '("Apple" "NVIDIA" "Microsoft" "Alphabet (Google)" "Amazon")
                 #:name "company_name")
         (series '(229.9 138.93 420.56 166.41 188.4) #:name "price")
         (series '(231.31 139.6 424.04 167.62 189.83) #:name "day_high")
         (series '(228.6 136.3 417.52 164.78 188.44) #:name "day_low")
         (series '(237.23 140.76 468.35 193.31 201.2) #:name "year_high")
         (series '(164.08 39.23 324.39 121.46 118.35) #:name "year_low"))))

(displayln df)

;; --- function col --------------------------------------------------------
;; API gap: col takes one name, so build one expression per name; a list of
;; expressions is spliced into the context.
(define eur-usd-rate 1.09)
(displayln
 (~> df
     (with-columns
      (for/list ([name '("price" "day_high" "day_low" "year_high" "year_low")])
        (~> (col name) (/ eur-usd-rate) (round #:decimals 2))))))

(displayln
 (~> df (with-columns (~> (col 'float64) (/ eur-usd-rate) (round #:decimals 2)))))

;; API gap: col takes one dtype and selectors do not compose yet (#50), so
;; one expression per dtype.
(displayln
 (~> df
     (with-columns
      (for/list ([type '(float32 float64)])
        (~> (col type) (/ eur-usd-rate) (round #:decimals 2))))))

(displayln (select df "ticker" (col "^.*_high$") (col "^.*_low$")))

;; A Racket regexp keeps its Racket meaning.
(displayln (select df "ticker" (col #rx"_(high|low)$")))
(displayln (select df (col #px"^\\w+_high$")))

;; Polars' regex engine has no lookaround: match the names in Racket.
(define not-day #px"^(?!day_).*_(high|low)$")
(with-handlers ([exn:fail? (lambda (e) (displayln (exn-message e)))])
  (select df (col not-day)))
(displayln
 (select df (filter (lambda (name) (regexp-match? not-day name))
                    (column-names df))))

;; Each col is one name, dtype or pattern; mix them as separate specs.
(displayln (select df "ticker" (col 'float64)))

;; --- selecting all columns -----------------------------------------------
;; API gap: no DataFrame.equals.
(displayln (select df (all)))

;; --- excluding columns ---------------------------------------------------
(displayln (select df (exclude (all) "^day_.*$")))
(displayln (select df (~> (col 'float64) (exclude #rx"^day_"))))

;; --- column renaming -----------------------------------------------------
(define gbp-usd-rate 1.31)
(with-handlers ([exn:fail? (lambda (e) (displayln (exn-message e)))])
  (select df
          (/ (col "price") gbp-usd-rate)
          (/ (col "price") eur-usd-rate)))

(displayln
 (select df
         (~> (col "price") (/ gbp-usd-rate) (alias "price (GBP)"))
         (~> (col "price") (/ eur-usd-rate) (alias "price (EUR)"))))

;; API gap: no name.prefix / name.suffix (#51); alias each column.
(displayln
 (select df
         (for/list ([name (column-names df)]
                    #:when (regexp-match? #rx"^year_" name))
           (~> (col name) (/ eur-usd-rate) (alias (string-append "in_eur_" name))))
         (for/list ([name '("day_high" "day_low")])
           (~> (col name) (/ gbp-usd-rate) (alias (string-append name "_gbp"))))))

;; API gap: no name.map.
(displayln
 (select df (for/list ([name (column-names df)])
              (alias (col name) (string-upcase name)))))

;; --- programmatically generating expressions -----------------------------
(define (amplitude-expressions time-periods)
  (for/list ([tp (in-list time-periods)])
    (~> (col (string-append tp "_high"))
        (- (col (string-append tp "_low")))
        (alias (string-append tp "_amplitude")))))

(displayln (~> df (with-columns (amplitude-expressions '("day" "year")))))

;; --- more flexible column selections -------------------------------------
;; API gap: no polars.selectors, and no set operations on selectors (#50).
(displayln (select df (col 'string) (col #rx"_high$")))
(displayln
 (select df (for/list ([name (column-names df)]
                       #:when (and (regexp-match? #rx"_" name)
                                   (not (eq? (dtype (ref df name)) 'string))))
              name)))

(define people
  (dataframe (list (series '("Anna" "Bob") #:name "name")
                   (series '(#t #f) #:name "has_partner")
                   (series '(#f #f) #:name "has_kids")
                   (series '(#t #f) #:name "has_tattoos")
                   (series '(#t #t) #:name "is_alive"))))

;; API gap: no name.prefix, so the negated columns keep their names.
(displayln (select people (not (col #rx"^has_"))))

;; Debugging selectors: multi-column-expr? plays cs.is_selector; selecting
;; from the frame plays cs.expand_selector.
(displayln (multi-column-expr? (not (col #rx"^has_"))))
(displayln (~> people (select (col #rx"^has_")) column-names))
(displayln
 (for/list ([e (amplitude-expressions '("day" "year"))])
   (list (meta-output-name e) (meta-root-names e))))
