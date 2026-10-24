#lang racket/base

(require (prefix-in base: racket/base)
         (only-in racket/match match match-define)
         polars/private/foreign
         polars/private/expr
         (only-in polars/private/expr-core drop-owned)
         polars/private/generic/core
         polars/private/generic/dtype
         polars/private/generic/logical
         polars/private/generic/operands
         (only-in polars/private/resource with-release)
         syntax/parse/define
         (for-syntax racket/base syntax/parse))

(provide (all-defined-out)
         (all-from-out polars/private/generic/logical))

(define-syntax-parse-rule (define-cmp name:id expr-op:expr series-op:expr
                                      series-op-reflected:expr base-op:expr)
  (define (name . args)
    (match args
      [_ #:when (andmap base:number? args) (apply base-op args)]
      [(list a b)
       (cond
         [(or (Expr-ptr? a) (Expr-ptr? b)) (call-with-exprs 'name a b expr-op)]
         [(expression-form-op 'name expr-op a b) => values]
         [(series? a)
          (call-with-operand-series 'name a b 'right
                                    (lambda (o) (named-after a b (series-op 'name a o))))]
         [(series? b)
          (call-with-operand-series 'name b a 'left
                                    (lambda (o) (named-after b a (series-op-reflected 'name b o))))]
         [else (base-op a b)])]
      [_ (apply base-op args)])))

(define (named-after s other result)
  (cond
    [(series? other) (wrap-series result)]
    [else (series-rename result (series-name s))
          (wrap-series result)]))

(define (base:!= . args) (base:not (apply base:= args)))

(define-cmp >  expr-gt series-gt/who series-lt/who base:>)
(define-cmp <  expr-lt series-lt/who series-gt/who base:<)
(define-cmp >= expr-ge series-ge/who series-le/who base:>=)
(define-cmp <= expr-le series-le/who series-ge/who base:<=)
(define-cmp =  expr-eq series-eq/who series-eq/who base:=)
(define-cmp != expr-ne series-ne/who series-ne/who base:!=)

(define (call-with-exprs who a b proc)
  (with-release ([ea (->expr/who who a) (if (eq? ea a) void expr-drop)]
                 [eb (->expr/who who b) (if (eq? eb b) void expr-drop)])
    (proc ea eb)))

(define (binary-arith who expr-op series-op base-op a b)
  (cond [(or (Expr-ptr? a) (Expr-ptr? b)) (call-with-exprs who a b expr-op)]
        [(expression-form-op who expr-op a b) => values]
        [(series? a)
         (call-with-operand-series who a b 'right
                                   (lambda (o) (wrap-series (series-op who a o 'right))))]
        [(series? b)
         (call-with-operand-series who b a 'left
                                   (lambda (o) (wrap-series (series-op who o b 'left))))]
        [else (base-op a b)]))

(define ((sideless series-op) who a b _side)
  (series-op who a b))

(define (integer-like? dt)
  (and (memq dt '(int8 int16 int32 int64 uint8 uint16 uint32 uint64 boolean null)) #t))

(define (series-true-div who a b side)
  (define a-integer? (integer-like? (series-dtype a)))
  (define b-dtype (series-dtype b))
  (define floor? (and a-integer? (integer-like? b-dtype)
                      (not (and (eq? (series-dtype a) 'null) (eq? b-dtype 'null)))))
  (define cast-a? (and a-integer? (not floor?)))
  (define cast-b? (and (eq? side 'left) (not floor?)
                       (match b-dtype
                         [(or 'float32 (list 'decimal _ _)) #t]
                         [_ (integer-like? b-dtype)])))
  (with-release ([a* (if cast-a? (series-cast a 'float64) a) (if cast-a? series-drop void)]
                 [b* (if cast-b? (series-cast b 'float64) b) (if cast-b? series-drop void)])
    (series-div/who who a* b*)))

(define (series-negate s)
  (match (series-dtype s)
    ['null s]
    [(or 'int8 'int16 'int32 'int64 'float32 'float64 (list 'duration _) (list 'decimal _ _))
     (series-through-expr '- s expr-neg)]
    [dt (raise-arguments-error '- "cannot negate a series of this dtype" "dtype" dt)]))

(define (expr-reciprocal e)
  (with-release ([divided (p/ 1 e) expr-drop])
    (match (expr-meta-output-name/raw e)
      [#f (expr-name-keep divided)]
      [name (expr-alias divided name)])))

(define (series-reciprocal s)
  (match (series-dtype s)
    ['null s]
    [(or (? numeric-dtype?) 'boolean (list 'decimal _ _)) (series-through-expr '/ s expr-reciprocal)]
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
      [(cons a more)
       (for/fold ([acc a]) ([b (in-list more)])
         (with-release ([consumed acc (if (eq? consumed a) void drop-owned)])
           (binary-arith 'who expr-op series-op base-op consumed b)))])))

(define-arith p+ + expr-add (sideless series-add/who) base:+)
(define-arith p- - expr-sub (sideless series-sub/who) base:- #:unary expr-neg series-negate)
(define-arith p* * expr-mul (sideless series-mul/who) base:*)
(define-arith p/ / expr-div series-true-div base:/ #:unary expr-reciprocal series-reciprocal)

(define (base:mod a b . more)
  (foldl (lambda (m acc) (base:modulo acc m)) (base:modulo a b) more))

(define-arith mod mod expr-mod (sideless series-mod/who) base:mod #:binary-only)

(struct when-pending (clauses cond))
(struct when-acc (clauses))

(define (then wp value)
  (unless (when-pending? wp)
    (error 'then "`then` must follow `when` / `else-when`, got ~v" wp))
  (when-acc (append (when-pending-clauses wp)
                    (list (list (when-pending-cond wp) (->expr/who 'then value))))))

(define (else-when wa cond)
  (unless (when-acc? wa)
    (error 'else-when "`else-when` must follow `then`, got ~v" wa))
  (when-pending (when-acc-clauses wa) (->expr/who 'else-when cond)))

(define (otherwise wa default)
  (unless (when-acc? wa)
    (error 'otherwise "`otherwise` must follow `then`, got ~v" wa))
  (expr-when (when-acc-clauses wa) #:otherwise (->expr/who 'otherwise default)))

(define-syntax-parser p-when
  [(_ c:expr) #'(when-pending '() (->expr/who 'when c))]
  [(_ test:expr body:expr ...) #'(base:when test body ...)])

(module+ test
  (require rackunit
           (only-in ffi/unsafe/atomic call-as-atomic)
           (only-in gregor date)
           (only-in gregor/period hours minutes)
           (only-in gregor/time time)
           (only-in polars/private/bulk series->list)
           (only-in polars/private/expr-core expr-drop-count)
           (only-in polars/private/resource with-release)
           polars/private/generic/core
           polars/private/generic/test-fixtures
           (only-in threading ~>))

  (define operand-ints (series '(1 2) #:name "x"))
  (define operand-flags (series '(#t #f) #:name "f"))
  (for ([apply-operator (list (lambda () (p+ operand-ints 1))
                              (lambda () (< 1 operand-ints))
                              (lambda () (p-and operand-flags #t)))])
    (settle!)
    (let ([before (series-drop-count)])
      (apply-operator)
      (check >= (- (series-drop-count) before) 1)))
  (define (owned-temporaries thunk)
    (with-release ([v (col "v") expr-drop])
      (thunk v)))
  (for ([row (in-list
              (list (list "(+ s 1)" series-drop-count
                          (lambda (v) (series-drop (p+ operand-ints 1))) 2)
                    (list "(+ s 1 2 3)" series-drop-count
                          (lambda (v) (series-drop (p+ operand-ints 1 2 3))) 6)
                    (list "(* s s s s)" series-drop-count
                          (lambda (v) (series-drop (p* operand-ints operand-ints operand-ints
                                                       operand-ints)))
                          3)
                    (list "(+ s 1 (box 2))" series-drop-count
                          (lambda (v) (check-exn exn:fail:contract?
                                                 (lambda () (p+ operand-ints 1 (box 2)))))
                          2)
                    (list "(- e 1)" expr-drop-count (lambda (v) (expr-drop (p- v 1))) 3)
                    (list "(- e 1 2 3)" expr-drop-count (lambda (v) (expr-drop (p- v 1 2 3))) 7)
                    (list "(+ 1 e)" expr-drop-count (lambda (v) (expr-drop (p+ 1 v))) 3)
                    (list "(> e 1)" expr-drop-count (lambda (v) (expr-drop (> v 1))) 3)
                    (list "(< 1 e)" expr-drop-count (lambda (v) (expr-drop (< 1 v))) 3)
                    (list "(= e e)" expr-drop-count (lambda (v) (expr-drop (= v v))) 2)
                    (list "(/ e)" expr-drop-count (lambda (v) (expr-drop (p/ v))) 4)
                    (list "(/ s)" expr-drop-count
                          (lambda (v) (series-drop (p/ operand-ints))) 6)))])
    (match-define (list label count thunk expected) row)
    (check-equal? (drops-during count (lambda () (owned-temporaries thunk))) expected label)
    (check-equal? (drops-during count (lambda () (owned-temporaries thunk) (settle!))) expected
                  label))
  (check-equal? (series->list (p+ operand-ints operand-ints)) '(2 4))
  (check-equal? (series->list (p-and operand-flags operand-flags)) '(#t #f))
  (check-equal? (series->list operand-ints) '(1 2))
  (check-equal? (series->list operand-flags) '(#t #f))

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
  (check-pred Expr-ptr? (p-and (>= (col "value") 10) (<= (col "value") 25)))
  (check-pred Expr-ptr? (p-or (= (col "group") "a") (= (col "group") "c")))
  (check-pred Expr-ptr? (p-not (= (col "group") "a")))
  (define m1 (> v64 15))
  (define m2 (< v64 20))
  (define (mask->list m) (for/list ([i (in-range (len m))]) (ref m i)))
  (check-equal? (mask->list (p-and m1 m2)) '(#f #f #f #f #t))
  (check-equal? (mask->list (p-or  m1 m2)) '(#t #t #t #t #t))
  (check-equal? (mask->list (p-not m1))    '(#t #f #t #f #f))
  (check-equal? (mask->list (p-xor m1 m2)) '(#t #t #t #t #f))

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
  (for ([unary (list (list (p- (col "value")) "col(\"value\").negate()")
                    (list (p/ (col "value"))
                          "[(dyn int: 1) rust_div (col(\"value\"))].alias(\"value\")")
                    (list (p+ (col "value")) "col(\"value\")")
                    (list (p* (col "value")) "col(\"value\")")
                    (list (p- (col "delay")) "col(\"delay\").negate()")
                    (list (p/ (col "speed"))
                          "[(dyn int: 1) rust_div (col(\"speed\"))].alias(\"speed\")"))])
    (match-define (list e printed) unary)
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
  (check-equal? (series->list (= (series (list (date 2024 1 1))) (datetime 2024 1 1))) '(#t))
  (check-equal? (series->list (= (series (list (date 2024 1 1))) (datetime 2024 1 1 0 0 1))) '(#f))
  (check-eq? (p+ ints) ints)
  (check-eq? (p* ints) ints)
  (check-exn #rx"^-: cannot negate a series of this dtype\n  dtype: 'uint8"
             (lambda () (p- (series '(1 2) #:dtype 'u8))))
  (check-exn #rx"^-: cannot negate a series of this dtype\n  dtype: 'string"
             (lambda () (p- (series '("a" "b")))))
  (define bools (series '(#t #f) #:name "b"))
  (for ([result (list (p/ bools) (p/ 1 bools))])
    (check-equal? (list (dtype result) (series-name result) (series->list result))
                  (list 'int32 "b" (list 1 polars-null))))
  (for ([operand (list (series '("a")) (series (list (hours 1)))
                       (series (list (datetime 2013 1 1))))])
    (check-exn #rx"^/: cannot take the reciprocal of a series of this dtype\n  dtype: "
               (lambda () (p/ operand))))
  (for ([operand (list 5 (col "value") v64)])
    (check-exn #rx"^mod: arity mismatch.*expected: at least 2\n  given: 1"
               (lambda () (mod operand))))
  (check-exn #rx"^mod: arity mismatch.*expected: at least 2\n  given: 0" (lambda () (mod)))

  (check-pred Expr-ptr? (~> (p-when (> (col "score") 15)) (then 10) (otherwise 0)))
  (check-pred Expr-ptr?
              (~> (p-when (> (col "score") 20)) (then 2)
                  (else-when (> (col "score") 10)) (then 1)
                  (otherwise 0)))
  (check-exn exn:fail? (lambda () (else-when (when-pending '() #t) #t)))
  (check-equal? (let ([acc 0]) (p-when #t (set! acc 1)) acc) 1)
  (check-equal? (let ([acc 0]) (p-when #f (set! acc 1)) acc) 0))
