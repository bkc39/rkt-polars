#lang racket/base

;; Expr string batch 3: lengths, slicing, find, and match counts.
;;
;; The .str slicing ops are str-prefixed (str-slice / str-head / str-tail) so
;; they don't collide with the row-level slice / head / tail.
;;
;; Inside `nix develop`:
;;   racket examples/31-expr-string-batch3.rkt

(require polars)

(define df
  (dataframe (list (series '("hello" "héllo" "banana" "abc123abc") #:name "text"))))

(define out
  (~> df
      (with-columns
        (alias (str-len-bytes "text") "bytes")
        (alias (str-len-chars "text") "chars")
        (alias (str-slice "text" 1 3) "slice")
        (alias (str-head "text" 2) "head")
        (alias (str-tail "text" 2) "tail")
        (alias (str-find "text" "[0-9]+") "find_digits")
        (alias (str-find-literal "text" "na") "find_na")
        (alias (str-count-matches "text" "a" #:literal #t) "count_a"))))

(displayln out)
