#lang racket/base

;; Operators that shadow racket/base, all with the same three-way dispatch
;; (Expr -> build an Expr; series -> eager elementwise; else -> racket/base):
;;   * comparison  > < >= <= = !=
;;   * arithmetic  + - * /     (defined p+/p-/p*/p/, exposed via rename-out)
;;   * logical     and or not xor (and/or are short-circuit macros: p-and/p-or)
;;   * conditional when / then / otherwise (Polars pl.when().then().otherwise())
;; The shadowing public names live behind p* spellings so this module's own
;; arithmetic/boolean/control-flow stays racket/base; the aggregator renames
;; them on the way out.

(require (prefix-in base: racket/base)
         (only-in racket/list make-list)
         polars/private/foreign
         polars/private/expr
         polars/private/generic/core
         polars/private/generic/dtype)

(provide (all-defined-out))

;; A constant series of `dt`, length `n`, every slot = `value`.
(define (const-series dt n value)
  (define ctor (dtype->constructor dt #f))
  (wrap-series (ctor "" (coerce-elements dt (make-list n value)))))

;; The other operand of a series op, as a series matching `s`.
(define (cmp-other s other)
  (if (series? other) other (const-series (series-dtype s) (series-len s) other)))

;; --- comparison operators ---------------------------------------------------
(define-syntax-rule (define-cmp name expr-op series-op series-op-reflected base-op)
  (define (name . args)
    (cond
      [(andmap base:number? args) (apply base-op args)]
      [(base:= (length args) 2)
       (let ([a (base:car args)] [b (base:cadr args)])
         (cond
           [(or (Expr-ptr? a) (Expr-ptr? b)) (expr-op a b)]
           [(series? a) (wrap-series (series-op a (cmp-other a b)))]
           [(series? b) (wrap-series (series-op-reflected b (cmp-other b a)))]
           [else (apply base-op args)]))]
      [else (apply base-op args)])))

;; `!=` has no racket/base spelling; fall back to (not (= …)).
(define (base:!= . args) (base:not (apply base:= args)))

(define-cmp >  expr-gt series-gt series-lt base:>)
(define-cmp <  expr-lt series-lt series-gt base:<)
(define-cmp >= expr-ge series-ge series-le base:>=)
(define-cmp <= expr-le series-le series-ge base:<=)
(define-cmp =  expr-eq series-eq series-eq base:=)
(define-cmp != expr-ne series-ne series-ne base:!=)

;; --- arithmetic operators ---------------------------------------------------
(define (binary-arith expr-op series-op base-op a b)
  (cond [(or (Expr-ptr? a) (Expr-ptr? b)) (expr-op a b)]
        [(series? a) (wrap-series (series-op a (cmp-other a b)))]
        [(series? b) (wrap-series (series-op (cmp-other b a) b))]
        [else (base-op a b)]))

(define-syntax-rule (define-arith name expr-op series-op base-op)
  (define (name . args)
    (cond
      [(andmap base:number? args) (apply base-op args)]   ; numeric fast path
      [(null? args) (base-op)]
      [(null? (cdr args))
       (let ([a (car args)])
         (if (or (Expr-ptr? a) (series? a)) a (base-op a)))]
      [else (foldl (lambda (b acc) (binary-arith expr-op series-op base-op acc b))
                   (car args) (cdr args))])))

(define-arith p+ expr-add series-add base:+)
(define-arith p- expr-sub series-sub base:-)
(define-arith p* expr-mul series-mul base:*)
(define-arith p/ expr-div series-div base:/)

;; --- boolean / logical operators --------------------------------------------
;; and / or stay short-circuit macros; only an Expr/series operand routes into
;; the eager combiners.  not / xor are strict, so plain functions.

(define (combine-and a b)
  (if (or (Expr-ptr? a) (Expr-ptr? b)) (expr-and a b) (wrap-series (series-and a b))))
(define (combine-or a b)
  (if (or (Expr-ptr? a) (Expr-ptr? b)) (expr-or a b)  (wrap-series (series-or a b))))

(define-syntax p-and
  (syntax-rules ()
    [(_)         #t]
    [(_ e)       e]
    [(_ e0 e ...) (let ([v e0])
                    (if (or (Expr-ptr? v) (series? v))
                        (combine-and v (p-and e ...))   ; predicate build (eager)
                        (if v (p-and e ...) v)))]))      ; booleans: racket `and`

(define-syntax p-or
  (syntax-rules ()
    [(_)         #f]
    [(_ e)       e]
    [(_ e0 e ...) (let ([v e0])
                    (if (or (Expr-ptr? v) (series? v))
                        (combine-or v (p-or e ...))
                        (if v v (p-or e ...))))]))        ; booleans: racket `or`

(define (p-not x)
  (cond [(Expr-ptr? x) (expr-not x)]
        [(series? x)   (wrap-series (series-not x))]
        [else          (base:not x)]))

(define (p-xor a b)
  (cond [(or (Expr-ptr? a) (Expr-ptr? b)) (expr-xor a b)]
        [(or (series? a) (series? b))     (wrap-series (series-xor a b))]
        [else (and (or a b) (not (and a b)))]))   ; boolean xor

;; --- when / then / otherwise ------------------------------------------------
;; Data-first builder that threads: (~> (when (> (col "x") 0)) (then 10) (otherwise 0)).
;; `when` (one arg) starts the builder; two-or-more keep racket/base `when`.

(struct when-pending (cond))         ; produced by (when cond)
(struct when-clause (cond value))    ; produced by (then ... value)

(define (then wp value)
  (unless (when-pending? wp)
    (error 'then "`then` must follow `when`, got ~v" wp))
  (when-clause (when-pending-cond wp) value))

(define (otherwise wc default)
  (unless (when-clause? wc)
    (error 'otherwise "`otherwise` must follow `then`, got ~v" wc))
  (expr-when (list (list (when-clause-cond wc) (when-clause-value wc)))
             #:otherwise default))

(define-syntax p-when
  (syntax-rules ()
    [(_ c) (when-pending c)]                          ; one arg: start the builder
    [(_ test body ...) (base:when test body ...)]))   ; else: racket control-flow

(module+ test
  ;; pure operator behaviour only (Expr-ptr? / series via ref / numbers); the
  ;; filter/select integration is exercised in reshape's tests, to avoid an
  ;; operators<->reshape test cycle.
  (require rackunit (only-in threading ~>)
           polars/private/generic/core
           polars/private/generic/test-fixtures)

  ;; comparison operators dispatch three ways
  (check-pred Expr-ptr? (> (col "value") 15))
  (check-pred Expr-ptr? (< 15 (col "value")))
  (check-pred Expr-ptr? (= (col "group") "a"))
  (define mask (> v64 15))
  (check-pred series? mask)
  (check-equal? (dtype mask) 'boolean)
  (check-equal? (for/list ([i (in-range (len mask))]) (ref mask i)) '(#f #t #f #t #t))
  (check-equal? (for/list ([i (in-range 5)]) (ref (< 15 v64) i)) '(#f #t #f #t #t))
  (check-equal? (> 3 2) #t)
  (check-equal? (< 1 2 3) #t)
  (check-equal? (= 2 2) #t)
  (check-equal? (!= 2 3) #t)
  (check-equal? (!= 2 2) #f)

  ;; boolean / logical operators (p-and / p-or / p-not / p-xor)
  (check-equal? (p-and #t #f) #f)
  (check-equal? (p-and 1 2 3) 3)
  (check-equal? (p-and) #t)
  (check-equal? (p-or #f 5) 5)
  (check-equal? (p-or #f #f) #f)
  (check-equal? (p-or) #f)
  (check-not-exn (lambda () (p-and #f (error "boom"))))
  (check-equal? (p-or 1 (error "boom")) 1)
  (check-equal? (p-and #t #f (error "boom")) #f)
  (define ran (box #f))
  (check-equal? (p-and #f (begin (set-box! ran #t) #t)) #f)
  (check-false (unbox ran))
  (check-true (p-and #t (begin (set-box! ran #t) #t)))
  (check-true (unbox ran))
  (check-equal? (p-not #f) #t)
  (check-equal? (p-not 5) #f)
  (check-equal? (p-xor #t #f) #t)
  (check-equal? (p-xor #t #t) #f)
  (check-equal? (p-xor #f #f) #f)
  ;; Expr predicates build Exprs (their filter behaviour is in reshape's tests)
  (check-pred Expr-ptr? (p-and (>= (col "value") 10) (<= (col "value") 25)))
  (check-pred Expr-ptr? (p-or (= (col "group") "a") (= (col "group") "c")))
  (check-pred Expr-ptr? (p-not (= (col "group") "a")))
  ;; series masks observed through produced element values
  (define m1 (> v64 15))
  (define m2 (< v64 20))
  (define (mask->list m) (for/list ([i (in-range (len m))]) (ref m i)))
  (check-equal? (mask->list (p-and m1 m2)) '(#f #f #f #f #t))
  (check-equal? (mask->list (p-or  m1 m2)) '(#t #t #t #t #t))
  (check-equal? (mask->list (p-not m1))    '(#t #f #t #f #f))
  (check-equal? (mask->list (p-xor m1 m2)) '(#t #t #t #t #f))

  ;; arithmetic operators (p+ / p- / p* / p/)
  (check-equal? (p+ 1 2 3) 6)
  (check-equal? (p- 10 3 2) 5)
  (check-equal? (p* 2 3 4) 24)
  (check-equal? (p/ 12 3) 4)
  (check-pred Expr-ptr? (p+ (col "score") 1))
  (check-equal? (for/list ([i (in-range 5)]) (ref (p+ v64 100) i)) '(110 125 107 130 118))
  (check-equal? (for/list ([i (in-range 5)]) (ref (p* v64 2) i)) '(20 50 14 60 36))

  ;; when / then / otherwise build an Expr; control-flow path stays racket `when`
  (check-pred Expr-ptr? (~> (p-when (> (col "score") 15)) (then 10) (otherwise 0)))
  (check-equal? (let ([acc 0]) (p-when #t (set! acc 1)) acc) 1)
  (check-equal? (let ([acc 0]) (p-when #f (set! acc 1)) acc) 0))
