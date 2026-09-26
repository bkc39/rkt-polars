#lang info

;; The project's Resyntax suite, module path `lint`.  It needs Resyntax, which
;; the dev shell installs and the rkt-polars build does not have, so setup
;; never compiles this collection; scripts/resyntax-lint.sh and `raco test
;; lint` load it in the dev shell.
(define compile-omit-paths 'all)
(define test-include-paths '(#rx"[.]resyntax$"))
