#lang setup/infotab

;; This collection is the package published to pkgs.rkt-lang.org as `polars`
;; (the catalog source is the repo with ?path=polars).  All package metadata
;; the catalog needs must therefore live here, not in the repo-root info.rkt.

(define name "polars")

(define deps '("base" "gregor-lib"))
(define build-deps '("scribble-lib" "racket-doc" "rackunit-lib"))

(define scribblings '(("scribblings/polars.scrbl" (multi-page))))

(define pkg-desc "Racket bindings to the Polars DataFrame library")
(define version "0.0.1")
(define pkg-authors '(bkc))
(define license '(Apache-2.0 OR MIT))

;; Copies the prebuilt libcompat shared object into native-libs/ at install
;; time; see private/install-compat.rkt.
(define pre-install-collection "private/install-compat.rkt")
(define compile-omit-files '("private/install-compat.rkt"))
