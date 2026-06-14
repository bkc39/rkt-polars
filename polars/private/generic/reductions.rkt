#lang racket/base

;; dtype-dispatched reductions (sum / mean / min / max) and the Polars-style
;; aggregator spellings (count / n-unique / median / std / var / first / last /
;; alias).  Numeric series reduce via the fast typed FFI; non-numeric series
;; (string / temporal / boolean) reduce via the expr engine through the single
;; `series-agg-via-expr` helper — the one home for that computation (describe
;; reuses min/max/mean rather than duplicating it).

(require racket/match
         (prefix-in base: racket/base)
         polars/private/foreign
         polars/private/expr
         polars/private/generic/core
         polars/private/generic/dtype
         polars/private/generic/expr-util)

(provide (all-defined-out))

(define sum-table
  (hash 'int8 series-sum-i8 'int16 series-sum-i16
        'int32 series-sum-i32 'int64 series-sum-i64
        'uint8 series-sum-u8 'uint16 series-sum-u16
        'uint32 series-sum-u32 'uint64 series-sum-u64
        'float32 series-sum-f32 'float64 series-sum-f64))

(define min-table
  (hash 'int8 series-min-i8 'int16 series-min-i16
        'int32 series-min-i32 'int64 series-min-i64
        'uint8 series-min-u8 'uint16 series-min-u16
        'uint32 series-min-u32 'uint64 series-min-u64
        'float32 series-min-f32 'float64 series-min-f64))

(define max-table
  (hash 'int8 series-max-i8 'int16 series-max-i16
        'int32 series-max-i32 'int64 series-max-i64
        'uint8 series-max-u8 'uint16 series-max-u16
        'uint32 series-max-u32 'uint64 series-max-u64
        'float32 series-max-f32 'float64 series-max-f64))

(define mean-table
  (hash 'int8 series-mean-i8 'int16 series-mean-i16
        'int32 series-mean-i32 'int64 series-mean-i64
        'uint8 series-mean-u8 'uint16 series-mean-u16
        'uint32 series-mean-u32 'uint64 series-mean-u64
        'float32 series-mean-f32 'float64 series-mean-f64))

(define (series-reduce who table s)
  (define dt (series-dtype s))
  (define f (hash-ref table dt #f))
  (unless f
    (error who "unsupported dtype for reduction: ~v" dt))
  (f s))

;; reduce a series to a scalar via the expr engine — handles every dtype,
;; including string/temporal min/max and boolean mean.  Single home for the
;; expr-based reduction (shared by the non-numeric paths below and, through
;; them, by describe).
(define (series-agg-via-expr expr-op s)
  (define name (series-name s))
  (define out (dataframe-select-exprs (dataframe-new (list s))
                                      (list (expr-alias (expr-op (col name)) "v"))))
  (series-ref (dataframe-column out "v") 0))

;; sum / mean / min / max are generic across three worlds:
;;   * a single Expr   -> the corresponding aggregation Expr (expr-sum, …)
;;   * a single series -> reduce to a scalar (numeric: fast typed FFI;
;;                        non-numeric min/max/mean: the expr engine)
;;   * anything else   -> racket/base numeric behaviour (variadic preserved)

(define (sum . args)
  (match args
    [(list (? Expr-ptr? e)) (expr-sum e)]
    [(list (? string? s)) (expr-sum (col s))]
    [(list (? series? s)) (series-reduce 'sum sum-table s)]
    [_ (apply base:+ args)]))

(define (mean . args)
  (match args
    [(list (? Expr-ptr? e)) (expr-mean e)]
    [(list (? string? s)) (expr-mean (col s))]
    [(list (? series? s))
     (if (numeric-dtype? (series-dtype s))
         (series-reduce 'mean mean-table s)
         (series-agg-via-expr expr-mean s))]   ; boolean -> fraction true
    [(list) (error 'mean "expected at least one argument")]
    [_ (/ (apply base:+ args) (length args))]))

(define (min . args)
  (match args
    [(list (? Expr-ptr? e)) (expr-min e)]
    [(list (? string? s)) (expr-min (col s))]
    [(list (? series? s))
     (if (numeric-dtype? (series-dtype s))
         (series-reduce 'min min-table s)
         (series-agg-via-expr expr-min s))]    ; string / temporal / boolean
    [_ (apply base:min args)]))

(define (max . args)
  (match args
    [(list (? Expr-ptr? e)) (expr-max e)]
    [(list (? string? s)) (expr-max (col s))]
    [(list (? series? s))
     (if (numeric-dtype? (series-dtype s))
         (series-reduce 'max max-table s)
         (series-agg-via-expr expr-max s))]
    [_ (apply base:max args)]))

;; --- additional Expr aggregators (Polars col(...).agg() spellings) ----------
;; Take an Expr or a bare column name (lifted via col).  first / last also keep
;; their racket/list list-accessor behaviour.

(define (count x)     (expr-count    (->col-expr 'count x)))
;; n-unique: eager count on a series; otherwise an aggregation Expr.
(define (n-unique x)
  (cond [(series? x) (series-n-unique x)]
        [else (expr-n-unique (->col-expr 'n-unique x))]))
(define (median x)    (expr-median   (->col-expr 'median x)))
;; std / var: eager on a series (dispatching #:ddof), otherwise an Expr aggregator.
(define (std x #:ddof [ddof 1])
  (cond [(series? x) (series-std x #:ddof ddof)]
        [else (expr-std (->col-expr 'std x) #:ddof ddof)]))
(define (var x #:ddof [ddof 1])
  (cond [(series? x) (series-var x #:ddof ddof)]
        [else (expr-var (->col-expr 'var x) #:ddof ddof)]))

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

;; alias: name an Expr (Polars' .alias) — e.g. (alias (sum (col "value")) "total").
(define (alias e name) (expr-alias e name))

(module+ test
  (require rackunit polars/private/generic/test-fixtures)
  ;; reductions dispatch on dtype (numeric series)
  (check-equal? (sum ints) 10)
  (check-equal? (max floats) 8.0)
  (check-equal? (min ints) 1)
  (check-equal? (mean ints) 2.5)
  (check-pred flonum? (mean ints))
  ;; numeric fallback preserves racket/base behaviour
  (check-equal? (max 1 2 3) 3)
  (check-equal? (min 4 2 9) 2)
  (check-equal? (sum 1 2 3) 6)
  (check-equal? (sum) 0)
  (check-equal? (mean 2 4) 3)
  ;; non-numeric min/max via the expr engine (matches Polars)
  (check-equal? (min (series '("banana" "apple" "cherry"))) "apple")
  (check-equal? (max (series '("banana" "apple" "cherry"))) "cherry")
  ;; Expr aggregators accept an Expr or a bare column name
  (check-pred Expr-ptr? (sum "value"))
  (check-pred Expr-ptr? (mean (col "value")))
  (check-pred Expr-ptr? (n-unique "group"))
  ;; first / last keep their list-accessor behaviour
  (check-equal? (first '(1 2 3)) 1)
  (check-equal? (last '(1 2 3)) 3)
  (check-pred Expr-ptr? (first (col "value")))
  ;; std / var eager on a series (with #:ddof)
  (let ([s (series '(1.0 2.0 3.0 4.0))])     ; deviations from mean 2.5 sum-sq = 5.0
    (check-= (var s) (/ 5.0 3.0) 1e-9)        ; sample (ddof=1)
    (check-= (var s #:ddof 0) 1.25 1e-9)      ; population (ddof=0)
    (check-= (std s #:ddof 0) (sqrt 1.25) 1e-9)))
