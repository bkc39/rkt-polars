#lang racket/base

;; Expr string batch 3: lengths, slicing, find, and match counts.
;;
;; Inside `nix develop`:
;;   racket examples/31-expr-string-batch3.rkt

(require polars)

(define df
  (dataframe-new
   (list (series-new-str "text" '("hello" "héllo" "banana" "abc123abc")))))

(define out
  (dataframe-with-columns
   df
   (list (expr-alias (expr-str-len-bytes (col "text")) "bytes")
         (expr-alias (expr-str-len-chars (col "text")) "chars")
         (expr-alias (expr-str-slice (col "text") 1 3) "slice")
         (expr-alias (expr-str-head (col "text") 2) "head")
         (expr-alias (expr-str-tail (col "text") 2) "tail")
         (expr-alias (expr-str-find (col "text") "[0-9]+") "find_digits")
         (expr-alias (expr-str-find-literal (col "text") "na") "find_na")
         (expr-alias (expr-str-count-matches (col "text") "a" #:literal #t)
                     "count_a"))))

(display-dataframe out)
