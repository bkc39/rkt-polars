#lang racket/base

(require ffi/unsafe
         (only-in gregor/period microseconds milliseconds nanoseconds)
         (only-in racket/contract/base </c ->i and/c any contract-out)
         (only-in racket/provide matching-identifiers-out)
         racket/match
         syntax/parse/define
         (only-in polars/private/c-integer size/c)
         (only-in polars/private/compat-dtype CompatOptBool-valid _CompatOptBool _CompatOptF32
                  _CompatOptF64 _CompatOptI16 _CompatOptI32 _CompatOptI64 _CompatOptI8
                  _CompatOptU16 _CompatOptU32 _CompatOptU64 _CompatOptU8 _CompatOptYMD
                  compat-dtype->datum compat-opt-bool->datum compat-opt-f32->datum
                  compat-opt-f64->datum compat-opt-i16->datum compat-opt-i32->datum
                  compat-opt-i64->datum compat-opt-i8->datum compat-opt-u16->datum
                  compat-opt-u32->datum compat-opt-u64->datum compat-opt-u8->datum polars-null)
         (only-in polars/private/compat-ffi _rsstr define-compat)
         (only-in polars/private/owned Series-ptr? _Series-ptr)
         (only-in polars/private/reason respell)
         (only-in polars/private/series-core series-cast-datetime-tz
                  series-dt-replace-time-zone/raw series-dtype/raw series-len series-time-zone)
         (only-in (submod polars/private/owned internal) series-drop)
         (only-in (submod polars/private/reason internal) call/reason)
         (only-in (submod polars/private/series-core internal) series-strings)
         (only-in (submod polars/private/series-ops internal) series-slice)
         (only-in polars/private/resource with-raw-buffer with-release)
         (only-in polars/private/temporal
                  days->date epoch->datetime epoch->moment nanoseconds->time offset-unit)
         (for-syntax racket/base racket/syntax syntax/parse))

