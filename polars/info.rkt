#lang setup/infotab

;; This collection is the package published to pkgs.rkt-lang.org as `polars`
;; (the catalog source is the repo with ?path=polars).  All package metadata
;; the catalog needs must therefore live here, not in the repo-root info.rkt.

(define name "polars")

(define deps '("base" "gregor-lib" "threading-lib"))
(define build-deps '("scribble-lib" "racket-doc" "rackunit-lib" "threading-doc"
                      "sandbox-lib" "plot-lib" "plot-gui-lib" "plot-doc"))

(define scribblings '(("scribblings/polars.scrbl" (multi-page))))

(define pkg-desc "Racket bindings to the Polars DataFrame library")
(define version "0.2")
(define pkg-authors '(bkc))
(define license '(Apache-2.0 OR MIT))

;; Copies the prebuilt libcompat shared object into native-libs/ at install
;; time; see private/install-compat.rkt.
(define pre-install-collection "private/install-compat.rkt")
(define compile-omit-files '("private/install-compat.rkt"))

(define test-timeouts
  '(("tests/generic/core.rkt" 600)
    ("tests/generic/csv-options.rkt" 900)))

;; scribblings/polars.scrbl includes every other chapter, so its run alone
;; runs each example of the manual once.
(define test-omit-paths
  '("scribblings/guide.scrbl"
    "scribblings/reference.scrbl"
    "scribblings/guide/concepts.scrbl"
    "scribblings/guide/expressions.scrbl"
    "scribblings/guide/getting-started.scrbl"
    "scribblings/guide/interop.scrbl"
    "scribblings/guide/io-json.scrbl"
    "scribblings/guide/io-parquet.scrbl"
    "scribblings/guide/io.scrbl"
    "scribblings/guide/nycflights.scrbl"
    "scribblings/guide/time-series.scrbl"))
