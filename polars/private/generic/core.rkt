#lang racket/base

(require racket/generic
         (only-in racket/contract/base -> ->* any/c contract-out listof or/c)
         (only-in racket/list check-duplicates)
         (only-in racket/match match*)
         syntax/parse/define
         (for-syntax racket/base)
         (only-in ffi/unsafe prop:cpointer)
         (only-in polars/private/bulk in-series)
         (only-in polars/private/expr-core lazyframe-dropped)
         polars/private/foreign
         (only-in polars/private/resource utf-8-name/c)
         polars/private/generic/dtype
         polars/private/generic/printing)

(provide (except-out (all-defined-out) dataframe series)
         (contract-out
          [dataframe (-> (listof Series-ptr?) dataframe?)]
          [series (->* ((or/c list? vector?)) (#:name utf-8-name/c #:dtype any/c) series?)]))

(define unset (gensym 'unset))

(define-generics has-ref
  (ref has-ref [key] #:columns [columns] #:rows [rows]))

(define-generics sized
  (len sized))

(define-generics has-shape
  (shape has-shape))

(define-generics has-dtype
  (dtype has-dtype))

(define-generics has-null-count
  (null-count has-null-count))

;; ---------------------------------------------------------------------------
;; the series wrapper

(struct series-rec (ptr)
  #:reflection-name 'series
  #:property prop:cpointer 0                ; marshals as a _Series-ptr
  #:property prop:owned-pointer 0
  #:property prop:custom-write (write-owned 'series series-dropped series->printed)
  #:property prop:sequence in-series
  #:methods gen:has-ref
  [(define (ref s [key unset] #:columns [columns unset] #:rows [rows unset])
     (series-ref* s key columns rows))]
  #:methods gen:sized
  [(define (len s) (series-len s))]
  #:methods gen:has-shape
  [(define (shape s) (list (series-len s)))]
  #:methods gen:has-dtype
  [(define (dtype s) (series-dtype s))]
  #:methods gen:has-null-count
  [(define (null-count s) (series-null-count s))])

(define series? series-rec?)
(define (wrap-series ptr) (series-rec ptr))
(define (null-series? v) (and (series? v) (eq? (series-dtype v) 'null)))

;; ---------------------------------------------------------------------------
;; the dataframe wrapper

(struct dataframe-rec (ptr)
  #:reflection-name 'dataframe
  #:property prop:cpointer 0
  #:property prop:owned-pointer 0
  #:property prop:custom-write
  (write-owned 'dataframe dataframe-dropped
               (lambda (d) (printed-or-placeholder 'dataframe (lambda () (dataframe->string/raw d)))))
  #:methods gen:has-ref
  [(define (ref d [key unset] #:columns [columns unset] #:rows [rows unset])
     (dataframe-ref* d key columns rows))]
  #:methods gen:sized
  [(define (len d) (dataframe-height d))]
  #:methods gen:has-shape
  [(define (shape d)
     (define-values (rows cols) (dataframe-shape d))
     (list rows cols))])

(define (dataframe? v) (dataframe-rec? v))
(define (wrap-dataframe ptr) (dataframe-rec ptr))

(define (frame-columns-problem columns)
  (define heights (map series-len columns))
  (define names (map series-name columns))
  (match* ((for/first ([h (in-list heights)] [n (in-list names)] #:unless (= h (car heights)))
             (list n h))
           (check-duplicates names))
    [((list name height) _)
     (format "could not create a new DataFrame: height of column '~a' (~a) does not match ~a"
             name height (format "height of column '~a' (~a)" (car names) (car heights)))]
    [(#f (? string? name))
     (format "could not create a new DataFrame: column with name '~a' has more than one occurrence"
             name)]
    [(#f #f) #f]))

(define (column-problem present names)
  (cond
    [(for/first ([name (in-list names)] #:unless (member name present)) name)
     => (lambda (name) (format "~s not found" name))]
    [(check-duplicates names) => (lambda (name) (format "~s named more than once" name))]
    [else #f]))

(define (refuse who problem fallback)
  (raise-arguments-error who (or problem fallback)))

(define (dataframe series-list)
  (wrap-dataframe
   (or (dataframe-new/raw series-list)
       (refuse 'dataframe (frame-columns-problem series-list) "could not create a new DataFrame"))))

;; ---------------------------------------------------------------------------
;; the lazyframe wrapper

(struct lazyframe-rec (ptr)
  #:reflection-name 'lazyframe
  #:property prop:cpointer 0
  #:property prop:owned-pointer 0
  #:property prop:custom-write
  (write-owned 'lazyframe lazyframe-dropped (lambda (lf) "#<lazyframe>")))

(define (lazyframe? v) (lazyframe-rec? v))
(define (wrap-lazyframe ptr) (lazyframe-rec ptr))

(define-syntax-parse-rule (define-wrapped name:id wrap:expr reader:expr)
  (define name (procedure-rename (compose1 wrap reader) 'name)))

;; ---------------------------------------------------------------------------
;; dataframe-only accessors (plain functions guarded on dataframe?).

(define (guard-dataframe who d)
  (unless (dataframe? d)
    (error who "expected a dataframe, got ~v" d)))

(define (width d)  (guard-dataframe 'width d)  (dataframe-width d))
(define (height d) (guard-dataframe 'height d) (dataframe-height d))
(define (column-name d i)
  (guard-dataframe 'column-name d)
  (dataframe-column-name d i))
(define (column-names d)
  (guard-dataframe 'column-names d)
  (dataframe-column-names d))

(define (shape/values x) (apply values (shape x)))

;; ---------------------------------------------------------------------------
;; series: keyword constructor with dtype inference (see dtype.rkt)

(define (series elements #:name [name ""] #:dtype [dtype #f])
  (define canonical (if dtype (normalize-dtype dtype) (infer-dtype elements)))
  (check-categorical-values 'series canonical elements)
  (define ctor (dtype->constructor canonical (vector? elements)))
  (wrap-series (ctor name (coerce-elements canonical elements))))

;; ---------------------------------------------------------------------------
;; ref dispatch helpers (referenced by the struct methods above)

(define (series-ref* s key columns rows)
  (unless (eq? columns unset)
    (error 'ref "a series has no columns to select"))
  (unless (eq? rows unset)
    (error 'ref "series row slicing not supported"))
  (when (eq? key unset)
    (error 'ref "ref on a series requires an index"))
  (series-value 'ref s key))

(define (column->name d c)
  (cond
    [(string? c) c]
    [(and (exact-nonnegative-integer? c) (< c (dataframe-width d))) (dataframe-column-name d c)]
    [(exact-nonnegative-integer? c)
     (raise-arguments-error 'ref "column index out of range" "index" c "width" (dataframe-width d))]
    [else (error 'ref "dataframe column selector must be a string or index, got ~v" c)]))

(define (dataframe-ref* d key columns rows)
  (unless (eq? rows unset)
    (error 'ref "dataframe row slicing not yet implemented"))
  (define sel
    (cond
      [(not (eq? columns unset)) columns]
      [(not (eq? key unset)) key]
      [else (error 'ref "ref on a dataframe requires a column key or #:columns")]))
  (cond
    [(list? sel)
     (define names (map (lambda (c) (column->name d c)) sel))
     (wrap-dataframe
      (or (dataframe-select/c d names)
          (refuse 'ref (column-problem (dataframe-column-names d) names)
                  "cannot select the columns")))]
    [else
     (define name (column->name d sel))
     (wrap-series (or (dataframe-column/raw d name) (error 'ref "~s not found" name)))]))

(module+ internal
  (provide dataframe))
