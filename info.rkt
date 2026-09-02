#lang setup/infotab

(define collection 'multi)
(define deps '("base" "gregor-lib" "threading-lib"))
(define build-deps '("scribble-lib" "racket-doc" "rackunit-lib" "threading-doc"))
;; Documentation lives in the published `polars` collection
;; (polars/scribblings/polars.scrbl); this whole-repo package builds it from
;; there.  Declaring scribblings here too would document module `polars`
;; twice.
(define pkg-desc "Racket bindings to the polars library")
(define version "0.0.1")
(define pkg-authors '(bkc))
(define license '(Apache-2.0 OR MIT))
