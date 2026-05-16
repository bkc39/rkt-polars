#lang racket/base

;; Expr string batch 2: trim, strip prefixes/suffixes, replace, and extract.
;;
;; Inside `nix develop`:
;;   racket examples/24-expr-string-batch2.rkt

(require polars)

(define df
  (dataframe-new
   (list (series-new-str "text"
                         '("  alpha  "
                           "--beta--"
                           "id=123"
                           "report.txt"
                           "banana")))))

(define out
  (dataframe-with-columns
   df
   (list (expr-alias (expr-str-strip-chars (col "text")) "trimmed")
         (expr-alias (expr-str-strip-chars (col "text") "-") "stripped")
         (expr-alias (expr-str-strip-prefix (col "text") "id=") "no_prefix")
         (expr-alias (expr-str-strip-suffix (col "text") ".txt") "no_suffix")
         (expr-alias (expr-str-replace (col "text") "\\d+" "#") "replace_digits")
         (expr-alias (expr-str-replace-all (col "text") "a" "A" #:literal #t)
                     "replace_all_a")
         (expr-alias (expr-str-extract (col "text") "([0-9]+)") "digits"))))

(display-dataframe out)
