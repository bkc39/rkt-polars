#lang racket/base

;; Polars' cumulative / sequential Expr ops: cum-sum / cum-prod / cum-min /
;; cum-max / cum-count (each #:reverse), shift (#:n, #:fill-value), and diff
;; (#:n, #:null-behavior).  Each takes an Expr or a bare column-name string
;; (auto-lifted via col).

(require polars/private/foreign
         polars/private/expr
         polars/private/generic/expr-util)

(provide cum-sum cum-prod cum-min cum-max cum-count shift diff)

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
  (expr-shift (->col-expr 'shift x) #:n n #:fill-value fill-value))
(define (diff x #:n [n 1] #:null-behavior [null-behavior 'ignore])
  (expr-diff (->col-expr 'diff x) #:n n #:null-behavior null-behavior))

(module+ test
  (require rackunit (only-in threading ~>)
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
  (check-equal? (c "d1" 1) 1))            ; 2-1