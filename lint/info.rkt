#lang info

;; The rkt-polars build has no Resyntax, so nothing may compile this tree:
;; `raco setup --check-pkg-deps` reads any lint/compiled/ as rkt-polars
;; depending on Resyntax.  Resyntax and `raco test lint` load it from source.
(define compile-omit-paths 'all)
(define test-include-paths '(#rx"[.]resyntax$"))
