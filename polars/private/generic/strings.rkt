#lang racket/base

;; Polars' `.str` namespace: string transforms and predicates over an Expr.
;; Each mirrors pl.col(x).str.<method>(...).  The first argument is the column
;; to operate on; a bare column-name string is auto-lifted via `col`, so both
;;   (str-to-lowercase (col "name"))  and  (str-to-lowercase "name")
;; work.

(require polars/private/foreign
         polars/private/expr)

(provide str-to-lowercase str-to-uppercase
         str-contains str-starts-with str-ends-with)

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
                "AB"))
