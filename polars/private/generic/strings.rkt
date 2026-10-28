#lang racket/base

;; Polars' `.str` namespace: string transforms and predicates over an Expr.
;; Each mirrors pl.col(x).str.<method>(...).  The first argument is the column
;; to operate on; a bare column-name string is auto-lifted via `col`, so both
;;   (str-to-lowercase (col "name"))  and  (str-to-lowercase "name")
;; work.

(require racket/contract/base
         (only-in racket/string non-empty-string?)
         polars/private/foreign
         polars/private/expr
         (only-in polars/private/c-integer int64/c nonnegative-int64/c size/c)
         (only-in polars/private/expr-str parse-datetime)
         polars/private/generic/expr-util)

(provide str-to-lowercase str-to-uppercase
         str-contains str-starts-with str-ends-with
         str-strip-chars str-strip-prefix str-strip-suffix
         str-replace str-replace-all
         str-len-bytes str-len-chars str-head str-tail
         str-find str-find-literal str-count-matches
         str->date str->time
         (contract-out
          [str-extract (->* (col-expr/c any/c) (#:group-index size/c) Expr-ptr?)]
          [str-slice (->* (col-expr/c (or/c Expr-ptr? int64/c))
                          ((or/c #f polars-null? Expr-ptr? nonnegative-int64/c))
                          Expr-ptr?)]
          [str->datetime (->* (col-expr/c)
                              (#:format (or/c #f string?)
                               #:unit (or/c 'milliseconds 'microseconds 'nanoseconds)
                               #:time-zone (or/c #f non-empty-string?)
                               #:ambiguous (or/c 'raise 'earliest 'latest 'null)
                               #:strict boolean?
                               #:exact boolean?
                               #:cache boolean?)
                              Expr-ptr?)]))

(define-expr-unop str-to-lowercase 'str-to-lowercase expr-str-to-lowercase)
(define-expr-unop str-to-uppercase 'str-to-uppercase expr-str-to-uppercase)
(define (str-contains x pattern)
  (expr-str-contains (->col-expr 'str-contains x) (->expr/who 'str-contains pattern)))
(define (str-starts-with x prefix)
  (expr-str-starts-with (->col-expr 'str-starts-with x) (->expr/who 'str-starts-with prefix)))
(define (str-ends-with x suffix)
  (expr-str-ends-with (->col-expr 'str-ends-with x) (->expr/who 'str-ends-with suffix)))

;; strip whitespace (no chars) or the given chars from both ends; strip a fixed
;; prefix / suffix.
(define (str-strip-chars x [chars #f])
  (expr-str-strip-chars (->col-expr 'str-strip-chars x)
                        (and chars (->expr/who 'str-strip-chars chars))))
(define (str-strip-prefix x prefix)
  (expr-str-strip-prefix (->col-expr 'str-strip-prefix x) (->expr/who 'str-strip-prefix prefix)))
(define (str-strip-suffix x suffix)
  (expr-str-strip-suffix (->col-expr 'str-strip-suffix x) (->expr/who 'str-strip-suffix suffix)))

;; regex replace (first / all matches); `#:literal #t` treats pattern as plain
;; text.  `str-extract` returns the `#:group-index` capture group (default 1).
(define (str-replace x pat value #:literal [literal #f])
  (expr-str-replace (->col-expr 'str-replace x) (->expr/who 'str-replace pat)
                    (->expr/who 'str-replace value) #:literal literal))
(define (str-replace-all x pat value #:literal [literal #f])
  (expr-str-replace-all (->col-expr 'str-replace-all x) (->expr/who 'str-replace-all pat)
                        (->expr/who 'str-replace-all value) #:literal literal))
(define (str-extract x pat #:group-index [group-index 1])
  (expr-str-extract (->col-expr 'str-extract x) (->expr/who 'str-extract pat)
                    #:group-index group-index))

;; byte / char length; substring by (offset length); first / last n chars.
;; These are the .str-namespaced analogues of the row-level slice / head / tail.
(define-expr-unop str-len-bytes 'str-len-bytes expr-str-len-bytes)
(define-expr-unop str-len-chars 'str-len-chars expr-str-len-chars)
(define (str-slice x offset [length #f])
  (expr-str-slice (->col-expr 'str-slice x) offset length))
(define (str-head x n) (expr-str-head (->col-expr 'str-head x) (->expr/who 'str-head n)))
(define (str-tail x n) (expr-str-tail (->col-expr 'str-tail x) (->expr/who 'str-tail n)))

;; find a regex (`#:strict` raises on invalid pattern) / a literal substring;
;; count matches (`#:literal #t` counts a plain substring instead of a regex).
(define (str-find x pat #:strict [strict #t])
  (expr-str-find (->col-expr 'str-find x) (->expr/who 'str-find pat) #:strict strict))
(define (str-find-literal x pat)
  (expr-str-find-literal (->col-expr 'str-find-literal x) (->expr/who 'str-find-literal pat)))
(define (str-count-matches x pat #:literal [literal #f])
  (expr-str-count-matches (->col-expr 'str-count-matches x) (->expr/who 'str-count-matches pat)
                          #:literal literal))

;; parse strings to Date / Datetime / Time.  #:strict #f turns unparseable
;; values into null instead of raising; #:format is a chrono strptime pattern
;; (inferred when omitted); #:exact #f allows surrounding text;
;; str->datetime also takes #:unit ('milliseconds | 'microseconds | 'nanoseconds).
(define (str->date x #:format [format #f] #:strict [strict #t]
                   #:exact [exact #t] #:cache [cache #t])
  (expr-str->date (->col-expr 'str->date x)
                  #:format format #:strict strict #:exact exact #:cache cache))
(define (str->datetime x #:format [format #f] #:unit [unit 'microseconds]
                       #:time-zone [time-zone #f] #:ambiguous [ambiguous 'raise]
                       #:strict [strict #t] #:exact [exact #t] #:cache [cache #t])
  (parse-datetime 'str->datetime (->col-expr 'str->datetime x)
                  format unit time-zone ambiguous strict exact cache))
(define (str->time x #:format [format #f] #:strict [strict #t]
                   #:exact [exact #t] #:cache [cache #t])
  (expr-str->time (->col-expr 'str->time x)
                  #:format format #:strict strict #:exact exact #:cache cache))

(module+ internal
  (provide str->datetime str-extract str-slice))
