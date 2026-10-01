#lang racket/base

(require racket/generic
         (only-in ffi/unsafe prop:cpointer)
         (only-in polars/private/bulk in-series)
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
  #:property prop:owned-pointer 0
  #:property prop:custom-write
  (lambda (s port mode)
    (write-string (series->string s) port))
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

;; ---------------------------------------------------------------------------
;; the dataframe wrapper

(struct dataframe-rec (ptr)
  #:reflection-name 'dataframe
  #:property prop:cpointer 0
  #:property prop:owned-pointer 0
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
     (define-values (rows cols) (dataframe-shape d))
     (list rows cols))])

(define (dataframe? v) (dataframe-rec? v))
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
  #:property prop:owned-pointer 0
  #:property prop:custom-write
  (lambda (lf port mode) (write-string "#<lazyframe>" port)))

(define (lazyframe? v) (lazyframe-rec? v))
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
  (unless (eq? columns unset)
    (error 'ref "a series has no columns to select"))
  (unless (eq? rows unset)
    (error 'ref "series row slicing not supported"))
  (when (eq? key unset)
    (error 'ref "ref on a series requires an index"))
  (series-ref s key))

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
  (require rackunit (only-in gregor datetime) (only-in racket/sequence sequence->list))
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
  (check-equal? (series-dtype (series (list (datetime 2024 1 1)))) '(datetime microseconds #f))
  (check-equal? (series-dtype (series (vector 1 2 3) #:dtype 'f64)) 'float64)
  (check-exn #rx"series: unsupported dtype '\\(datetime weeks\\)"
             (lambda () (series '(1) #:dtype '(datetime weeks))))
  (check-exn #rx"series: unsupported dtype '\\(datetime microseconds \"UTC\"\\)"
             (lambda () (series '(1) #:dtype '(datetime microseconds "UTC"))))
  (check-equal? (series-name (series '(1 2 3) #:name "xs")) "xs")
  (check-equal? (series-dtype (series (list (expt 2 40)))) 'int64)

  ;; symbols infer a categorical and read back as symbols; strings need #:dtype
  (define dests (series (list 'IAH polars-null 'ATL 'IAH) #:name "dest"))
  (check-equal? (series-dtype dests) 'categorical)
  (check-equal? (for/list ([x dests]) x) (list 'IAH polars-null 'ATL 'IAH))
  (check-equal? (series-dtype (series (vector "a" 'b) #:dtype 'categorical)) 'categorical)
  (check-exn #rx"cannot infer a dtype" (lambda () (series (list 'a "b"))))
  (define levels (series '("info" debug) #:dtype '(enum debug info)))
  (check-equal? (dtype levels) '(enum debug info))
  (check-equal? (ref levels 0) 'info)
  (check-exn #rx"^series: cannot convert to '\\(enum debug info\\): .*\\[\"error\"\\]"
             (lambda () (series '(info error) #:dtype '(enum debug info))))
  (check-exn #rx"unsupported dtype '\\(enum debug debug\\)"
             (lambda () (series '(debug) #:dtype '(enum debug debug))))

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

  (check-true (sequence? withnull))
  (check-equal? (for/list ([x withnull]) x) (list 10 polars-null 30))
  (for ([_ (in-range 2)])
    (check-equal? (sequence->list withnull) (list 10 polars-null 30)))
  (check-false (sequence? frame))

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

(module+ test
  (require (only-in polars/private/expr dataframe-lazy lazyframe-drop))
  (define (settle!)
    (for ([_ (in-range 4)])
      (collect-garbage)
      (sleep 0.1)))
  (define (drops-once count drop make)
    (settle!)
    (define before (count))
    (drop (make))
    (settle!)
    (- (count) before))
  (check-equal? (drops-once series-drop-count series-drop (lambda () (series '(1 2)))) 1)
  (check-equal? (drops-once series-drop-count series-drop
                            (lambda () (wrap-series (wrap-series (series-new-i64 "x" '(1))))))
                1)
  (check-equal? (drops-once dataframe-drop-count dataframe-drop
                            (lambda () (dataframe (list (series '(1 2) #:name "a")))))
                1)
  (check-pred void? (begin (lazyframe-drop (wrap-lazyframe (dataframe-lazy frame)))
                           (settle!))))

(module+ test
  (require (only-in gregor date moment now)
           (only-in gregor/period days hours microseconds milliseconds months nanoseconds weeks)
           (only-in gregor/time time))
  (define (round-trip elements [dtype #f])
    (define s (if dtype (series elements #:dtype dtype) (series elements)))
    (list (series-dtype s) (for/list ([x s]) x)))

  (define ymds (list (date 2013 1 1) polars-null (date -1300 5 23) (date 1969 12 31)))
  (check-equal? (round-trip ymds) (list 'date ymds))
  (check-equal? (round-trip (list->vector ymds)) (list 'date ymds))
  (check-equal? (round-trip ymds 'date) (list 'date ymds))
  (define clocks (list (time 5 6 7 123456789) polars-null (time 0)))
  (check-equal? (round-trip clocks) (list 'time clocks))
  (define stamps (list (datetime 2013 1 1 5 6 7 123456000) polars-null (datetime 1969 12 31 23 59 59)))
  (check-equal? (round-trip stamps) (list '(datetime microseconds #f) stamps))
  (check-equal? (round-trip (list (datetime 2024 1 1 0 0 0 1) (datetime 2024)))
                (list '(datetime nanoseconds #f) (list (datetime 2024 1 1 0 0 0 1) (datetime 2024))))
  (define ns-edges (list (datetime 1677 9 21 0 12 43 145224192)
                        (datetime 2262 4 11 23 47 16 854775807)))
  (check-equal? (round-trip ns-edges) (list '(datetime nanoseconds #f) ns-edges))
  (check-equal? (round-trip (list (datetime 2024 1 1 0 0 0 1500) (datetime 1600 1 1 0 0 0 999)))
                (list '(datetime microseconds #f)
                      (list (datetime 2024 1 1 0 0 0 1000) (datetime 1600 1 1))))
  (check-equal? (series-dtype (series (list (now) (datetime 1600 1 1))))
                '(datetime microseconds #f))
  (check-equal? (round-trip (list (datetime 2013 1 1 5 6 7 123456789) (datetime 1600 1 1)))
                (list '(datetime microseconds #f)
                      (list (datetime 2013 1 1 5 6 7 123456000) (datetime 1600 1 1))))
  (check-equal? (round-trip (list (datetime 1995 10 16 9 30 0 123456789) (datetime 1995 11 1)))
                (list '(datetime nanoseconds #f)
                      (list (datetime 1995 10 16 9 30 0 123456789) (datetime 1995 11 1))))
  (check-equal? (round-trip (list (datetime 1995 10 16 9 30 0 123456789) (datetime 1600 1 1)))
                (list '(datetime microseconds #f)
                      (list (datetime 1995 10 16 9 30 0 123456000) (datetime 1600 1 1))))
  (check-equal? (round-trip stamps 'datetime) (list '(datetime microseconds #f) stamps))
  (check-equal? (round-trip (list (datetime 1969 12 31 23 59 59 999500000))
                            '(datetime milliseconds))
                (list '(datetime milliseconds #f) (list (datetime 1969 12 31 23 59 59 999000000))))
  (check-equal? (round-trip (list (hours 1) polars-null (milliseconds -1500)))
                (list '(duration microseconds)
                      (list (microseconds 3600000000) polars-null (microseconds -1500000))))
  (check-equal? (round-trip (list (nanoseconds 1500) (days 1)))
                (list '(duration nanoseconds)
                      (list (nanoseconds 1500) (nanoseconds 86400000000000))))
  (check-equal? (round-trip (list (nanoseconds -1500) (weeks -20000)))
                (list '(duration microseconds)
                      (list (microseconds -1) (microseconds (* -20000 7 86400 1000000)))))
  (check-equal? (round-trip (list (milliseconds 1500)) '(duration milliseconds))
                (list '(duration milliseconds) (list (milliseconds 1500))))
  (check-equal? (round-trip (list polars-null) 'date) (list 'date (list polars-null)))

  (check-exn #rx"cannot infer a dtype" (lambda () (series (list (date 2024 1 2) (datetime 2024)))))
  (check-exn #rx"cannot infer a dtype" (lambda () (series (list (months 1)))))
  (check-exn #rx"^series: a moment carries a time zone"
             (lambda () (series (list (moment 2024 1 2 #:tz "Europe/Paris")))))
  (check-exn #rx"^series: a moment carries a time zone"
             (lambda () (series (list (moment 2024 1 2 #:tz "UTC")) #:dtype 'datetime)))
  (check-exn #rx"^series: expected a gregor date for this dtype\n  dtype: 'date\n  value: \"2024-01-02\""
             (lambda () (series '("2024-01-02") #:dtype 'date)))
  (check-exn #rx"^series: expected a gregor period without years or months"
             (lambda () (series (list (months 1)) #:dtype '(duration microseconds))))
  (check-exn #rx"^series: value out of range for this dtype"
             (lambda () (series (list (datetime 1500)) #:dtype '(datetime nanoseconds #f)))))
