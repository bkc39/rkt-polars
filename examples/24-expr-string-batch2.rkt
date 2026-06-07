#lang racket/base

;; Expr string batch 2: trim, strip prefixes/suffixes, replace, and extract.
;;
;; All .str transforms are prefix-free and data-first, with bare column-name
;; strings auto-lifted to (col ...), so they thread through with-columns.
;;
;; Inside `nix develop`:
;;   racket examples/24-expr-string-batch2.rkt

(require polars)

(define df
  (dataframe
   (list (series '("  alpha  "
                   "--beta--"
                   "id=123"
                   "report.txt"
                   "banana")
                 #:name "text"))))

(define out
  (~> df
      (with-columns
        (alias (str-strip-chars "text") "trimmed")
        (alias (str-strip-chars "text" "-") "stripped")
        (alias (str-strip-prefix "text" "id=") "no_prefix")
        (alias (str-strip-suffix "text" ".txt") "no_suffix")
        (alias (str-replace "text" "\\d+" "#") "replace_digits")
        (alias (str-replace-all "text" "a" "A" #:literal #t) "replace_all_a")
        (alias (str-extract "text" "([0-9]+)") "digits"))))

(displayln out)
