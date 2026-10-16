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
         (only-in racket/match match match* match-define)
         polars/private/foreign
         polars/private/expr
         polars/private/generic/core
         polars/private/generic/dtype
         (only-in polars/private/resource with-release)
         (only-in polars/private/series series-repeat-temporal)
         (only-in polars/private/temporal temporal-value-dtype)
         syntax/parse/define
         (for-syntax racket/base syntax/parse))

(provide (all-defined-out))

;; A constant series of `dt`, length `n`, every slot = `value`.
(define (const-series dt n value)
  (wrap-series
   (if (temporal-dtype? dt)
       (series-repeat-temporal 'series "" value n dt)
       ((dtype->constructor dt #f) "" (coerce-elements dt (make-list n value))))))

;; The other operand of a series op, as a series matching `s`; a gregor value
;; keeps the dtype `lit` gives it, as the expression path does.
(define (cmp-other who s other)
  (define o
    (cond
      [(series? other) other]
      [(temporal-value-dtype other) => (lambda (dt) (const-series dt (series-len s) other))]
      [else (const-series (series-dtype s) (series-len s) other)]))
  (match* ((series-dtype s) (series-dtype o))
    [((list 'datetime _ zone) (list 'datetime _ other-zone))
     #:when (not (equal? zone other-zone))
     (raise-arguments-error who "datetimes in different time zones"
                            "series dtype" (series-dtype s) "other dtype" (series-dtype o))]
    [(_ _) o]))

(define (failure-cause e)
  (define message (exn-message e))
  (match (regexp-match #rx"^[^:]*: (?:failed to collect the query: )?(.*?)(?:\n\nResolved plan.*)?$"
                       message)
    [(list _ cause) cause]
    [#f message]))

(define (raise-cause who e #:contract? [contract? (exn:fail:contract? e)])
  (define make-exn (if contract? exn:fail:contract exn:fail))
  (raise (make-exn (format "~a: ~a" who (failure-cause e)) (exn-continuation-marks e))))

;; A 'null series with a plain operand runs the expression form, the operand
;; read by `lit`, which has no polars-null literal; #f otherwise.
(define (null-series-op who expr-op a b)
  (define (plain? v) (not (or (series? v) (polars-null? v))))
  (define (literal v)
    (with-handlers ([exn:fail? (lambda (e) (raise-cause who e #:contract? #t))])
      (lit v)))
  (define (run s build)
    (with-handlers ([exn:fail? (lambda (e) (raise-cause who e))])
      (series-through-expr s build)))
  (cond
    [(and (null-series? a) (plain? b))
     (define v (literal b))
     (run a (lambda (e) (expr-op e v)))]
    [(and (null-series? b) (plain? a))
     (define v (literal a))
     (run b (lambda (e) (expr-op v e)))]
    [else #f]))

;; --- comparison operators ---------------------------------------------------
(define-syntax-parse-rule (define-cmp name:id expr-op:expr series-op:expr
                                      series-op-reflected:expr base-op:expr)
  (define (name . args)
    (cond
      [(andmap base:number? args) (apply base-op args)]
      [(base:= (length args) 2)
       (let ([a (base:car args)] [b (base:cadr args)])
         (cond
           [(or (Expr-ptr? a) (Expr-ptr? b)) (expr-op a b)]
           [(null-series-op 'name expr-op a b) => values]
           [(series? a) (wrap-series (series-op a (cmp-other 'name a b)))]
           [(series? b) (wrap-series (series-op-reflected b (cmp-other 'name b a)))]
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
(define (binary-arith who expr-op series-op base-op a b)
  (cond [(or (Expr-ptr? a) (Expr-ptr? b)) (expr-op a b)]
        [(null-series-op who expr-op a b) => values]
        [(series? a) (wrap-series (series-op a (cmp-other who a b)))]
        [(series? b) (wrap-series (series-op (cmp-other who b a) b))]
        [else (base-op a b)]))

(define (series-through-expr s build)
  (define name (series-name s))
  (with-release ([frame (dataframe-new (list s)) dataframe-drop]
                 [out (dataframe-select-exprs frame (list (expr-alias (build (expr-all)) name)))
                      dataframe-drop])
    (wrap-series (dataframe-column out name))))

(define (series-negate s)
  (match (series-dtype s)
    ['null s]
    [(or 'int8 'int16 'int32 'int64 'float32 'float64 (list 'duration _) (list 'decimal _ _))
     (series-through-expr s expr-neg)]
    [dt (raise-arguments-error '- "cannot negate a series of this dtype" "dtype" dt)]))

(define (expr-reciprocal e)
  (define divided (p/ 1 e))
  (match (expr-meta-output-name/raw e)
    [#f (expr-name-keep divided)]
    [name (expr-alias divided name)]))

(define (series-reciprocal s)
  (match (series-dtype s)
    ['null s]
    [(or (? numeric-dtype?) (list 'decimal _ _)) (series-through-expr s expr-reciprocal)]
    [dt (raise-arguments-error '/ "cannot take the reciprocal of a series of this dtype"
                               "dtype" dt)]))

(begin-for-syntax
  (define-splicing-syntax-class (one-argument who base-op)
    #:description "a one-argument case (#:unary expr-op series-op, or #:binary-only)"
    #:attributes ([clause 1])
    (pattern (~seq #:unary expr-op:expr series-op:expr)
             #:with (clause ...) #`([(list (? Expr-ptr? a)) (expr-op a)]
                                    [(list (? series? a)) (series-op a)]
                                    [(list a) (#,base-op a)]))
    (pattern (~seq #:binary-only)
             #:with (clause ...) #`([(list) (raise-arity-error '#,who (arity-at-least 2))]
                                    [(list a) (raise-arity-error '#,who (arity-at-least 2) a)]))
    (pattern (~seq)
             #:with (clause ...) #`([(list (and a (or (? Expr-ptr?) (? series?)))) a]
                                    [(list a) (#,base-op a)]))))

(define-syntax-parse-rule (define-arith name:id who:id expr-op:expr series-op:expr base-op:expr
                           (~var one (one-argument #'who #'base-op)))
  (define (name . args)
    (match args
      one.clause ...
      [_ #:when (andmap base:number? args) (apply base-op args)]
      [(cons a more) (foldl (lambda (b acc) (binary-arith 'who expr-op series-op base-op acc b))
                            a more)])))

(define-arith p+ + expr-add series-add base:+)
(define-arith p- - expr-sub series-sub base:- #:unary expr-neg series-negate)
(define-arith p* * expr-mul series-mul base:*)
(define-arith p/ / expr-div series-div base:/ #:unary expr-reciprocal series-reciprocal)

;; `mod` does not collide with racket/base (which spells it `modulo`), so it
;; is provided under its own name rather than via the rename-out dance.  Plain
;; numbers fall back to racket/base `modulo`, folded left.
(define (base:mod a b . more)
  (foldl (lambda (m acc) (base:modulo acc m)) (base:modulo a b) more))

(define-arith mod mod expr-mod series-mod base:mod #:binary-only)

;; --- boolean / logical operators --------------------------------------------
;; and / or stay short-circuit macros; only an Expr/series operand routes into
;; the eager combiners.  not / xor are strict, so plain functions.

(define (combine-and a b)
  (if (or (Expr-ptr? a) (Expr-ptr? b)) (expr-and a b) (wrap-series (series-and a b))))
(define (combine-or a b)
  (if (or (Expr-ptr? a) (Expr-ptr? b)) (expr-or a b)  (wrap-series (series-or a b))))

(define-syntax-parser p-and
  [(_) #'#t]
  [(_ e:expr) #'e]
  [(_ e0:expr e:expr ...+)
   #'(let ([v e0])
       (if (or (Expr-ptr? v) (series? v))
           (combine-and v (p-and e ...))   ; predicate build (eager)
           (if v (p-and e ...) v)))])      ; booleans: racket `and`

(define-syntax-parser p-or
  [(_) #'#f]
  [(_ e:expr) #'e]
  [(_ e0:expr e:expr ...+)
   #'(let ([v e0])
       (if (or (Expr-ptr? v) (series? v))
           (combine-or v (p-or e ...))
           (if v v (p-or e ...))))])       ; booleans: racket `or`

(define (p-not x)
  (cond [(Expr-ptr? x) (expr-not x)]
        [(series? x)   (wrap-series (series-not x))]
        [else          (base:not x)]))

(define (p-xor a b)
  (cond [(or (Expr-ptr? a) (Expr-ptr? b)) (expr-xor a b)]
        [(or (series? a) (series? b))     (wrap-series (series-xor a b))]
        [else (and (or a b) (not (and a b)))]))   ; boolean xor

;; --- when / then / else-when / otherwise ------------------------------------
;; Data-first builder that threads, mirroring Polars'
;; when().then()(.when().then())*.otherwise():
;;   (~> (when (> (col "x") 0)) (then 10) (otherwise 0))
;;   (~> (when (< (col "x") 0)) (then -1)
;;       (else-when (= (col "x") 0)) (then 0)
;;       (otherwise 1))
;; `when` (one arg) starts the builder; two-or-more keep racket/base `when`.

;; when-pending: clauses accumulated so far + the open condition awaiting `then`.
;; when-acc:     clauses accumulated so far, awaiting `else-when` or `otherwise`.
(struct when-pending (clauses cond))   ; produced by (when cond) / (else-when cond)
(struct when-acc (clauses))            ; produced by (then ... value)

(define (then wp value)
  (unless (when-pending? wp)
    (error 'then "`then` must follow `when` / `else-when`, got ~v" wp))
  (when-acc (append (when-pending-clauses wp)
                    (list (list (when-pending-cond wp) value)))))

(define (else-when wa cond)
  (unless (when-acc? wa)
    (error 'else-when "`else-when` must follow `then`, got ~v" wa))
  (when-pending (when-acc-clauses wa) cond))

(define (otherwise wa default)
  (unless (when-acc? wa)
    (error 'otherwise "`otherwise` must follow `then`, got ~v" wa))
  (expr-when (when-acc-clauses wa) #:otherwise default))

(define-syntax-parser p-when
  [(_ c:expr) #'(when-pending '() c)]                  ; one arg: start the builder
  [(_ test:expr body:expr ...) #'(base:when test body ...)])  ; else: racket control-flow

(module+ test
  ;; pure operator behaviour only (Expr-ptr? / series via ref / numbers); the
  ;; filter/select integration is exercised in reshape's tests, to avoid an
  ;; operators<->reshape test cycle.
  (require rackunit
           (only-in ffi/unsafe/atomic call-as-atomic)
           (only-in gregor date)
           (only-in gregor/period hours minutes)
           (only-in polars/private/bulk series->list)
           polars/private/generic/core
           polars/private/generic/test-fixtures
           (only-in threading ~>))

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
  (check-equal? (for/list ([i (in-range 5)]) (ref (mod v64 3) i)) '(1 1 1 0 0))
  (check-equal? (mod 10 3) 1)
  (check-equal? (mod 10 4 3) 2)
  (check-equal? (mod -7 4 3) 1)
  (check-pred Expr-ptr? (mod (col "value") 2))

  (check-equal? (list (p- 5) (p/ 4) (p+ 3) (p* 3)) '(-5 1/4 3 3))
  (for ([op (list p- p/)])
    (define s (series '(1.0 2.0 4.0) #:name "v"))
    (check-equal? (call-as-atomic
                   (lambda ()
                     (define before (dataframe-drop-count))
                     (op s)
                     (base:- (dataframe-drop-count) before)))
                  2))
  (for ([case (list (list (p- (col "value")) "col(\"value\").negate()")
                    (list (p/ (col "value"))
                          "[(dyn int: 1) rust_div (col(\"value\"))].alias(\"value\")")
                    (list (p+ (col "value")) "col(\"value\")")
                    (list (p* (col "value")) "col(\"value\")")
                    (list (p- (col "delay")) "col(\"delay\").negate()")
                    (list (p/ (col "speed"))
                          "[(dyn int: 1) rust_div (col(\"speed\"))].alias(\"speed\")"))])
    (match-define (list e printed) case)
    (check-equal? (format "~a" e) printed))
  (define unary-frame
    (dataframe-select-exprs ops-df
                            (list (expr-alias (p- (col "value")) "neg")
                                  (expr-alias (p/ (col "value")) "recip")
                                  (expr-alias (p/ (col "cost")) "cost-recip")
                                  (expr-alias (p+ (col "value")) "same"))))
  (define (unary-column name) (series->list (dataframe-column unary-frame name)))
  (check-equal? (unary-column "neg") '(-10 -25 -7 -30 -18))
  (check-equal? (unary-column "recip") '(0 0 0 0 0))
  (check-equal? (unary-column "cost-recip")
                (map (lambda (x) (base:/ 1 x)) '(1.2 2.4 0.5 3.1 1.8)))
  (check-equal? (unary-column "same") '(10 25 7 30 18))
  (define reciprocals (dataframe-select-exprs ops-df (list (p/ (col "value")) (p/ (col "cost")))))
  (check-equal? (dataframe-column-names reciprocals) '("value" "cost"))
  (check-equal? (series->list (dataframe-column reciprocals "cost"))
                (map (lambda (x) (base:/ 1 x)) '(1.2 2.4 0.5 3.1 1.8)))
  (check-equal? (dataframe-column-names (dataframe-with-columns ops-df (list (p/ (col "cost")))))
                '("group" "value" "cost"))
  (check-equal? (expr-meta-output-name (p/ (expr-alias (col "cost") "c"))) "c")
  (define c-frame (dataframe (list (series '(1.0 2.0) #:name "c1") (series '(4.0 8.0) #:name "c2")
                                   (series '(1 2) #:name "n"))))
  (define (reciprocal-names . exprs)
    (dataframe-column-names (dataframe-select-exprs c-frame exprs)))
  (check-equal? (reciprocal-names (p/ (col #rx"^c"))) '("c1" "c2"))
  (check-equal? (reciprocal-names (p/ (col #rx"^c1$"))) '("c1"))
  (check-equal? (reciprocal-names (p/ (col "*"))) '("c1" "c2" "n"))
  (check-equal? (reciprocal-names (p/ (col 'float64))) '("c1" "c2"))
  (check-equal? (reciprocal-names (p/ (p/ (col #rx"^c")))) '("c1" "c2"))
  (check-equal? (reciprocal-names (p/ (lit 2))) '("literal"))
  (check-equal? (reciprocal-names (p/ (expr-sum (col "c2")))) '("c2"))
  (check-equal? (~> (dataframe-select-exprs c-frame (list (p/ (col #rx"^c"))))
                    (dataframe-column "c2")
                    series->list)
                '(0.25 0.125))
  (check-equal? (format "~a" (p/ (col #rx"^c1$")))
                "[(dyn int: 1) rust_div (cs.matches(\"^(?s).*(?:^c1$).*$\"))].name.keep()")
  (define negated (p- withnull))
  (check-pred series? negated)
  (check-equal? (dtype negated) 'int32)
  (check-equal? (series->list negated) (list -10 polars-null -30))
  (check-equal? (series-name (p- ints)) "ints")
  (check-equal? (series->list (p- floats)) '(-1.5 -2.0 -4.25 -8.0))
  (check-equal? (series->list (p- (series (list (hours 1) (minutes -30)))))
                (series->list (series (list (hours -1) (minutes 30)))))
  (check-equal? (series->list (p- prices)) (list -5/4 -4/5 polars-null -12))
  (check-equal? (series->list (p/ prices)) (list 4/5 5/4 polars-null 2/25))
  (check-equal? (series-name (p/ prices)) "price")
  (define pattern-named (series '(1 2) #:name "^a$"))
  (check-equal? (series->list (p- pattern-named)) '(-1 -2))
  (check-equal? (series-name (p- pattern-named)) "^a$")
  (check-equal? (series->list (p/ pattern-named)) '(1 0))
  (check-equal? (series-name (p/ pattern-named)) "^a$")
  (check-equal? (series->list (p- (series '(1 -2 3)))) '(-1 2 -3))
  (check-equal? (series-name (p- (series '(1 -2 3) #:name "v"))) "v")
  (define replaced
    (dataframe-with-columns (dataframe (list (series '(10 25 7) #:name "v")))
                            (list (p/ (col "v")))))
  (check-equal? (dataframe-column-names replaced) '("v"))
  (check-equal? (series->list (dataframe-column replaced "v")) '(0 0 0))
  (check-exn #rx"^mod: arity mismatch" (lambda () (mod (col "v"))))
  (check-equal? (~> (dataframe (list (series '(10 25 7) #:name "v")))
                    (dataframe-select-exprs (list (expr-alias (p- (col "v")) "neg")))
                    (dataframe-column "neg")
                    series->list)
                '(-10 -25 -7))
  (check-equal? (series->list (p/ (series '(1.0 2.0 4.0)))) '(1.0 0.5 0.25))
  (check-equal? (series->list (p/ (series '(1 2 4)))) '(1 0 0))
  (check-equal? (series->list (p/ (series '(1 -1 2 -2 0)))) (list 1 -1 0 -1 polars-null))
  (check-equal? (series->list (p/ (series '(-7 7 1)) (series '(2 2 0)))) (list -4 3 polars-null))
  (check-equal? (series->list (p/ ints)) '(1 0 0 0))
  (check-equal? (dtype (p/ ints)) 'int32)
  (check-equal? (series-name (p/ floats)) "floats")
  (check-equal? (series->list (p/ (series '(1 2) #:dtype 'u8))) '(1 0))
  (define nulls
    (wrap-series (series-cast (series (list polars-null polars-null) #:name "n") 'null)))
  (for ([op (list p- p/)])
    (define result (op nulls))
    (check-equal? (list (dtype result) (len result) (series-name result)) '(null 2 "n")))
  (for ([case (list (list (p+ nulls 1) 'int32) (list (p- 1 nulls) 'int32) (list (p/ nulls 2) 'int32)
                    (list (p* 2.5 nulls) 'float64) (list (p+ nulls 2.5) 'float64)
                    (list (p+ nulls "a") 'string) (list (p+ nulls 'a) 'string)
                    (list (= nulls 'a) 'boolean) (list (= nulls "a") 'boolean)
                    (list (= nulls 1) 'boolean) (list (> 1 nulls) 'boolean)
                    (list (p+ nulls polars-null) 'null))])
    (match-define (list result expected) case)
    (check-equal? (list (dtype result) (series-name result) (series->list result))
                  (list expected "n" (list polars-null polars-null))))
  (define null-frame (dataframe (list nulls)))
  (define (outcome thunk)
    (with-handlers ([exn:fail? (lambda (e) (list 'raised (failure-cause e)))])
      (define result (thunk))
      (list (dtype result) (series->list result))))
  (define (selected e)
    (wrap-series (dataframe-column (dataframe-select-exprs null-frame (list (expr-alias e "n")))
                                   "n")))
  (for* ([op (list p+ p- p* p/ mod = != > < >= <=)]
         [value (list 1 2.5 "a" 'a #t (datetime 2024 1 1) (date 2024 1 1) #\a (expt 2 63))])
    (check-equal? (outcome (lambda () (op nulls value)))
                  (outcome (lambda () (selected (op (col "n") value))))
                  (format "~a ~v" (object-name op) value))
    (check-equal? (outcome (lambda () (op value nulls)))
                  (outcome (lambda () (selected (op value (col "n")))))
                  (format "~v ~a" value (object-name op))))
  (check-not-equal? (outcome (lambda () (p+ nulls #\a)))
                    (outcome (lambda () (p+ nulls (date 2024 1 1)))))
  (define (polars-failure? e) (and (exn:fail? e) (not (exn:fail:contract? e))))
  (for ([case (list (list (lambda () (p+ nulls (date 2024 1 1))) polars-failure?
                          #rx"^[+]: [^\n]*date$")
                    (list (lambda () (p- nulls "a")) polars-failure? #rx"^-: [^\n]*str`$")
                    (list (lambda () (p- "a" nulls)) polars-failure? #rx"^-: [^\n]*str`$")
                    (list (lambda () (p+ nulls #\a)) exn:fail:contract? #rx"^[+]: [^\n]*#\\\\a$")
                    (list (lambda () (= nulls #\a)) exn:fail:contract? #rx"^=: [^\n]*#\\\\a$")
                    (list (lambda () (p+ nulls (expt 2 63))) exn:fail:contract?
                          #rx"^[+]: .*_int64.*9223372036854775808$")
                    (list (lambda () (> (expt 2 63) nulls)) exn:fail:contract?
                          #rx"^>: .*_int64.*9223372036854775808$"))])
    (match-define (list thunk kind rx) case)
    (check-exn kind thunk)
    (define message (with-handlers ([exn:fail? exn-message]) (thunk) #f))
    (check-regexp-match rx message)
    (check-false (regexp-match? #rx"Resolved plan|lazyframe-collect|lit:|expr_lit" message)))
  (check-equal? (series->list (= (series (list (date 2024 1 1))) (datetime 2024 1 1))) '(#t))
  (check-equal? (series->list (= (series (list (date 2024 1 1))) (datetime 2024 1 1 0 0 1))) '(#f))
  (check-eq? (p+ ints) ints)
  (check-eq? (p* ints) ints)
  (check-exn #rx"^-: cannot negate a series of this dtype\n  dtype: 'uint8"
             (lambda () (p- (series '(1 2) #:dtype 'u8))))
  (check-exn #rx"^-: cannot negate a series of this dtype\n  dtype: 'string"
             (lambda () (p- (series '("a" "b")))))
  (for ([operand (list (series '("a")) (series '(#t #f)) (series (list (hours 1)))
                       (series (list (datetime 2013 1 1))))])
    (check-exn #rx"^/: cannot take the reciprocal of a series of this dtype\n  dtype: "
               (lambda () (p/ operand))))
  (for ([operand (list 5 (col "value") v64)])
    (check-exn #rx"^mod: arity mismatch.*expected: at least 2\n  given: 1"
               (lambda () (mod operand))))
  (check-exn #rx"^mod: arity mismatch.*expected: at least 2\n  given: 0" (lambda () (mod)))

  ;; when / then / otherwise build an Expr; control-flow path stays racket `when`
  (check-pred Expr-ptr? (~> (p-when (> (col "score") 15)) (then 10) (otherwise 0)))
  ;; chained when / then / else-when / then / otherwise (end-to-end values are
  ;; checked in reshape's with-columns tests; here we only confirm it builds)
  (check-pred Expr-ptr?
              (~> (p-when (> (col "score") 20)) (then 2)
                  (else-when (> (col "score") 10)) (then 1)
                  (otherwise 0)))
  (check-exn exn:fail? (lambda () (else-when (when-pending '() #t) #t))) ; else-when needs a then
  (check-equal? (let ([acc 0]) (p-when #t (set! acc 1)) acc) 1)
  (check-equal? (let ([acc 0]) (p-when #f (set! acc 1)) acc) 0))
