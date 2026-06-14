#lang racket/base

;; Polars' `.str` namespace: string transforms and predicates over an Expr.
;; Each mirrors pl.col(x).str.<method>(...).  The first argument is the column
;; to operate on; a bare column-name string is auto-lifted via `col`, so both
;;   (str-to-lowercase (col "name"))  and  (str-to-lowercase "name")
;; work.

(require polars/private/foreign
         polars/private/expr
         polars/private/generic/expr-util)

(provide str-to-lowercase str-to-uppercase
         str-contains str-starts-with str-ends-with
         str-strip-chars str-strip-prefix str-strip-suffix
         str-replace str-replace-all str-extract
         str-len-bytes str-len-chars str-slice str-head str-tail
         str-find str-find-literal str-count-matches
         str-to-date str-to-datetime str-to-time)

(define-expr-unop str-to-lowercase 'str-to-lowercase expr-str-to-lowercase)
(define-expr-unop str-to-uppercase 'str-to-uppercase expr-str-to-uppercase)
(define (str-contains x pattern)
  (expr-str-contains (->col-expr 'str-contains x) pattern))
(define (str-starts-with x prefix)
  (expr-str-starts-with (->col-expr 'str-starts-with x) prefix))
(define (str-ends-with x suffix)
  (expr-str-ends-with (->col-expr 'str-ends-with x) suffix))

;; strip whitespace (no chars) or the given chars from both ends; strip a fixed
;; prefix / suffix.
(define (str-strip-chars x [chars #f])
  (expr-str-strip-chars (->col-expr 'str-strip-chars x) chars))
(define (str-strip-prefix x prefix)
  (expr-str-strip-prefix (->col-expr 'str-strip-prefix x) prefix))
(define (str-strip-suffix x suffix)
  (expr-str-strip-suffix (->col-expr 'str-strip-suffix x) suffix))

;; regex replace (first / all matches); `#:literal #t` treats pattern as plain
;; text.  `str-extract` returns the `#:group-index` capture group (default 1).
(define (str-replace x pat value #:literal [literal #f])
  (expr-str-replace (->col-expr 'str-replace x) pat value #:literal literal))
(define (str-replace-all x pat value #:literal [literal #f])
  (expr-str-replace-all (->col-expr 'str-replace-all x) pat value #:literal literal))
(define (str-extract x pat #:group-index [group-index 1])
  (expr-str-extract (->col-expr 'str-extract x) pat #:group-index group-index))

;; byte / char length; substring by (offset length); first / last n chars.
;; These are the .str-namespaced analogues of the row-level slice / head / tail.
(define-expr-unop str-len-bytes 'str-len-bytes expr-str-len-bytes)
(define-expr-unop str-len-chars 'str-len-chars expr-str-len-chars)
(define (str-slice x offset length)
  (expr-str-slice (->col-expr 'str-slice x) offset length))
(define (str-head x n) (expr-str-head (->col-expr 'str-head x) n))
(define (str-tail x n) (expr-str-tail (->col-expr 'str-tail x) n))

;; find a regex (`#:strict` raises on invalid pattern) / a literal substring;
;; count matches (`#:literal #t` counts a plain substring instead of a regex).
(define (str-find x pat #:strict [strict #t])
  (expr-str-find (->col-expr 'str-find x) pat #:strict strict))
(define (str-find-literal x pat)
  (expr-str-find-literal (->col-expr 'str-find-literal x) pat))
(define (str-count-matches x pat #:literal [literal #f])
  (expr-str-count-matches (->col-expr 'str-count-matches x) pat #:literal literal))

;; parse strings to Date / Datetime / Time.  #:strict #f turns unparseable
;; values into null instead of raising; #:format is a chrono strptime pattern
;; (inferred when omitted); #:exact #f allows surrounding text;
;; str-to-datetime also takes #:unit ('milliseconds | 'microseconds | 'nanoseconds).
(define (str-to-date x #:format [format #f] #:strict [strict #t]
                     #:exact [exact #t] #:cache [cache #t])
  (expr-str-to-date (->col-expr 'str-to-date x)
                    #:format format #:strict strict #:exact exact #:cache cache))
(define (str-to-datetime x #:format [format #f] #:unit [unit 'microseconds]
                         #:strict [strict #t] #:exact [exact #t] #:cache [cache #t])
  (expr-str-to-datetime (->col-expr 'str-to-datetime x)
                        #:format format #:unit unit
                        #:strict strict #:exact exact #:cache cache))
(define (str-to-time x #:format [format #f] #:strict [strict #t]
                     #:exact [exact #t] #:cache [cache #t])
  (expr-str-to-time (->col-expr 'str-to-time x)
                    #:format format #:strict strict #:exact exact #:cache cache))

(module+ test
  (require rackunit (only-in threading ~>)
           (only-in gregor date datetime)
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
  (check-equal? (ref (ref out3 #:columns "count_a") 2) 3)
  ;; string-to-temporal: parse Date/Datetime/Time; #:strict #f -> null on failure
  (define p
    (dataframe (list (series '("2024-01-02" "not-a-date" "2024-05-09 extra") #:name "date_s")
                     (series '("2024-01-02 03:04:05" "bad" "x") #:name "dt_s")
                     (series '("03:04:05.123456789" "bad" "x") #:name "time_s"))))
  (define out4
    (~> p (with-columns
            (alias (str-to-date "date_s" #:strict #f) "d_infer")
            (alias (str-to-date "date_s" #:format "%Y-%m-%d" #:strict #f #:exact #f) "d_embed")
            (alias (str-to-datetime "dt_s" #:format "%Y-%m-%d %H:%M:%S"
                                    #:unit 'milliseconds #:strict #f) "dt")
            (alias (str-to-time "time_s" #:format "%H:%M:%S%.f" #:strict #f) "tm"))))
  (check-equal? (ref (ref out4 #:columns "d_infer") 0) (date 2024 1 2))
  (check-equal? (ref (ref out4 #:columns "d_infer") 1) polars-null)
  (check-equal? (ref (ref out4 #:columns "d_embed") 2) (date 2024 5 9)) ; #:exact #f
  (check-equal? (ref (ref out4 #:columns "dt") 0) (datetime 2024 1 2 3 4 5))
  (check-equal? (ref (ref out4 #:columns "dt") 1) polars-null)
  (check-not-eq? (ref (ref out4 #:columns "tm") 0) polars-null)
  (check-equal? (ref (ref out4 #:columns "tm") 1) polars-null))
