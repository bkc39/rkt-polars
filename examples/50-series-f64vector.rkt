#lang racket/base

;; A numeric series as an f64vector: series->f64vector (Polars' to_numpy).
;;
;; The result is an ffi/vector f64vector, the buffer foreign numeric code
;; takes. Integers and booleans are cast to flonums while copying; a null
;; becomes +nan.0 by default, any other real with #:null, or an error with
;; #:null 'error.
;;
;; Inside `nix develop`:
;;   racket examples/50-series-f64vector.rkt

(require ffi/vector
         polars)

(define ints (series (list 1 2 polars-null 4) #:name "ints"))

(writeln (f64vector->list (series->f64vector ints)))
(writeln (f64vector->list (series->f64vector ints #:null 0)))
(writeln (f64vector->list (series->f64vector (series (list #t #f #t)))))
(writeln (f64vector->list (series->f64vector (series '(0.25 0.5) #:dtype 'f32))))

;; 'error refuses a null, naming its row
(displayln
 (with-handlers ([exn:fail:contract? exn-message])
   (series->f64vector ints #:null 'error)))
(writeln (f64vector->list (series->f64vector (series '(3 1 2)) #:null 'error)))

;; a column that is not numeric is refused, naming its dtype
(displayln
 (with-handlers ([exn:fail:contract? exn-message])
   (series->f64vector (series '("a" "b") #:name "letters"))))

;; the buffer is ordinary Racket data
(define v (series->f64vector ints #:null 0))
(writeln (for/sum ([i (in-range (f64vector-length v))]) (f64vector-ref v i)))
(writeln (f64vector-length v))
