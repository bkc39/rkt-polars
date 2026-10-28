#lang racket/base

(require racket/match
         (only-in racket/contract/base
                  -> ->* ->i any/c contract-out flat-contract-predicate listof or/c
                  unsupplied-arg?)
         (prefix-in base: racket/base)
         (except-in racket/list drop)
         (only-in racket/list [drop list-drop])
         (only-in racket/contract/base contract-out)
         polars/private/foreign
         polars/private/expr
         (only-in (submod polars/private/expr internal) collect-plan/who lazyframe-collect/who)
         (only-in polars/private/resource utf-8-name->string utf-8-name/c utf-8-names/c with-release)
         (only-in polars/private/expr-core explain/c lazyframe-explainer)
         polars/private/generic/core
         (only-in polars/private/c-integer int64-max int64/c size/c)
         (only-in polars/private/generic/dtype dtype-spec?)
         (only-in polars/private/generic/expr-util col-expr/c))

(provide (except-out (all-defined-out) cast explain head tail slice drop pivot unpivot
                     group-by agg rename with-column)
         (contract-out
          [cast (-> (or/c Expr-ptr? series? string?) cast-target/c (or/c Expr-ptr? series?))]
          [head (-> rows-source/c size/c any/c)]
          [tail (-> rows-source/c size/c any/c)]
          [slice (-> rows-source/c int64/c size/c any/c)]
          [drop (->i ([x (or/c dataframe? list?)]
                      [arg (x) (if (dataframe? x) (or/c utf-8-name/c utf-8-names/c) any/c)])
                     [result any/c])]
          [pivot (->* (dataframe? #:on utf-8-names/c #:index utf-8-names/c #:values utf-8-names/c)
                      (#:agg (or/c #f 'none 'first 'sum 'min 'max 'mean 'count))
                      dataframe?)]
          [unpivot (-> dataframe? #:on utf-8-names/c #:index utf-8-names/c dataframe?)]
          [with-column (-> dataframe? series? dataframe?)]
          [group-by (-> (or/c dataframe? lazyframe?) col-expr/c col-expr/c ... grouped?)]
          [agg (-> grouped? Expr-ptr? ... (or/c dataframe? lazyframe?))]
          (rename rename rename (->i ([x (or/c series? dataframe?)] [a utf-8-name/c])
                                     ([b utf-8-name/c])
                                     #:pre/desc (x b)
                                     (or (series? x) (not (unsupplied-arg? b))
                                         "renaming a dataframe column needs old and new names")
                                     [result (or/c series? dataframe?)]))
          [explain (explain/c lazyframe?)]))

(define cast-target/c (or/c dtype-spec? 'binary 'duration))

(define rows-source/c (or/c series? dataframe? lazyframe? Expr-ptr?))

(define expr-rows-max int64-max)

(define (expr-window offset length)
  (define start (max offset (- expr-rows-max)))
  (values start (min expr-rows-max (max 0 (- length (- start offset))))))

(define (column-height-problem d s)
  (define height (dataframe-height d))
  (define n (series-len s))
  (and (not (= n height))
       (format "unable to add a column of length ~a to a DataFrame of height ~a" n height)))

(define (rename-problem d old new)
  (define present (dataframe-column-names d))
  (cond
    [(column-problem present (list old)) => values]
    [(member new present) (format "column '~a' is duplicate" new)]
    [else #f]))

(define (collect-frame who d extend)
  (wrap-dataframe (collect-plan/who who d extend)))

(define (filter . args)
  (match args
    [(list (? dataframe? d) (? Expr-ptr? pred))
     (collect-frame 'filter d (lambda (plan) (lazyframe-filter plan pred)))]
    [(list (? dataframe? d) (? series? mask))
     (with-release ([predicate (expr-lit-series mask) expr-drop])
       (collect-frame 'filter d (lambda (plan) (lazyframe-filter plan predicate))))]
    [(list (? lazyframe? lf) (? Expr-ptr? pred))
     (wrap-lazyframe (lazyframe-filter lf pred))]
    [(list (? Expr-ptr? e) (? Expr-ptr? pred))
     (expr-filter e pred)]   ; column-level filter; length-changing, use in select
    [_ (apply base:filter args)]))

(define (head x n)
  (cond [(series? x)    (wrap-series    (series-head x n))]
        [(dataframe? x) (wrap-dataframe (dataframe-head x n))]
        [(lazyframe? x) (wrap-lazyframe (lazyframe-head x n))]
        [else           (expr-head x #:n n)]))

(define (tail x n)
  (cond [(series? x)    (wrap-series    (series-tail x n))]
        [(dataframe? x) (wrap-dataframe (dataframe-tail x n))]
        [(lazyframe? x) (wrap-lazyframe (lazyframe-tail x n))]
        [else           (expr-tail x #:n n)]))

(define (slice x offset length)
  (cond [(series? x)    (wrap-series    (series-slice x offset length))]
        [(dataframe? x) (wrap-dataframe (dataframe-slice x offset length))]
        [(lazyframe? x) (wrap-lazyframe (lazyframe-slice x offset length))]
        [else
         (define-values (start rows) (expr-window offset length))
         (expr-slice x start rows)]))

(define (unique x)
  (cond [(series? x)    (wrap-series    (series-unique x))]
        [(dataframe? x) (wrap-dataframe (dataframe-unique x))]
        [else (error 'unique "expected a series or dataframe, got ~v" x)]))

(define (drop-nulls x)
  (cond [(series? x)    (wrap-series    (series-drop-nulls x))]
        [(dataframe? x) (wrap-dataframe (dataframe-drop-nulls x))]
        [(Expr-ptr? x)  (expr-drop-nulls x)]   ; length-changing; use inside select
        [else (error 'drop-nulls "expected a series, dataframe, or Expr, got ~v" x)]))

(define (reverse x)
  (cond [(series? x)   (wrap-series (series-reverse x))]
        [(Expr-ptr? x) (expr-reverse x)]
        [(list? x)     (base:reverse x)]
        [else (error 'reverse "expected a series, Expr, or list, got ~v" x)]))

;; --- dataframe column operations --------------------------------------------

;; Coerce select/with-columns specs into a flat Expr list: an Expr passes
;; through, a string/index is lifted via (col ...), a list splices.
(define (specs->exprs who d specs)
  (define (spec->expr s)
    (cond [(Expr-ptr? s) s]
          [(string? s) (col s)]
          [(exact-nonnegative-integer? s) (col (dataframe-column-name d s))]
          [else (error who "expected a column name, index, or Expr, got ~v" s)]))
  (append-map (lambda (s) (if (list? s) (map spec->expr s) (list (spec->expr s)))) specs))

;; select: project / derive columns -> dataframe (Polars df.select).  Variadic
;; and expression-aware: each argument is a column name, index, an Expr, or a
;; list thereof.  Always a dataframe.
(define (select d . specs)
  (cond
    [(dataframe? d)
     (collect-frame 'select d (lambda (plan) (lazyframe-select plan (specs->exprs 'select d specs))))]
    [(lazyframe? d)
     (wrap-lazyframe (lazyframe-select d (specs->exprs 'select d specs)))]
    [else (error 'select "expected a dataframe or lazyframe, got ~v" d)]))

;; with-columns: add/replace columns in one pass (Polars df.with_columns).
;; Same variadic, expression-aware specs as select, but keeps the existing
;; columns and appends the (typically aliased) derived ones.
(define (with-columns d . specs)
  (cond
    [(dataframe? d)
     (collect-frame 'with-columns d
                    (lambda (plan) (lazyframe-with-columns plan (specs->exprs 'with-columns d specs))))]
    [(lazyframe? d)
     (wrap-lazyframe (lazyframe-with-columns d (specs->exprs 'with-columns d specs)))]
    [else (error 'with-columns "expected a dataframe or lazyframe, got ~v" d)]))

(define (drop x arg)
  (cond
    [(dataframe? x)
     (define names (map utf-8-name->string (if (list? arg) arg (list arg))))
     (wrap-dataframe
      (or (dataframe-drop-columns/c x names)
          (refuse 'drop (column-problem (dataframe-column-names x) names)
                  "cannot drop the columns")))]
    [else (list-drop x arg)]))

(define (with-column d s)
  (wrap-dataframe
   (or (dataframe-with-column/raw d s)
       (refuse 'with-column (column-height-problem d s) "cannot add the column"))))

(define (cast x dtype)
  (cond [(Expr-ptr? x) (expr-cast-to 'cast x dtype)]
        [(series? x)   (wrap-series (series-cast-to 'cast x dtype))]
        [else          (expr-cast-to 'cast (col x) dtype)]))

(define (pivot d #:on on #:index index #:values values #:agg [agg 'first])
  (wrap-dataframe (pivot-frame 'pivot d on index values agg)))

(define (unpivot d #:on on #:index index)
  (wrap-dataframe (unpivot-frame 'unpivot d on index)))

;; --- group-by / agg: the deferred, threading-compatible group handle --------
(struct grouped (frame keys) #:reflection-name 'grouped)

(define (group-by frame . keys)
  (grouped frame keys))

(define (agg g . agg-exprs)
  (define frame (grouped-frame g))
  (define keys (grouped-keys g))
  ;; dispatch on whether the grouped frame is eager or lazy
  (if (lazyframe? frame)
      (wrap-lazyframe (lazyframe-group-by-agg frame keys agg-exprs))
      (collect-frame 'agg frame (lambda (plan) (lazyframe-group-by-agg plan keys agg-exprs)))))

;; --- lazy: a DataFrame's deferred query plan, and back ----------------------
(define (lazy d)
  (guard-dataframe 'lazy d)
  (wrap-lazyframe (dataframe-lazy d)))

(define (collect lf)
  (unless (lazyframe? lf)
    (error 'collect "expected a lazyframe, got ~v" lf))
  (wrap-dataframe (lazyframe-collect/who 'collect lf)))

(define explain (lazyframe-explainer 'explain))

;; --- clone / rename ---------------------------------------------------------
;; series-slice already returns a fresh series, so a full-length slice clones.
(define (series-clone s)
  (wrap-series (series-slice s 0 (series-len s))))

(define (clone x)
  (cond
    [(series? x) (series-clone x)]
    [else (error 'clone "expected a series, got ~v" x)]))

;; mutating: renames in place, returns void.
(define (rename! x new-name)
  (cond
    [(series? x) (series-rename x new-name)]
    [else (error 'rename! "expected a series, got ~v" x)]))

(define (rename x a [b unset])
  (define name (utf-8-name->string a))
  (cond
    [(series? x)
     (define c (series-clone x))
     (series-rename c name)
     c]
    [else
     (define new (utf-8-name->string b))
     (wrap-dataframe
      (or (dataframe-rename/raw x name new)
          (refuse 'rename (rename-problem x name new) "cannot rename the column")))]))

(module+ internal
  (provide agg cast drop group-by head pivot rename slice tail unpivot with-column))
