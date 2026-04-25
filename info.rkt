#lang setup/infotab

(define collection 'multi)
(define deps '("base" "gregor-lib"))
(define build-deps '("scribble-lib" "racket-doc" "rackunit-lib"))
(define scribblings '(("scribblings/rkt-polars.scrbl" ())))
(define pkg-desc "Racket bindings to the polars library")
(define version "0.0.1")
(define pkg-authors '(bkc))
(define license '(Apache-2.0 OR MIT))