(provide (except-out (all-defined-out)
                     define-copies define-series-refs series-date-ref series-index/c
                     series-ref-bytes series-ref-cat series-ref-str series-ref-string
                     (matching-identifiers-out #rx"^series-ref-.*/raw$" (all-defined-out)))
         (contract-out
          [series-ref-bytes
           (->i ([who symbol?]
                 [s Series-ptr?]
                 [index (s) (and/c exact-nonnegative-integer? (</c (series-len s)))]
                 [limit size/c])
                any)]
          [series-ref-str series-index/c]))

(define-compat series-ref-is-null
  (_fun _Series-ptr _size -> _int32))

(define series-index/c
  (->i ([s Series-ptr?]
        [index (s) (and/c exact-nonnegative-integer? (</c (series-len s)))])
       any))

(define-syntax-parse-rule (define-series-refs [type:id result:expr] ...)
  #:with ((name c-id) ...)
  (for/list ([t (in-list (syntax->list #'(type ...)))])
    (list (format-id t "series-ref-~a/raw" t)
          (format-id t "series_ref_~a" t)))
  (begin
    (define-compat name
      (_fun _Series-ptr _size -> result)
      #:c-id c-id)
    ...
    (provide (contract-out [name series-index/c] ...))))

(define-series-refs
  [i8 _CompatOptI8]
  [i16 _CompatOptI16]
  [i32 _CompatOptI32]
  [i64 _CompatOptI64]
  [u8 _CompatOptU8]
  [u16 _CompatOptU16]
  [u32 _CompatOptU32]
  [u64 _CompatOptU64]
  [f32 _CompatOptF32]
  [f64 _CompatOptF64]
  [bool _CompatOptBool]
  [date _CompatOptYMD]
  [duration _CompatOptI64]
  [time _CompatOptI64])

(define (series-ref-unsupported who dtype)
  (error who "unsupported dtype ~v" dtype))

(define (require-ref-value who dtype value)
  (or value (error who "could not read non-null value for dtype ~v" dtype)))

(define (duration-value->period dtype value)
  (match dtype
    [`(duration nanoseconds) (nanoseconds value)]
    [`(duration microseconds) (microseconds value)]
    [`(duration milliseconds) (milliseconds value)]
    [`(duration ,_) (microseconds value)]
    [_ (error 'series-ref "expected duration dtype, got ~v" dtype)]))

(define-compat series-copy-decimal
  (_fun _Series-ptr _size _size _pointer _size _bytes _size -> _int64))


(define (series-ref-string s index)
  (match (series-strings s index 1)
    [(list value) value]
    [#f #f]))

(define-compat series-ref-cat
  (_fun _Series-ptr _size -> _rsstr))

(define (series-ref-str s index)
  (match (and (eqv? (series-ref-is-null s index) 0) (compat-dtype->datum (series-dtype/raw s)))
    ['string (series-ref-string s index)]
    [(or 'categorical 'enum) (series-ref-cat s index)]
    [_ #f]))

(define-compat series-binary-byte-len
  (_fun _Series-ptr _size _size _size -> _int64))

;; The buffers are GC memory the collector may move: never #:blocking?.
(define-compat series-copy-binary
  (_fun _Series-ptr _size _size _size _bytes _size _pointer _size _pointer _size _bytes _size
        -> _int64))

(define (series-ref-bytes who s index limit)
  (define size (series-binary-byte-len s index 1 limit))
  (define buf (make-bytes (max size 0)))
  (define valid (make-bytes 1))
  (define copied
    (and (not (negative? size))
         (with-raw-buffer ([offsets 2 _int64])
           (series-copy-binary s index 1 limit buf size offsets 2 #f 0 valid 1))))
  (cond
    [(or (not copied) (negative? copied))
     (error who "cannot read a binary value at index ~a" index)]
    [(zero? (bytes-ref valid 0)) polars-null]
    [else buf]))

;; The validity buffers are GC memory the collector may move: never #:blocking?.
(define-syntax-parse-rule (define-copies name:id ...)
  (begin
    (define-compat name
      (_fun _Series-ptr _size _size _pointer _size _bytes _size -> _int64))
    ...))

(define-copies
  series-copy-i8 series-copy-i16 series-copy-i32 series-copy-i64
  series-copy-u8 series-copy-u16 series-copy-u32 series-copy-u64
  series-copy-f32 series-copy-f64 series-copy-bool)

(define ((unreadable-datetime who zone) reason)
  (error who "cannot read a datetime in ~s: ~a" zone (respell reason)))

;; `count` rows of a zoned column from `start`: each UTC instant into
;; `instants`, and into `walls` its wall clock in (offset-unit unit).
(define (copy-zoned-datetimes who s dtype start count instants walls valid
                              #:unreadable [unreadable (unreadable-datetime who (caddr dtype))])
  (match-define (list _ unit zone) dtype)
  (define (copied status)
    (when (negative? status)
      (error who "could not copy a series of dtype ~v (status ~a)" dtype status)))
  (with-release ([rows (series-slice s start count) series-drop]
                 [view (series-cast-datetime-tz who rows (list 'datetime (offset-unit unit) zone))
                       series-drop])
    (define-values (clocks reason)
      (call/reason (lambda () (series-dt-replace-time-zone/raw view #f "raise" "raise")) values))
    (cond
      [clocks
       (with-release ([walls-of clocks series-drop])
         (copied (series-copy-i64 rows 0 count instants count valid
                                  (if valid (bytes-length valid) 0)))
         (copied (series-copy-i64 walls-of 0 count walls count #f 0)))]
      [else (unreadable (or reason "no reason recorded"))])))

(define (series-ref-datetime who s index unit zone unreadable)
  (with-raw-buffer ([value 2 _int64])
    (cond
      [(not zone)
       (and (zero? (series-copy-i64 s index 1 value 1 #f 0))
            (epoch->datetime unit (ptr-ref value _int64 0)))]
      [else
       (let/ec return
         (copy-zoned-datetimes who s (list 'datetime unit zone) index 1
                               value (ptr-add value 1 _int64) #f
                               #:unreadable (if unreadable
                                                (lambda (reason) (return (unreadable reason)))
                                                (unreadable-datetime who zone)))
         (epoch->moment unit (ptr-ref value _int64 0) (ptr-ref value _int64 1) zone))])))

(define (series-date-ref s index)
  (with-raw-buffer ([days 1 _int32])
    (and (zero? (series-copy-i32 s index 1 days 1 #f 0))
         (days->date (ptr-ref days _int32 0)))))

(define (decimal-ref words i scale)
  (/ (+ (ptr-ref words _uint64 (* 2 i))
        (arithmetic-shift (ptr-ref words _int64 (add1 (* 2 i))) 64))
     (expt 10 scale)))

(define (series-ref-decimal s index scale)
  (with-raw-buffer ([words 2 _uint64])
    (and (zero? (series-copy-decimal s index 1 words 2 #f 0))
         (decimal-ref words 0 scale))))

(define (series-ref s index)
  (series-value 'series-ref s index))

(define (series-value who s index #:unreadable [unreadable #f])
  (unless (exact-nonnegative-integer? index)
    (error who "index must be an exact nonnegative integer, got ~v" index))
  (define len (series-len s))
  (unless (< index len)
    (error who "index ~a out of bounds for series of length ~a" index len))
  (case (series-ref-is-null s index)
    [(1) polars-null]
    [(0)
     (define dtype (compat-dtype->datum (series-dtype/raw s)))
     (case dtype
       [(int8) (require-ref-value who dtype (compat-opt-i8->datum (series-ref-i8/raw s index)))]
       [(int16) (require-ref-value who dtype (compat-opt-i16->datum (series-ref-i16/raw s index)))]
       [(int32) (require-ref-value who dtype (compat-opt-i32->datum (series-ref-i32/raw s index)))]
       [(int64) (require-ref-value who dtype (compat-opt-i64->datum (series-ref-i64/raw s index)))]
       [(uint8) (require-ref-value who dtype (compat-opt-u8->datum (series-ref-u8/raw s index)))]
       [(uint16) (require-ref-value who dtype (compat-opt-u16->datum (series-ref-u16/raw s index)))]
       [(uint32) (require-ref-value who dtype (compat-opt-u32->datum (series-ref-u32/raw s index)))]
       [(uint64) (require-ref-value who dtype (compat-opt-u64->datum (series-ref-u64/raw s index)))]
       [(float32) (require-ref-value who dtype (compat-opt-f32->datum (series-ref-f32/raw s index)))]
       [(float64) (require-ref-value who dtype (compat-opt-f64->datum (series-ref-f64/raw s index)))]
       [(boolean)
        (define value (series-ref-bool/raw s index))
        (when (zero? (CompatOptBool-valid value))
          (error who "could not read non-null value for dtype ~v" dtype))
        (compat-opt-bool->datum value)]
       [(string) (require-ref-value who dtype (series-ref-string s index))]
       [(categorical enum)
        (string->symbol (require-ref-value who dtype (series-ref-cat s index)))]
       [(date) (require-ref-value who dtype (series-date-ref s index))]
       [(time)
        (define raw (compat-opt-i64->datum (series-ref-time/raw s index)))
        (require-ref-value who dtype (and raw (nanoseconds->time raw)))]
       [else
        (match dtype
          [`(duration ,_)
           (define raw (compat-opt-i64->datum (series-ref-duration/raw s index)))
           (require-ref-value who dtype (and raw (duration-value->period dtype raw)))]
          [`(datetime ,unit ,zoned)
           (require-ref-value who dtype
                              (series-ref-datetime who s index unit (and zoned (series-time-zone s))
                                                  unreadable))]
          [`(decimal ,_ ,scale) (require-ref-value who dtype (series-ref-decimal s index scale))]
          [_ (series-ref-unsupported who dtype)])])]
    [else (error who "could not read null state at index ~a" index)]))

(module+ internal
  (provide series-ref-bytes series-ref-cat))
