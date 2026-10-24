#lang racket/base

;; Polars' cumulative / sequential Expr ops: cum-sum / cum-prod / cum-min /
;; cum-max / cum-count (each #:reverse), shift (#:n, #:fill-value), and diff
;; (#:n, #:null-behavior).  Each takes an Expr or a bare column-name string
;; (auto-lifted via col).

(require (only-in racket/contract/base ->* any/c contract-out)
         (only-in polars/private/c-integer int64/c)
         polars/private/foreign
         polars/private/expr
         polars/private/generic/expr-util)

(provide cum-sum cum-prod cum-min cum-max cum-count
         (contract-out
          [shift (->* (col-expr/c) (#:n int64/c #:fill-value any/c) Expr-ptr?)]
          [diff (->* (col-expr/c) (#:n int64/c #:null-behavior null-behavior/c)
                     Expr-ptr?)]))

(define (cum-sum x #:reverse [reverse #f])
  (expr-cum-sum (->col-expr 'cum-sum x) #:reverse reverse))
(define (cum-prod x #:reverse [reverse #f])
  (expr-cum-prod (->col-expr 'cum-prod x) #:reverse reverse))
(define (cum-min x #:reverse [reverse #f])
  (expr-cum-min (->col-expr 'cum-min x) #:reverse reverse))
(define (cum-max x #:reverse [reverse #f])
  (expr-cum-max (->col-expr 'cum-max x) #:reverse reverse))
(define (cum-count x #:reverse [reverse #f])
  (expr-cum-count (->col-expr 'cum-count x) #:reverse reverse))

;; shift rows by #:n (positive = later, negative = earlier); #:fill-value fills
;; the vacated slots instead of null.  diff takes successive differences over a
;; lag of #:n, with #:null-behavior 'ignore | 'drop.
(define (shift x #:n [n 1] #:fill-value [fill-value #f])
  (expr-shift (->col-expr 'shift x) #:n n
              #:fill-value (and fill-value (->expr/who 'shift fill-value))))
(define (diff x #:n [n 1] #:null-behavior [null-behavior 'ignore])
  (expr-diff (->col-expr 'diff x) #:n n #:null-behavior null-behavior))

(module+ test
  (require rackunit (only-in threading ~>)
           (only-in polars/private/bulk series->list)
           polars/private/generic/core
           polars/private/generic/reductions   ; alias
           polars/private/generic/reshape)     ; with-columns
  (define df (dataframe (list (series '(1 2 3 4 5) #:name "x" #:dtype 'i64))))
  (define out
    (~> df (with-columns
             (alias (cum-sum "x") "cs")
             (alias (cum-sum "x" #:reverse #t) "csr")
             (alias (cum-prod "x") "cp")
             (alias (cum-min "x") "cmin")
             (alias (cum-max "x") "cmax")
             (alias (cum-count "x") "cc")
             (alias (shift "x" #:n 1) "s1")
             (alias (shift "x" #:n -1) "sm1")
             (alias (shift "x" #:n 1 #:fill-value 0) "s1f")
             (alias (diff "x" #:n 1) "d1"))))
  (define (c name i) (ref (ref out #:columns name) i))
  ;; x = (1 2 3 4 5)
  (check-equal? (c "cs" 4) 15)        ; 1+2+3+4+5
  (check-equal? (c "csr" 0) 15)       ; reversed cumulative sum
  (check-equal? (c "cp" 4) 120)       ; 5!
  (check-equal? (c "cmin" 4) 1)
  (check-equal? (c "cmax" 4) 5)
  (check-equal? (c "cc" 4) 5)
  (check-equal? (c "s1" 0) polars-null)   ; shifted down -> leading null
  (check-equal? (c "s1" 1) 1)
  (check-equal? (c "sm1" 4) polars-null)  ; shifted up -> trailing null
  (check-equal? (c "s1f" 0) 0)            ; vacated slot filled with 0
  (check-equal? (c "d1" 0) polars-null)
  (check-equal? (c "d1" 1) 1)             ; 2-1
  (define (columns d)
    (map (lambda (name) (series->list (ref d name))) (column-names d)))
  (define steps (dataframe (list (series '(1 3 6 10) #:name "v"))))
  (check-equal? (columns (select steps
                                 (alias (shift "v") "down")
                                 (alias (shift "v" #:n -1 #:fill-value 0) "up")
                                 (alias (diff "v") "change")))
                (list (list polars-null 1 3 6) '(3 6 10 0) (list polars-null 2 3 4)))
  (check-equal? (columns (select steps (diff "v" #:null-behavior 'drop))) '((2 3 4))))

(module+ test
  (require (only-in polars/private/test-helpers contract-violation-of)
           (prefix-in contracted: (submod "..")))
  (check-exn (contract-violation-of 'shift) (lambda () (contracted:shift "v" #:n (expt 2 63)))))
