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
         str-replace str-replace-all str-extract)

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
  (check-equal? (ref (ref out2 #:columns "digits") 2) "123"))
