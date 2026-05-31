#lang racket/base

;; High-level, "rackety" generic API layered over the monomorphic Series /
;; DataFrame bindings in polars/private/foreign.
;;
;; A series is exposed as a wrapper struct (the `series` predicate is `series?`)
;; rather than the raw FFI pointer.  The struct carries `prop:cpointer`, so a
;; wrapped series still marshals transparently as a `_Series-ptr` through every
;; existing binding (series-dtype, series-sum-i32, dataframe-new, …); we only
;; pay for the wrapper at the boundary.  It also carries `prop:custom-write`, so
;; a series prints in the REPL the way Polars prints it.  The underlying pointer
;; is deliberately not part of the public series API.
;;
;; The dataframe is exposed the same way: a `dataframe` wrapper struct
;; (`dataframe?`) with prop:cpointer + a Polars-table prop:custom-write, built by
;; the smart `dataframe` constructor.
;;
;; Dispatch uses small, purpose-named racket/generic interfaces:
;;   gen:describable    — (describe x)        series, dataframe
;;   gen:has-ref        — (ref x [key] #:columns ...)  series, dataframe
;;   gen:sized          — (len x)             series (#elements), dataframe (height)
;;   gen:has-shape      — (shape x)           series (n), dataframe (rows cols)
;;   gen:has-dtype      — (dtype x)           series
;;   gen:has-null-count — (null-count x)      series
;; Both wrappers implement the interfaces they have a capability for via
;; #:methods.  Dataframe-only metadata (width, height, column-name(s)) are plain
;; guarded functions.
;;
;; Naming convention: a trailing `!` marks an operation that mutates its
;; argument in place (rename!); the un-suffixed form returns a fresh value
;; (rename, via clone).
;;
;; dtype promotion lattice
;; -----------------------
;; series-dtype returns canonical symbols (int8 int16 int32 int64, uint8 ..
;; uint64, float32 float64, boolean, string, date, time, (datetime ..)).
;; Reductions follow a simple, documented rule:
;;   * sum / min / max  preserve the input dtype.
;;   * mean             always returns float64 (the underlying series-mean-*
;;                      bindings compute in double precision regardless of the
;;                      input integer/float width), so (mean ints) is a flonum.
;; The widening order from narrow to wide is:
;;   int8 < int16 < int32 < int64        (signed)
;;   uint8 < uint16 < uint32 < uint64     (unsigned)
;;   any integer < float32 < float64      (to floating point, used by mean)
;; Casts between dtypes are performed with series-cast.

(require racket/match
         racket/generic
         racket/list
         racket/string
         (only-in ffi/unsafe prop:cpointer)
         (prefix-in base: racket/base)
         (only-in gregor datetime?)
         polars/private/foreign
         polars/private/series)

(module+ test
  (require rackunit gregor))

(provide series series? series->string
         dataframe dataframe?
         describe ref
         len shape dtype null-count
         width height column-name column-names
         gen:describable describable?
         gen:has-ref has-ref?
         gen:sized sized?
         gen:has-shape has-shape?
         gen:has-dtype has-dtype?
         gen:has-null-count has-null-count?
         sum mean min max
         rename rename! clone series-clone)

;; ---------------------------------------------------------------------------
;; generic interfaces
;;
;; Small, purpose-named capability interfaces (per the project's
;; "name capability generics, not catch-alls" rule).  Some are genuinely
;; cross-type (a series and a dataframe both have a `len` and a `shape`);
;; others have a single implementor today but are named so a future type
;; (e.g. an expression) can join without a rename.

;; sentinel for "argument not supplied" in ref's optional positional/keyword args
(define unset (gensym 'unset))

;; describe: print a one-line summary for a series, a shape + per-column dtype
;; summary for a dataframe.
(define-generics describable
  (describe describable))

;; ref: index a series (returns the element) or slice columns out of a
;; dataframe.  Data-first, so it threads.  See series-ref* / dataframe-ref*.
(define-generics has-ref
  (ref has-ref [key] #:columns [columns] #:rows [rows]))

;; len: number of elements (series) / number of rows (dataframe).
(define-generics sized
  (len sized))

;; shape: (values n) for a series, (values rows cols) for a dataframe.
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
  ;; marshals as a _Series-ptr wherever the FFI expects one
  #:property prop:cpointer 0
  ;; prints like a Polars series
  #:property prop:custom-write
  (lambda (s port mode)
    (write-string (series->string s) port))
  #:methods gen:describable
  [(define (describe s) (describe-series s))]
  #:methods gen:has-ref
  [(define (ref s [key unset] #:columns [columns unset] #:rows [rows unset])
     (series-ref* s key columns rows))]
  #:methods gen:sized
  [(define (len s) (series-len s))]
  #:methods gen:has-shape
  [(define (shape s) (series-len s))]
  #:methods gen:has-dtype
  [(define (dtype s) (series-dtype s))]
  #:methods gen:has-null-count
  [(define (null-count s) (series-null-count s))])

(define series? series-rec?)
(define (wrap-series ptr) (series-rec ptr))

;; ---------------------------------------------------------------------------
;; the dataframe wrapper
;;
;; Mirrors the series wrapper: carries prop:cpointer (so it still marshals as a
;; _DataFrame-ptr through every dataframe-* binding) and prop:custom-write (so a
;; dataframe prints in Polars' table format under display / ~a, with no need for
;; a separate display-dataframe).

(struct dataframe-rec (ptr)
  #:reflection-name 'dataframe
  #:property prop:cpointer 0
  #:property prop:custom-write
  (lambda (d port mode)
    (write-string (dataframe->string d) port))
  #:methods gen:describable
  [(define (describe d) (describe-dataframe d))]
  #:methods gen:has-ref
  [(define (ref d [key unset] #:columns [columns unset] #:rows [rows unset])
     (dataframe-ref* d key columns rows))]
  #:methods gen:sized
  [(define (len d) (dataframe-height d))]
  #:methods gen:has-shape
  [(define (shape d) (dataframe-shape d))])

(define dataframe? dataframe-rec?)
(define (wrap-dataframe ptr) (dataframe-rec ptr))

;; smart constructor: wraps dataframe-new (which accepts series wrappers, since
;; they marshal as _Series-ptr).  Keep the raw dataframe-new as the low-level API.
(define (dataframe series-list)
  (wrap-dataframe (dataframe-new series-list)))

;; dataframe-only accessors.  Only one tabular type exists today, so these are
;; plain functions guarded on dataframe?; promote to a gen:tabular capability if
;; a second tabular type (e.g. a lazyframe wrapper) appears.
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

;; ---------------------------------------------------------------------------
;; dtype aliases
;;
;; Accept both the short constructor spellings (i32, f64, str, bool) and the
;; canonical symbols returned by series-dtype (int32, float64, string,
;; boolean).  Maps everything to a canonical symbol.

(define dtype-aliases
  (hash 'i8 'int8    'int8 'int8
        'i16 'int16   'int16 'int16
        'i32 'int32   'int32 'int32
        'i64 'int64   'int64 'int64
        'u8 'uint8    'uint8 'uint8
        'u16 'uint16  'uint16 'uint16
        'u32 'uint32  'uint32 'uint32
        'u64 'uint64  'uint64 'uint64
        'f32 'float32 'float32 'float32
        'f64 'float64 'float64 'float64
        'bool 'boolean 'boolean 'boolean
        'str 'string   'string 'string
        'date 'date
        'time 'time
        'datetime 'datetime))

(define (normalize-dtype dt)
  (cond
    [(and (symbol? dt) (hash-ref dtype-aliases dt #f)) => values]
    [(and (pair? dt) (memq (car dt) '(datetime duration))) dt]
    [else (error 'series "unsupported dtype ~v" dt)]))

;; ---------------------------------------------------------------------------
;; series: keyword constructor with dtype inference

(define (infer-dtype elements)
  (define vals
    (for/list ([x (in-list (if (vector? elements)
                               (vector->list elements)
                               elements))]
               #:unless (polars-null? x))
      x))
  ;; Defaults mirror Polars' inference for a Python list: integers -> Int64,
  ;; reals -> Float64, strings -> String, booleans -> Boolean.
  (cond
    [(null? vals) 'int64]
    [(andmap boolean? vals) 'boolean]
    [(andmap exact-integer? vals) 'int64]
    [(andmap real? vals) 'float64]              ; mixed int/float -> float64
    [(andmap string? vals) 'string]
    [(andmap datetime? vals) 'datetime]
    [else (error 'series
                 "cannot infer a dtype from elements; pass #:dtype explicitly")]))

(define (dtype->constructor canonical vec?)
  (case canonical
    [(int8)    (if vec? series-new-i8/vec  series-new-i8)]
    [(int16)   (if vec? series-new-i16/vec series-new-i16)]
    [(int32)   (if vec? series-new-i32/vec series-new-i32)]
    [(int64)   (if vec? series-new-i64/vec series-new-i64)]
    [(uint8)   (if vec? series-new-u8/vec  series-new-u8)]
    [(uint16)  (if vec? series-new-u16/vec series-new-u16)]
    [(uint32)  (if vec? series-new-u32/vec series-new-u32)]
    [(uint64)  (if vec? series-new-u64/vec series-new-u64)]
    [(float32) (if vec? series-new-f32/vec series-new-f32)]
    [(float64) (if vec? series-new-f64/vec series-new-f64)]
    [(boolean) (if vec? series-new-bool/vec series-new-bool)]
    [(string)  (if vec? series-new-str/vec series-new-str)]
    [else
     (match canonical
       [(or 'datetime `(datetime . ,_))
        (if vec? series-new-datetime/vec series-new-datetime)]
       [_ (error 'series "no constructor for dtype ~v" canonical)])]))

;; The float constructors want flonums; accept exact reals too by coercing,
;; so (series '(1 2 3) #:dtype 'f64) does what the user means.
(define (coerce-elements canonical elements)
  (case canonical
    [(float32 float64)
     (define (->fl x) (if (and (not (polars-null? x)) (exact? x))
                          (exact->inexact x)
                          x))
     (if (vector? elements)
         (for/vector #:length (vector-length elements) ([x (in-vector elements)]) (->fl x))
         (map ->fl elements))]
    [else elements]))

;; (series elements #:name "n" #:dtype 'i32)
;; elements may be a list or a vector; nulls are polars-null.  Returns a series.
(define (series elements #:name [name ""] #:dtype [dtype #f])
  (define canonical (if dtype (normalize-dtype dtype) (infer-dtype elements)))
  (define ctor (dtype->constructor canonical (vector? elements)))
  (wrap-series (ctor name (coerce-elements canonical elements))))

;; ---------------------------------------------------------------------------
;; dtype-dispatched reductions

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

;; sum / mean / min / max are generic: on a series they reduce (dispatching on
;; dtype); on anything else they fall back to the numeric racket/base
;; behaviour, so requiring polars does not break (max 1 2 3) or (sum) etc.

(define (sum . args)
  (match args
    [(list (? series? s)) (series-reduce 'sum sum-table s)]
    [_ (apply base:+ args)]))

(define (mean . args)
  (match args
    [(list (? series? s)) (series-reduce 'mean mean-table s)]
    [(list) (error 'mean "expected at least one argument")]
    [_ (/ (apply base:+ args) (length args))]))

(define (min . args)
  (match args
    [(list (? series? s)) (series-reduce 'min min-table s)]
    [_ (apply base:min args)]))

(define (max . args)
  (match args
    [(list (? series? s)) (series-reduce 'max max-table s)]
    [_ (apply base:max args)]))

;; ---------------------------------------------------------------------------
;; describe / ref helpers (used by the generic methods above)

(define (describe-series s)
  (printf "name=~s len=~a dtype=~a nulls=~a\n"
          (series-name s) (series-len s)
          (series-dtype s) (series-null-count s)))

(define (describe-dataframe d)
  (define-values (rows cols) (dataframe-shape d))
  (printf "DataFrame shape=(~a ~a)\n" rows cols)
  (for ([nm (in-list (dataframe-column-names d))])
    (printf "  ~a: ~a\n" nm (series-dtype (dataframe-column d nm)))))

;; ref dispatch for a series: positional index only.
(define (series-ref* s key columns rows)
  (cond
    [(not (eq? columns unset)) (error 'ref "a series has no columns to select")]
    [(not (eq? rows unset)) (error 'ref "series row slicing not supported")]
    [(eq? key unset) (error 'ref "ref on a series requires an index")]
    [else (series-ref s key)]))

;; ref dispatch for a dataframe: column selection (by name or index) via either
;; a positional key or #:columns.  A single selector returns a wrapped series; a
;; list of selectors returns a wrapped dataframe (a column-projected slice).
;; Row slicing (#:rows) is reserved but not yet implemented.
(define (column->name d c)
  (cond
    [(string? c) c]
    [(exact-nonnegative-integer? c) (dataframe-column-name d c)]
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
     (wrap-dataframe (dataframe-select d (map (lambda (c) (column->name d c)) sel)))]
    [else (wrap-series (dataframe-column d (column->name d sel)))]))

;; ---------------------------------------------------------------------------
;; clone / rename

;; series-slice already returns a fresh series, so a full-length slice is a
;; cheap clone that needs no native-lib support.
(define (series-clone s)
  (wrap-series (series-slice s 0 (series-len s))))

(define (clone x)
  (cond
    [(series? x) (series-clone x)]
    [else (error 'clone "expected a series, got ~v" x)]))

;; mutating: renames in place, returns void (as is conventional for ! mutators)
(define (rename! x new-name)
  (cond
    [(series? x) (series-rename x new-name)]
    [else (error 'rename! "expected a series, got ~v" x)]))

;; non-mutating: returns a renamed copy, leaving the original untouched
(define (rename x new-name)
  (cond
    [(series? x)
     (define c (series-clone x))
     (series-rename c new-name)
     c]
    [else (error 'rename "expected a series, got ~v" x)]))

;; ---------------------------------------------------------------------------
;; Polars-style printing

(define (dtype->polars-label dt)
  (define (tu->label tu)
    (case tu
      [(milliseconds) "ms"]
      [(microseconds) "us"]
      [(nanoseconds)  "ns"]
      [else (format "~a" tu)]))
  (cond
    [(symbol? dt)
     (case dt
       [(int8) "i8"] [(int16) "i16"] [(int32) "i32"] [(int64) "i64"]
       [(uint8) "u8"] [(uint16) "u16"] [(uint32) "u32"] [(uint64) "u64"]
       [(float32) "f32"] [(float64) "f64"]
       [(string) "str"] [(boolean) "bool"]
       [(date) "date"] [(time) "time"]
       [else (format "~a" dt)])]
    [(and (pair? dt) (eq? (car dt) 'datetime))
     (format "datetime[~a]" (tu->label (cadr dt)))]
    [(and (pair? dt) (eq? (car dt) 'duration))
     (format "duration[~a]" (tu->label (cadr dt)))]
    [else (format "~a" dt)]))

(define (value->cell v)
  (cond
    [(polars-null? v) "null"]
    [(string? v) (format "~s" v)]      ; quoted, like Polars
    [else (format "~a" v)]))

;; Polars shows at most ~10 rows: the first 5, an ellipsis, then the last 5.
(define (row-indices len)
  (if (<= len 10)
      (range len)
      (append (range 0 5) (list 'ellipsis) (range (- len 5) len))))

(define (series->string s)
  (define len (series-len s))
  (define lines
    (for/list ([i (in-list (row-indices len))])
      (if (eq? i 'ellipsis)
          "\t…"
          (string-append "\t" (value->cell (series-ref s i))))))
  (string-append
   (format "shape: (~a,)\n" len)
   (format "Series: '~a' [~a]\n" (series-name s) (dtype->polars-label (series-dtype s)))
   "[\n"
   (string-join lines "\n")
   "\n]"))

;; ---------------------------------------------------------------------------

(module+ test
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

  ;; reductions dispatch on dtype
  (define ints (series '(1 2 3 4) #:name "ints" #:dtype 'i32))
  (define floats (series '(1.5 2.0 4.25 8.0) #:name "floats"))
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

  ;; Polars-style printing
  (check-true (regexp-match? #rx"shape: \\(4,\\)" (series->string ints)))
  (check-true (regexp-match? #rx"Series: 'ints' \\[i32\\]" (series->string ints)))
  (check-equal? (format "~a" ints) (series->string ints))   ; custom-write
  ;; null and truncation
  (define big (series (range 100) #:dtype 'i64))
  (check-true (regexp-match? #rx"…" (series->string big)))
  (define withnull (series (list 10 polars-null 30) #:dtype 'i32))
  (check-true (regexp-match? #rx"null" (series->string withnull)))

  ;; ref on series and dataframe; df ref returns a wrapped series
  (check-equal? (ref withnull 0) 10)
  (check-equal? (ref withnull 1) polars-null)
  (define df (dataframe (list ints floats)))   ; accepts series wrappers
  (check-pred series? (ref df "floats"))
  (check-pred series? (ref df 0))
  (check-equal? (series-name (ref df "floats")) "floats")
  (check-equal? (series-name (ref df 0)) "ints")

  ;; clone / rename / rename!
  (define original (series '(1 2 3) #:name "orig" #:dtype 'i32))
  (define renamed (rename original "copy"))
  (check-pred series? renamed)
  (check-equal? (series-name original) "orig")  ; untouched
  (check-equal? (series-name renamed) "copy")
  (check-pred void? (rename! original "mutated"))
  (check-equal? (series-name original) "mutated")

  ;; series capability generics
  (check-equal? (len floats) 4)
  (check-equal? (shape floats) 4)
  (check-equal? (dtype ints) 'int32)
  (check-equal? (null-count withnull) 1)

  ;; dataframe wrapper
  (define users (series '("alice" "bob" "carol") #:name "user"))
  (define sc (series '(10 25 18) #:name "score" #:dtype 'i32))
  (define cost (series '(1.2 3.5 2.0) #:name "cost"))
  (define frame (dataframe (list users sc cost)))
  (check-pred dataframe? frame)
  (check-false (dataframe? sc))

  ;; shape / len / width / height / column metadata
  (check-equal? (call-with-values (lambda () (shape frame)) list) '(3 3))
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

  ;; custom-write prints the Polars table; describe works on the wrapper
  (check-true (regexp-match? #rx"shape: \\(3, 3\\)" (format "~a" frame)))
  (check-pred void? (describe frame))
  (check-pred void? (describe sc)))
