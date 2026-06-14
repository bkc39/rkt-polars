#lang racket/base

;; The wrapper core: the series / dataframe wrapper structs, their capability
;; generics (ref / len / shape / dtype / null-count), the smart constructors,
;; the dataframe accessors, and ref dispatch.  `describe` is NOT a struct method
;; (it's a plain function in describe.rkt that reuses the public reductions);
;; keeping it out of the struct is what lets reductions depend on this core
;; without a cycle.

(require racket/generic
         (only-in ffi/unsafe prop:cpointer)
         polars/private/foreign
         polars/private/generic/dtype
         polars/private/generic/printing)

(provide (all-defined-out))

;; sentinel for "argument not supplied" in ref's optional positional/keyword args
(define unset (gensym 'unset))

;; ---------------------------------------------------------------------------
;; capability generics (small, purpose-named; per "name capability generics").

;; ref: index a series (returns the element) or slice columns out of a
;; dataframe.  Data-first, so it threads.  See series-ref* / dataframe-ref*.
(define-generics has-ref
  (ref has-ref [key] #:columns [columns] #:rows [rows]))

;; len: number of elements (series) / number of rows (dataframe).
(define-generics sized
  (len sized))

;; shape: (n) for a series, (rows cols) for a dataframe.
(define-generics has-shape
  (shape has-shape))

;; dtype: a series' element dtype (canonical symbol).
(define-generics has-dtype
  (dtype has-dtype))

;; null-count: number of null entries in a series.
(define-generics has-null-count
  (null-count has-null-count))

;; ---------------------------------------------------------------------------
;; the series wrapper

(struct series-rec (ptr)
  #:reflection-name 'series
  #:property prop:cpointer 0                ; marshals as a _Series-ptr
  #:property prop:custom-write
  (lambda (s port mode)
    (write-string (series->string s) port))
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

;; ---------------------------------------------------------------------------
;; the dataframe wrapper

(struct dataframe-rec (ptr)
  #:reflection-name 'dataframe
  #:property prop:cpointer 0
  #:property prop:custom-write
  (lambda (d port mode)
    (write-string (dataframe->string d) port))
  #:methods gen:has-ref
  [(define (ref d [key unset] #:columns [columns unset] #:rows [rows unset])
     (dataframe-ref* d key columns rows))]
  #:methods gen:sized
  [(define (len d) (dataframe-height d))]
  #:methods gen:has-shape
  [(define (shape d)
     (let-values ([(rows cols) (dataframe-shape d)])
       (list rows cols)))])

(define dataframe? dataframe-rec?)
(define (wrap-dataframe ptr) (dataframe-rec ptr))

;; smart constructor: wraps dataframe-new (which accepts series wrappers, since
;; they marshal as _Series-ptr).  Keep the raw dataframe-new as the low-level API.
(define (dataframe series-list)
  (wrap-dataframe (dataframe-new series-list)))

;; ---------------------------------------------------------------------------
;; the lazyframe wrapper
;;
;; A lazyframe is a deferred query plan, not a materialized table, so (unlike the
;; series/dataframe wrappers) it has no len/shape/ref/dtype — you build a plan
;; with the data-first verbs and run it with `collect`.  prop:cpointer lets it
;; marshal as a _LazyFrame-ptr through the lazyframe-* bindings.

(struct lazyframe-rec (ptr)
  #:reflection-name 'lazyframe
  #:property prop:cpointer 0
  #:property prop:custom-write
  (lambda (lf port mode) (write-string "#<lazyframe>" port)))

(define lazyframe? lazyframe-rec?)
(define (wrap-lazyframe ptr) (lazyframe-rec ptr))

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

;; csv round-trip, prefix-free (Polars' df.write_csv / pl.read_csv).
(define (write-csv d path)
  (guard-dataframe 'write-csv d)
  (dataframe-write-csv d path))
(define (read-csv path)
  (wrap-dataframe (dataframe-read-csv path)))

;; parquet round-trip (Polars' df.write_parquet / pl.read_parquet).
(define (write-parquet d path)
  (guard-dataframe 'write-parquet d)
  (dataframe-write-parquet d path))
(define (read-parquet path)
  (wrap-dataframe (dataframe-read-parquet path)))

;; newline-delimited JSON / JSON Lines (Polars' df.write_ndjson / pl.read_ndjson).
(define (write-ndjson d path)
  (guard-dataframe 'write-ndjson d)
  (dataframe-write-json-lines d path))
(define (read-ndjson path)
  (wrap-dataframe (dataframe-read-json-lines path)))

;; shape as a list (examples); shape/values is the multiple-values variant.
(define (shape/values x) (apply values (shape x)))

;; ---------------------------------------------------------------------------
;; series: keyword constructor with dtype inference (see dtype.rkt)

;; (series elements #:name "n" #:dtype 'i32)
;; elements may be a list or a vector; nulls are polars-null.  Returns a series.
(define (series elements #:name [name ""] #:dtype [dtype #f])
  (define canonical (if dtype (normalize-dtype dtype) (infer-dtype elements)))
  (define ctor (dtype->constructor canonical (vector? elements)))
  (wrap-series (ctor name (coerce-elements canonical elements))))

;; ---------------------------------------------------------------------------
;; ref dispatch helpers (referenced by the struct methods above)

;; ref for a series: positional index only.
(define (series-ref* s key columns rows)
  (cond
    [(not (eq? columns unset)) (error 'ref "a series has no columns to select")]
    [(not (eq? rows unset)) (error 'ref "series row slicing not supported")]
    [(eq? key unset) (error 'ref "ref on a series requires an index")]
    [else (series-ref s key)]))

;; a dataframe column selector, as a name.
(define (column->name d c)
  (cond
    [(string? c) c]
    [(exact-nonnegative-integer? c) (dataframe-column-name d c)]
    [else (error 'ref "dataframe column selector must be a string or index, got ~v" c)]))

;; ref for a dataframe: a single selector -> wrapped series; a list -> wrapped
;; dataframe (column-projected slice).  Row slicing (#:rows) is reserved.
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
     (wrap-dataframe (dataframe-select d (map (lambda (c) (column->name d c)) sel)))]
    [else (wrap-series (dataframe-column d (column->name d sel)))]))

(module+ test
  ;; fixtures are inline here: core can't require test-fixtures (which requires
  ;; core) without a compile-time cycle.
  (require rackunit racket/file (only-in gregor datetime))
  (define ints (series '(1 2 3 4) #:name "ints" #:dtype 'i32))
  (define floats (series '(1.5 2.0 4.25 8.0) #:name "floats"))
  (define withnull (series (list 10 polars-null 30) #:dtype 'i32))
  (define frame
    (dataframe (list (series '("alice" "bob" "carol") #:name "user")
                     (series '(10 25 18) #:name "score" #:dtype 'i32)
                     (series '(1.2 3.5 2.0) #:name "cost"))))

  ;; series custom-write goes through series->string
  (check-equal? (format "~a" ints) (series->string ints))

  ;; constructor returns a series wrapper; series? distinguishes it
  (check-pred series? (series '(1 2 3)))
  (check-false (series? 5))
  (check-false (series? '(1 2 3)))

  ;; dtype inference + alias parity
  (check-equal? (series-dtype (series '(1 2 3) #:dtype 'i32)) 'int32)
  (check-equal? (series-dtype (series '(1 2 3) #:dtype 'int32)) 'int32)
  (check-equal? (series-dtype (series '(1 2 3))) 'int64)   ; Polars default
  (check-equal? (series-dtype (series '(1.0 2.0))) 'float64)
  (check-equal? (series-dtype (series '("a" "b"))) 'string)
  (check-equal? (series-dtype (series '(#t #f))) 'boolean)
  (check-equal? (series-dtype (series (list (datetime 2024 1 1)))) '(datetime milliseconds #f))
  (check-equal? (series-dtype (series (vector 1 2 3) #:dtype 'f64)) 'float64)
  (check-equal? (series-name (series '(1 2 3) #:name "xs")) "xs")
  (check-equal? (series-dtype (series (list (expt 2 40)))) 'int64)

  ;; ref on series and dataframe; df ref returns a wrapped series
  (check-equal? (ref withnull 0) 10)
  (check-equal? (ref withnull 1) polars-null)
  (define df (dataframe (list ints floats)))
  (check-pred series? (ref df "floats"))
  (check-pred series? (ref df 0))
  (check-equal? (series-name (ref df "floats")) "floats")
  (check-equal? (series-name (ref df 0)) "ints")

  ;; series capability generics
  (check-equal? (len floats) 4)
  (check-equal? (shape floats) '(4))
  (check-equal? (call-with-values (lambda () (shape/values floats)) list) '(4))
  (check-equal? (dtype ints) 'int32)
  (check-equal? (null-count withnull) 1)

  ;; dataframe wrapper + shape / len / width / height / column metadata
  (check-pred dataframe? frame)
  (check-false (dataframe? ints))
  (check-equal? (shape frame) '(3 3))
  (check-equal? (call-with-values (lambda () (shape/values frame)) list) '(3 3))
  (check-equal? (len frame) 3)
  (check-equal? (height frame) 3)
  (check-equal? (width frame) 3)
  (check-equal? (column-name frame 0) "user")
  (check-equal? (column-names frame) '("user" "score" "cost"))

  ;; csv round-trip: write-csv -> read-csv preserves shape + column names
  (define csv-tmp (make-temporary-file "rkt-polars-test-~a.csv"))
  (write-csv frame csv-tmp)
  (define frame-rt (read-csv csv-tmp))
  (check-pred dataframe? frame-rt)
  (check-equal? (shape frame-rt) '(3 3))
  (check-equal? (column-names frame-rt) '("user" "score" "cost"))
  (delete-file csv-tmp)

  ;; parquet + ndjson round-trips preserve shape + column names
  (define pq-tmp (make-temporary-file "rkt-polars-test-~a.parquet"))
  (write-parquet frame pq-tmp)
  (check-equal? (shape (read-parquet pq-tmp)) '(3 3))
  (check-equal? (column-names (read-parquet pq-tmp)) '("user" "score" "cost"))
  (delete-file pq-tmp)
  (define nd-tmp (make-temporary-file "rkt-polars-test-~a.jsonl"))
  (write-ndjson frame nd-tmp)
  (check-equal? (shape (read-ndjson nd-tmp)) '(3 3))
  (delete-file nd-tmp)

  ;; ref: single column (positional or #:columns) -> series; list -> dataframe
  (check-pred series? (ref frame "score"))
  (check-pred series? (ref frame #:columns "score"))
  (check-pred series? (ref frame #:columns 1))
  (check-equal? (dtype (ref frame #:columns "score")) 'int32)
  (define projected (ref frame #:columns '("user" "cost")))
  (check-pred dataframe? projected)
  (check-equal? (width projected) 2)
  (check-equal? (column-names projected) '("user" "cost"))

  ;; row slicing is reserved, not yet implemented
  (check-exn exn:fail? (lambda () (ref frame #:rows 0)))

  ;; custom-write prints the Polars table
  (check-true (regexp-match? #rx"shape: \\(3, 3\\)" (format "~a" frame))))
