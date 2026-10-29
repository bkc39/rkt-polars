#lang racket/base

(require racket/contract/base
         racket/match
         (prefix-in base: racket/base)
         syntax/parse/define
         polars/private/foreign
         (only-in (submod polars/private/foreign internal)
                  series-n-unique/who series-std/who series-var/who typed-reductions)
         (except-in polars/private/expr expr-std expr-var)
         (only-in (submod polars/private/expr internal) expr-std expr-var)
         (only-in polars/private/c-integer uint8/c)
         polars/private/generic/core
         polars/private/generic/dtype
         (only-in polars/private/generic/expr-util ->col-expr col-expr/c)
         (only-in polars/private/resource with-release))

(provide (contract-out
          [std (->* ((or/c series? col-expr/c)) (#:ddof uint8/c) any/c)]
          [var (->* ((or/c series? col-expr/c)) (#:ddof uint8/c) any/c)]
          [n-unique (-> (or/c series? col-expr/c) any/c)]
          [alias (-> col-expr/c string? Expr-ptr?)])
         sum mean min max count median first last)

(define (reduction-route op dt)
  (match* (op dt)
    [('mean (or 'string 'categorical 'binary (cons 'enum _))) 'null]
    [('sum (or 'int8 'int16 'uint8 'uint16)) 'expr]
    [((or 'std 'var) 'float32) 'expr]
    [((or 'sum 'mean 'min 'max) (? numeric-dtype?)) 'native]
    [((or 'std 'var) (? numeric-dtype?)) 'dispersion]
    [((or 'std 'var) 'boolean) 'float64]
    [(_ (or 'null (? decimal-dtype?))) 'expr]
    [('sum (or 'boolean (list 'duration _))) 'expr]
    [('std (list 'duration _)) 'expr]
    [((or 'mean 'min 'max) _) 'expr]
    [(_ _) #f]))

(define (series-agg-via-expr who expr-op s)
  (with-release ([frame (dataframe-new (list s)) dataframe-drop]
                 [all (expr-all) expr-drop]
                 [reduced (expr-op all) expr-drop]
                 [named (expr-alias reduced "v") expr-drop]
                 [out (dataframe-select-exprs frame (list named)) dataframe-drop]
                 [column (dataframe-column out "v") series-drop])
    (series-value who column 0)))

(define (reduce-series op s #:ddof [ddof 1])
  (define dt (series-dtype s))
  (define series-dispersion (if (eq? op 'std) series-std/who series-var/who))
  (match (reduction-route op dt)
    ['native (or ((hash-ref (hash-ref typed-reductions op) dt) op s) polars-null)]
    ['dispersion (or (series-dispersion op s #:ddof ddof) polars-null)]
    ['float64 (with-release ([floats (series-cast s 'float64) series-drop])
                (or (series-dispersion op floats #:ddof ddof) polars-null))]
    ['expr (series-agg-via-expr op (lambda (e) (aggregation op e ddof)) s)]
    ['null polars-null]
    [#f (error op "unsupported dtype for reduction: ~v" dt)]))

(define (aggregation op e ddof)
  (match op
    ['sum (expr-sum e)]
    ['mean (expr-mean e)]
    ['min (expr-min e)]
    ['max (expr-max e)]
    ['std (expr-std e #:ddof ddof)]
    ['var (expr-var e #:ddof ddof)]))

(define-syntax-parse-rule (define-reducer (name:id formal:id ... . rest:id) plain:expr)
  (define (name formal ... . rest)
    (match (list* formal ... rest)
      [(list (? Expr-ptr? e)) (aggregation 'name e 1)]
      [(list (? string? column)) (aggregation 'name (col column) 1)]
      [(list (? series? s)) (reduce-series 'name s)]
      [args (apply plain args)])))

(define-reducer (sum . vs) base:+)
(define-reducer (mean v . vs) (lambda args (/ (apply base:+ args) (length args))))
(define-reducer (min . vs) base:min)
(define-reducer (max . vs) base:max)

(define (dispersion op x ddof)
  (match x
    [(? series?) (reduce-series op x #:ddof ddof)]
    [_ (aggregation op (->col-expr op x) ddof)]))

(define (std x #:ddof [ddof 1]) (dispersion 'std x ddof))
(define (var x #:ddof [ddof 1]) (dispersion 'var x ddof))

(define (count x) (expr-count (->col-expr 'count x)))

(define (n-unique x)
  (match x
    [(? series?) (series-n-unique/who 'n-unique x)]
    [_ (expr-n-unique (->col-expr 'n-unique x))]))

(define (median x) (expr-median (->col-expr 'median x)))

(define (first x)
  (cond
    [(Expr-ptr? x) (expr-first x)]
    [(string? x) (expr-first (col x))]
    [(pair? x) (car x)]
    [else (error 'first "expected an Expr, column name, or non-empty list, got ~v" x)]))

(define (last x)
  (cond
    [(Expr-ptr? x) (expr-last x)]
    [(string? x) (expr-last (col x))]
    [(pair? x) (let loop ([l x]) (if (null? (cdr l)) (car l) (loop (cdr l))))]
    [else (error 'last "expected an Expr, column name, or non-empty list, got ~v" x)]))

(define (alias e name) (expr-alias (->col-expr 'alias e) name 'alias))

(module+ internal
  (provide n-unique std var))
