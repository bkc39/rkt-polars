#lang racket/base

;; High-level, "rackety" generic API layered over the monomorphic Series /
;; DataFrame bindings in polars/private/foreign.
;;
;; A Series is a single opaque pointer that already carries its dtype at
;; runtime (see series-dtype in foreign.rkt), so these generics dispatch on
;; that tag rather than introducing a wrapper struct.  The result is one
;; representation everywhere: every value handled here is a raw Series-ptr or
;; DataFrame-ptr, exactly as produced by the rest of the package.
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
         (prefix-in base: racket/base)
         (only-in gregor datetime?)
         polars/private/foreign
         polars/private/series)

(module+ test
  (require rackunit gregor))

(provide series
         describe
         ref
         sum mean min max
         rename rename!
         clone series-clone)

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

(define i32-min (- (expt 2 31)))
(define i32-max (sub1 (expt 2 31)))
(define (fits-i32? n) (<= i32-min n i32-max))

(define (infer-dtype elements)
  (define vals
    (for/list ([x (in-list (if (vector? elements)
                               (vector->list elements)
                               elements))]
               #:unless (polars-null? x))
      x))
  (cond
    [(null? vals) 'int32]                       ; matches series-empty default
    [(andmap boolean? vals) 'boolean]
    [(andmap exact-integer? vals)
     (if (andmap fits-i32? vals) 'int32 'int64)]
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
;; elements may be a list or a vector; nulls are polars-null.
(define (series elements #:name [name ""] #:dtype [dtype #f])
  (define canonical (if dtype (normalize-dtype dtype) (infer-dtype elements)))
  (define ctor (dtype->constructor canonical (vector? elements)))
  (ctor name (coerce-elements canonical elements)))

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
    [(list (? Series-ptr? s)) (series-reduce 'sum sum-table s)]
    [_ (apply base:+ args)]))

(define (mean . args)
  (match args
    [(list (? Series-ptr? s)) (series-reduce 'mean mean-table s)]
    [(list) (error 'mean "expected at least one argument")]
    [_ (/ (apply base:+ args) (length args))]))

(define (min . args)
  (match args
    [(list (? Series-ptr? s)) (series-reduce 'min min-table s)]
    [_ (apply base:min args)]))

(define (max . args)
  (match args
    [(list (? Series-ptr? s)) (series-reduce 'max max-table s)]
    [_ (apply base:max args)]))

;; ---------------------------------------------------------------------------
;; describe / ref: dispatch on series vs dataframe

(define (describe x)
  (cond
    [(Series-ptr? x)
     (printf "name=~s len=~a dtype=~a nulls=~a\n"
             (series-name x) (series-len x)
             (series-dtype x) (series-null-count x))]
    [(DataFrame-ptr? x)
     (define-values (rows cols) (dataframe-shape x))
     (printf "DataFrame shape=(~a ~a)\n" rows cols)
     (for ([nm (in-list (dataframe-column-names x))])
       (printf "  ~a: ~a\n" nm (series-dtype (dataframe-column x nm))))]
    [else (error 'describe "expected a series or dataframe, got ~v" x)]))

;; (ref series index) -> element ; (ref dataframe name-or-index) -> column
;; data-first so it threads naturally: (~> df (ref "col") (ref 0))
(define (ref x key)
  (cond
    [(Series-ptr? x) (series-ref x key)]
    [(DataFrame-ptr? x)
     (cond
       [(string? key) (dataframe-column x key)]
       [(exact-nonnegative-integer? key)
        (dataframe-column x (dataframe-column-name x key))]
       [else (error 'ref "dataframe column key must be a string or index, got ~v" key)])]
    [else (error 'ref "expected a series or dataframe, got ~v" x)]))

;; ---------------------------------------------------------------------------
;; clone / rename

;; series-slice already returns a fresh series, so a full-length slice is a
;; cheap clone that needs no native-lib support.
(define (series-clone s)
  (series-slice s 0 (series-len s)))

(define (clone x)
  (cond
    [(Series-ptr? x) (series-clone x)]
    [else (error 'clone "expected a series, got ~v" x)]))

;; mutating: renames in place, returns void (as is conventional for ! mutators)
(define (rename! x new-name)
  (cond
    [(Series-ptr? x) (series-rename x new-name)]
    [else (error 'rename! "expected a series, got ~v" x)]))

;; non-mutating: returns a renamed copy, leaving the original untouched
(define (rename x new-name)
  (cond
    [(Series-ptr? x)
     (define c (series-clone x))
     (series-rename c new-name)
     c]
    [else (error 'rename "expected a series, got ~v" x)]))

;; ---------------------------------------------------------------------------

(module+ test
  ;; constructor + dtype inference
  (check-equal? (series-dtype (series '(1 2 3) #:dtype 'i32)) 'int32)
  (check-equal? (series-dtype (series '(1 2 3) #:dtype 'int32)) 'int32)
  (check-equal? (series-dtype (series '(1 2 3))) 'int32)
  (check-equal? (series-dtype (series '(1.0 2.0))) 'float64)
  (check-equal? (series-dtype (series '("a" "b"))) 'string)
  (check-equal? (series-dtype (series '(#t #f))) 'boolean)
  (check-equal? (series-dtype (series (list (datetime 2024 1 1)))) '(datetime milliseconds #f))
  (check-equal? (series-dtype (series (vector 1 2 3) #:dtype 'f64)) 'float64)
  (check-equal? (series-name (series '(1 2 3) #:name "xs")) "xs")
  ;; big integers widen to int64
  (check-equal? (series-dtype (series (list (expt 2 40)))) 'int64)

  ;; reductions dispatch on dtype
  (define ints (series '(1 2 3 4) #:name "ints" #:dtype 'i32))
  (define floats (series '(1.5 2.0 4.25 8.0) #:name "floats"))
  (check-equal? (sum ints) 10)
  (check-equal? (max floats) 8.0)
  (check-equal? (min ints) 1)
  ;; mean of ints promotes to float64
  (check-equal? (mean ints) 2.5)
  (check-pred flonum? (mean ints))

  ;; numeric fallback preserves racket/base behaviour
  (check-equal? (max 1 2 3) 3)
  (check-equal? (min 4 2 9) 2)
  (check-equal? (sum 1 2 3) 6)
  (check-equal? (sum) 0)
  (check-equal? (mean 2 4) 3)

  ;; ref on series and dataframe
  (define nullable (series (list 10 polars-null 30) #:name "n" #:dtype 'i32))
  (check-equal? (ref nullable 0) 10)
  (check-equal? (ref nullable 1) polars-null)
  (define df (dataframe-new (list ints floats)))
  (check-equal? (series-name (ref df "floats")) "floats")
  (check-equal? (series-name (ref df 0)) "ints")

  ;; clone / rename / rename!
  (define original (series '(1 2 3) #:name "orig" #:dtype 'i32))
  (define renamed (rename original "copy"))
  (check-equal? (series-name original) "orig")  ; untouched
  (check-equal? (series-name renamed) "copy")
  (check-pred void? (rename! original "mutated"))
  (check-equal? (series-name original) "mutated"))
