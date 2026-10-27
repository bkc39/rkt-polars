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
