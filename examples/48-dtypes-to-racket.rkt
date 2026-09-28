#lang racket/base

;; Every dtype family to Racket values.
;;
;; Integers come out as exact integers, floats as flonums, booleans as #t/#f,
;; strings as strings, and the temporal dtypes as gregor values: a date, a
;; datetime (floored to the second, as `ref` gives), a time and a period.
;;
;; Inside `nix develop`:
;;   racket examples/48-dtypes-to-racket.rkt

(require gregor
         polars)

(define (show s)
  (printf "~s: ~s\n" (dtype s) (series->list s)))

;; numeric
(show (series (list -8 polars-null 127) #:dtype 'i8))
(show (series (list 0 (sub1 (expt 2 64))) #:dtype 'u64))
(show (series (list 0.1 polars-null) #:dtype 'f32))
(show (series (list -0.0 +inf.0 +nan.0 polars-null)))

;; string and boolean
(show (series (list "héllo" "" polars-null "日本語")))
(show (series (list #t #f polars-null)))

;; temporal
(define stamps (series (list (datetime 2024 1 2 3 4 5) polars-null) #:name "t"))
(show stamps)
(show (cast stamps 'date))
(show (cast stamps 'time))
(show (cast (series (list 1500 -250 polars-null) #:dtype 'i64)
            '(duration milliseconds)))

;; a series of nulls only
(show (cast (series (list polars-null polars-null) #:dtype 'i64) 'null))

;; a dtype with no Racket value is refused, naming the dtype
(displayln
 (with-handlers ([exn:fail:contract? exn-message])
   (series->list (cast (series '("raw") #:name "blob") 'binary))))
