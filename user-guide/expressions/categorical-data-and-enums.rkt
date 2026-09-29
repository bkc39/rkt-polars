#lang racket/base

;; rkt-polars user guide — Expressions: Categorical data and enums
;; Mirrors https://docs.pola.rs/user-guide/expressions/categorical-data-and-enums/
;; and categorical_data_and_enums.py.
;;
;; Inside `nix develop`:
;;   racket user-guide/expressions/categorical-data-and-enums.rkt

(require polars)

(define (report thunk)
  (with-handlers ([exn:fail? (lambda (e) (displayln (exn-message e)))])
    (thunk)))

;; --- data type Enum: creating an Enum ------------------------------------
(define bears-enum '(enum Polar Panda Brown))
(define bears (series '(Polar Panda Brown Brown Polar) #:dtype bears-enum))
(displayln bears)

;; --- invalid values ------------------------------------------------------
(report (lambda () (series '(Polar Panda Brown Polar Shark) #:dtype bears-enum)))

;; --- category ordering and comparison ------------------------------------
(define log-levels '(enum debug info warning error))

(define logs
  (dataframe
   (list (series '(debug info debug error) #:name "level" #:dtype log-levels)
         (series '("process id: 525" "Service started correctly"
                   "startup time: 67ms" "Cannot connect to DB!")
                 #:name "message"))))

(define non-debug-logs (filter logs (> (col "level") 'debug)))
(displayln non-debug-logs)

(report (lambda () (select logs (> (col "level") "Pretty bad"))))

(define str-series (series '("info" "debug" "debug" "error")))
(displayln (= (ref logs "level") str-series))

;; --- data type Categorical -----------------------------------------------
(define bears-cat (series '(Polar Panda Brown Brown Polar) #:dtype 'categorical))
(displayln bears-cat)

;; --- using Categories objects --------------------------------------------
;; API gap: no pl.Categories; every categorical shares Polars' one global
;; mapping, so the species are a plain categorical.
(displayln
 (dataframe (list (series '(Polar Brown Panda Brown Polar) #:name "species"))))

;; --- lexical comparison with strings -------------------------------------
(displayln
 (~> (dataframe (list (rename bears-cat "categorical")))
     (with-columns (alias (< (col "categorical") "Cat") "categorical < \"Cat\""))))

(displayln
 (~> (dataframe (list (rename bears-cat "categorical")
                      (series '("Panda" "Brown" "Brown" "Polar" "Polar") #:name "string")))
     (with-columns (alias (= (col "categorical") (col "string")) "categorical == string"))))

;; --- combining categorical columns ---------------------------------------
(define male-bears
  (dataframe (list (series '(Polar Brown Panda) #:name "species")
                   (series '(450 500 110) #:name "weight"))))
(define female-bears
  (dataframe (list (series '(Brown Polar Panda) #:name "species")
                   (series '(340 200 90) #:name "weight"))))
(displayln (vstack male-bears female-bears))

;; --- categorical encodings -----------------------------------------------
;; API gap: no Series.extend; stack one-column frames instead.
(define cat-bears (series '(Polar Panda Brown Brown Polar) #:dtype 'categorical))
(define cat2-series (series '(Panda Brown Brown Polar Polar) #:dtype 'categorical))
(displayln (ref (vstack (dataframe (list cat-bears)) (dataframe (list cat2-series))) 0))
