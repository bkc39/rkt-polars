#lang racket/base

;; Polars' `.str` namespace: string transforms and predicates over an Expr.
;; Each mirrors pl.col(x).str.<method>(...).  The first argument is the column
;; to operate on; a bare column-name string is auto-lifted via `col`, so both
;;   (str-to-lowercase (col "name"))  and  (str-to-lowercase "name")
;; work.

(require polars/private/foreign
         polars/private/expr)

(provide str-to-lowercase str-to-uppercase
         str-contains str-starts-with str-ends-with
         str-strip-chars str-strip-prefix str-strip-suffix
         str-replace str-replace-all str-extract
         str-len-bytes str-len-chars str-slice str-head str-tail
         str-find str-find-literal str-count-matches)

;; Lift a column-name string to an Expr; pass an Expr through unchanged.
(define (->str-expr who x)
  (cond [(Expr-ptr? x) x]
        [(string? x)   (col x)]
        [else (error who "expected an Expr or column name, got ~v" x)]))

(define (str-to-lowercase x)
  (expr-str-to-lowercase (->str-expr 'str-to-lowercase x)))
(define (str-to-uppercase x)
  (expr-str-to-uppercase (->str-expr 'str-to-uppercase x)))
(define (str-contains x pattern)
  (expr-str-contains (->str-expr 'str-contains x) pattern))
(define (str-starts-with x prefix)
  (expr-str-starts-with (->str-expr 'str-starts-with x) prefix))
(define (str-ends-with x suffix)
  (expr-str-ends-with (->str-expr 'str-ends-with x) suffix))

;; strip whitespace (no chars) or the given chars from both ends; strip a fixed
;; prefix / suffix.
(define (str-strip-chars x [chars #f])
  (expr-str-strip-chars (->str-expr 'str-strip-chars x) chars))
(define (str-strip-prefix x prefix)
  (expr-str-strip-prefix (->str-expr 'str-strip-prefix x) prefix))
(define (str-strip-suffix x suffix)
  (expr-str-strip-suffix (->str-expr 'str-strip-suffix x) suffix))

;; regex replace (first / all matches); `#:literal #t` treats pattern as plain
;; text.  `str-extract` returns the `#:group-index` capture group (default 1).
(define (str-replace x pat value #:literal [literal #f])
  (expr-str-replace (->str-expr 'str-replace x) pat value #:literal literal))
(define (str-replace-all x pat value #:literal [literal #f])
  (expr-str-replace-all (->str-expr 'str-replace-all x) pat value #:literal literal))
(define (str-extract x pat #:group-index [group-index 1])
  (expr-str-extract (->str-expr 'str-extract x) pat #:group-index group-index))

;; byte / char length; substring by (offset length); first / last n chars.
;; These are the .str-namespaced analogues of the row-level slice / head / tail.
(define (str-len-bytes x) (expr-str-len-bytes (->str-expr 'str-len-bytes x)))
(define (str-len-chars x) (expr-str-len-chars (->str-expr 'str-len-chars x)))
(define (str-slice x offset length)
  (expr-str-slice (->str-expr 'str-slice x) offset length))
(define (str-head x n) (expr-str-head (->str-expr 'str-head x) n))
(define (str-tail x n) (expr-str-tail (->str-expr 'str-tail x) n))

;; find a regex (`#:strict` raises on invalid pattern) / a literal substring;
;; count matches (`#:literal #t` counts a plain substring instead of a regex).
(define (str-find x pat #:strict [strict #t])
  (expr-str-find (->str-expr 'str-find x) pat #:strict strict))
(define (str-find-literal x pat)
  (expr-str-find-literal (->str-expr 'str-find-literal x) pat))
(define (str-count-matches x pat #:literal [literal #f])
  (expr-str-count-matches (->str-expr 'str-count-matches x) pat #:literal literal))

(module+ test
  (require rackunit (only-in threading ~>)
           polars/private/generic/core
           polars/private/generic/reductions   ; alias
           polars/private/generic/reshape)     ; lazy / with-columns / collect
  (define df (dataframe (list (series '("Ab" "cD" "ef") #:name "s"))))
  (define out
    (~> df lazy
        (with-columns
          (alias (str-to-lowercase "s") "lo")
          (alias (str-to-uppercase "s") "hi")
          (alias (str-contains "s" "b") "has_b")
          (alias (str-starts-with "s" "A") "starts_a")
          (alias (str-ends-with "s" "f") "ends_f"))
        collect))
  (check-equal? (ref (ref out #:columns "lo") 0) "ab")
  (check-equal? (ref (ref out #:columns "hi") 1) "CD")
  (check-equal? (ref (ref out #:columns "has_b") 0) #t)
  (check-equal? (ref (ref out #:columns "has_b") 1) #f)
  (check-equal? (ref (ref out #:columns "starts_a") 0) #t)
  (check-equal? (ref (ref out #:columns "ends_f") 2) #t)
  ;; an Expr argument works the same as a column-name string
  (check-equal? (ref (ref (~> df (with-columns (alias (str-to-uppercase (col "s")) "u")))
                          #:columns "u")
                     0)
                "AB")
  ;; batch 2: strip / replace / extract
  (define t
    (dataframe (list (series '("  alpha  " "--beta--" "id=123" "report.txt" "banana")
                             #:name "text"))))
  (define out2
    (~> t (with-columns
            (alias (str-strip-chars "text") "trimmed")
            (alias (str-strip-chars "text" "-") "stripped")
            (alias (str-strip-prefix "text" "id=") "no_prefix")
            (alias (str-strip-suffix "text" ".txt") "no_suffix")
            (alias (str-replace "text" "\\d+" "#") "rep")
            (alias (str-replace-all "text" "a" "A" #:literal #t) "rep_all")
            (alias (str-extract "text" "([0-9]+)") "digits"))))
  (check-equal? (ref (ref out2 #:columns "trimmed") 0) "alpha")
  (check-equal? (ref (ref out2 #:columns "stripped") 1) "beta")
  (check-equal? (ref (ref out2 #:columns "no_prefix") 2) "123")
  (check-equal? (ref (ref out2 #:columns "no_suffix") 3) "report")
  (check-equal? (ref (ref out2 #:columns "rep") 2) "id=#")
  (check-equal? (ref (ref out2 #:columns "rep_all") 4) "bAnAnA")
  (check-equal? (ref (ref out2 #:columns "digits") 2) "123")
  ;; batch 3: lengths / slice / head / tail / find / count
  (define u
    (dataframe (list (series '("hello" "héllo" "banana" "abc123abc") #:name "text"))))
  (define out3
    (~> u (with-columns
            (alias (str-len-bytes "text") "bytes")
            (alias (str-len-chars "text") "chars")
            (alias (str-slice "text" 1 3) "slice")
            (alias (str-head "text" 2) "head")
            (alias (str-tail "text" 2) "tail")
            (alias (str-find "text" "[0-9]+") "find_d")
            (alias (str-find-literal "text" "na") "find_na")
            (alias (str-count-matches "text" "a" #:literal #t) "count_a"))))
  (check-equal? (ref (ref out3 #:columns "bytes") 1) 6)   ; é is 2 bytes
  (check-equal? (ref (ref out3 #:columns "chars") 1) 5)
  (check-equal? (ref (ref out3 #:columns "slice") 0) "ell")
  (check-equal? (ref (ref out3 #:columns "head") 1) "hé")
  (check-equal? (ref (ref out3 #:columns "tail") 2) "na")
  (check-equal? (ref (ref out3 #:columns "find_d") 3) 3)
  (check-equal? (ref (ref out3 #:columns "find_na") 2) 2)
  (check-equal? (ref (ref out3 #:columns "count_a") 2) 3))
