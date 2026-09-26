#lang racket/base

(require (only-in ffi/unsafe
                  -> _bytes _double _float _fun _int16 _int32 _int64 _int8 _pointer _size
                  _uint16 _uint32 _uint64 _uint8 free malloc ptr-ref)
         (only-in ffi/unsafe/alloc allocator deallocator)
         (only-in ffi/vector _f64vector f64vector-length make-f64vector)
         (only-in gregor jdn->date posix->datetime)
         (only-in gregor/time time)
         (only-in racket/match match match-define)
         (only-in syntax/parse/define define-syntax-parse-rule)
         (for-syntax (only-in syntax/parse id))
         (only-in threading ~>>)
         (only-in polars/private/foreign
                  _Series-ptr dataframe-column dataframe-column-names dataframe-height
                  define-compat duration-value->period polars-null series-drop
                  series-dtype series-len series-name series-null-count))

(provide check-column-names
         dataframe->columns
         dataframe->f64vector
         dataframe->hash
         in-series
         series->f64vector
         series->list
         series->vector)

;; Validity and string buffers are GC memory the collector may move: never #:blocking?.
(define free-buffer ((deallocator) free))
(define alloc-buffer
  ((allocator free-buffer) (lambda (count ctype) (malloc (max count 1) ctype 'raw))))

(define-syntax-parse-rule (define-copies name:id ...)
  (begin
    (define-compat name
      (_fun _Series-ptr _size _size _pointer _size _bytes _size -> _int64))
    ...))

(define-copies
  series-copy-i8 series-copy-i16 series-copy-i32 series-copy-i64
  series-copy-u8 series-copy-u16 series-copy-u32 series-copy-u64
  series-copy-f32 series-copy-f64 series-copy-bool)

(define-compat series-str-byte-len
  (_fun _Series-ptr _size _size -> _int64))

(define-compat series-copy-str
  (_fun _Series-ptr _size _size _bytes _size _pointer _size _bytes _size -> _int64))

(define-compat series-copy-as-f64
  (_fun (s dst offset stride null-value) ::
        (s : _Series-ptr)
        (dst : _f64vector) (_size = (f64vector-length dst))
        (offset : _size) (stride : _size) (null-value : _double)
        -> _int64))

(define unix-epoch-jdn 2440588)

(define (days->date days)
  (jdn->date (+ days unix-epoch-jdn)))

(define (per-second unit)
  (case unit
    [(nanoseconds) 1000000000]
    [(microseconds) 1000000]
    [else 1000]))

(define ((epoch->datetime unit) value)
  (define k (per-second unit))
  (posix->datetime (quotient (- value (modulo value k)) k)))

(define (nanoseconds->time value)
  (define-values (seconds nanosecond) (quotient/remainder value 1000000000))
  (define-values (minutes second) (quotient/remainder seconds 60))
  (define-values (hour minute) (quotient/remainder minutes 60))
  (time hour minute second nanosecond))

(define (byte->boolean b)
  (not (eq? 0 b)))

(struct layout (ctype read copy!))

(define i8 (layout _int8 (lambda (p i) (ptr-ref p _int8 i)) series-copy-i8))
(define i16 (layout _int16 (lambda (p i) (ptr-ref p _int16 i)) series-copy-i16))
(define i32 (layout _int32 (lambda (p i) (ptr-ref p _int32 i)) series-copy-i32))
(define i64 (layout _int64 (lambda (p i) (ptr-ref p _int64 i)) series-copy-i64))
(define u8 (layout _uint8 (lambda (p i) (ptr-ref p _uint8 i)) series-copy-u8))
(define u16 (layout _uint16 (lambda (p i) (ptr-ref p _uint16 i)) series-copy-u16))
(define u32 (layout _uint32 (lambda (p i) (ptr-ref p _uint32 i)) series-copy-u32))
(define u64 (layout _uint64 (lambda (p i) (ptr-ref p _uint64 i)) series-copy-u64))
(define f32 (layout _float (lambda (p i) (ptr-ref p _float i)) series-copy-f32))
(define f64 (layout _double (lambda (p i) (ptr-ref p _double i)) series-copy-f64))
(define bool (layout _uint8 (lambda (p i) (ptr-ref p _uint8 i)) series-copy-bool))

(define (layout-of dtype)
  (match dtype
    ['int8 (values i8 values)]
    ['int16 (values i16 values)]
    ['int32 (values i32 values)]
    ['int64 (values i64 values)]
    ['uint8 (values u8 values)]
    ['uint16 (values u16 values)]
    ['uint32 (values u32 values)]
    ['uint64 (values u64 values)]
    ['float32 (values f32 values)]
    ['float64 (values f64 values)]
    ['boolean (values bool byte->boolean)]
    ['date (values i32 days->date)]
    ['time (values i64 nanoseconds->time)]
    [`(datetime ,unit ,_) (values i64 (epoch->datetime unit))]
    [`(duration ,_) (values i64 (lambda (v) (duration-value->period dtype v)))]
    [_ (values #f #f)]))

(define (convertible? dtype)
  (define-values (kind _convert) (layout-of dtype))
  (or (memq dtype '(string null)) kind))

(define (checked who dtype status)
  (when (negative? status)
    (error who "could not copy a series of dtype ~v (status ~a)" dtype status))
  status)

(define (reject who message field s dtype)
  (raise-arguments-error who message field (series-name s) "dtype" dtype))

(define (convertible-dtype who field s)
  (define dtype (series-dtype s))
  (unless (convertible? dtype)
    (reject who "unsupported dtype" field s dtype))
  dtype)

(define (validity s count)
  (and (positive? (series-null-count s)) (make-bytes count)))

(define (valid-len valid)
  (if valid (bytes-length valid) 0))

(define (call-with-strings who s dtype start count valid null-value proc)
  (define buf (~>> (series-str-byte-len s start count) (checked who dtype) make-bytes))
  (define offsets (alloc-buffer (add1 count) _int64))
  (checked who dtype (series-copy-str s start count buf (bytes-length buf)
                                      offsets (add1 count) valid (valid-len valid)))
  (define (row i)
    (if (and valid (eq? 0 (bytes-ref valid i)))
        null-value
        (bytes->string/utf-8 buf #f (ptr-ref offsets _int64 i) (ptr-ref offsets _int64 (add1 i)))))
  (begin0 (proc row) (free-buffer offsets)))

(define (call-with-physical who s dtype start count valid null-value proc)
  (define-values (kind convert) (layout-of dtype))
  (match-define (layout ctype read copy!) kind)
  (define dst (alloc-buffer count ctype))
  (checked who dtype (copy! s start count dst count valid (valid-len valid)))
  (define (row i)
    (if (and valid (eq? 0 (bytes-ref valid i)))
        null-value
        (convert (read dst i))))
  (begin0 (proc row) (free-buffer dst)))

(define (call-with-rows who s dtype start count null-value proc)
  (define valid (validity s count))
  (case dtype
    [(null) (proc (lambda (i) null-value))]
    [(string) (call-with-strings who s dtype start count valid null-value proc)]
    [else (call-with-physical who s dtype start count valid null-value proc)]))

(define (column->vector who field s null-value)
  (define n (series-len s))
  (call-with-rows who s (convertible-dtype who field s) 0 n null-value
                  (lambda (row) (build-vector n row))))

(define (series->list s #:null [null-value polars-null])
  (define n (series-len s))
  (call-with-rows 'series->list s (convertible-dtype 'series->list "series" s) 0 n null-value
                  (lambda (row)
                    (for/fold ([acc '()]) ([i (in-range (sub1 n) -1 -1)])
                      (cons (row i) acc)))))

(define (series->vector s #:null [null-value polars-null])
  (column->vector 'series->vector "series" s null-value))

(define series-chunk-rows 4096)

(define (in-series s #:null [null-value polars-null] #:chunk-rows [chunk-rows series-chunk-rows])
  (define dtype (convertible-dtype 'in-series "series" s))
  (define n (series-len s))
  (make-do-sequence
   (lambda ()
     (define chunk-start 0)
     (define chunk (vector))
     (define (element i)
       (unless (< (- i chunk-start) (vector-length chunk))
         (define count (min chunk-rows (- n i)))
         (set! chunk-start i)
         (set! chunk (call-with-rows 'in-series s dtype i count null-value
                                     (lambda (row) (build-vector count row)))))
       (vector-ref chunk (- i chunk-start)))
     (values element add1 0 (lambda (i) (< i n)) #f #f))))

(define (f64-convertible? dtype)
  (and (memq dtype '(int8 int16 int32 int64 uint8 uint16 uint32 uint64 float32 float64
                     boolean null))
       #t))

(define (check-f64-convertible who message field s)
  (define dtype (series-dtype s))
  (unless (f64-convertible? dtype)
    (reject who message field s dtype)))

(define (copy-as-f64! who field s dst offset stride null-value)
  (define fill (if (eq? null-value 'error) +nan.0 (real->double-flonum null-value)))
  (define first-null
    (checked who (series-dtype s) (series-copy-as-f64 s dst offset stride fill)))
  (when (and (eq? null-value 'error) (< first-null (series-len s)))
    (raise-arguments-error who "null value" field (series-name s) "row" first-null)))

(define (series->f64vector s #:null [null-value +nan.0])
  (check-f64-convertible 'series->f64vector "not a numeric series" "series" s)
  (define out (make-f64vector (series-len s)))
  (copy-as-f64! 'series->f64vector "series" s out 0 1 null-value)
  out)

(define (check-column-names who d names)
  (define present (for/hash ([name (in-list (dataframe-column-names d))]) (values name #t)))
  (for/fold ([seen (hash)] #:result (void)) ([name (in-list names)])
    (cond
      [(not (hash-ref present name #f))
       (raise-arguments-error who "no such column" "column" name)]
      [(hash-ref seen name #f)
       (raise-arguments-error who "duplicate column" "column" name)]
      [else (hash-set seen name #t)])))

(define (call-with-columns who d names proc)
  (check-column-names who d names)
  (define fetched '())
  (dynamic-wind
   void
   (lambda ()
     (for ([name (in-list names)])
       (set! fetched (cons (dataframe-column d name) fetched)))
     (proc (reverse fetched)))
   (lambda () (for-each series-drop fetched))))

(define (frame-columns who d names null-value)
  (call-with-columns
   who d names
   (lambda (columns)
     (for-each (lambda (s) (convertible-dtype who "column" s)) columns)
     (for/list ([name (in-list names)] [s (in-list columns)])
       (cons name (column->vector who "column" s null-value))))))

(define (dataframe->columns d
                            #:columns [names (dataframe-column-names d)]
                            #:null [null-value polars-null])
  (frame-columns 'dataframe->columns d names null-value))

(define (dataframe->hash d
                         #:columns [names (dataframe-column-names d)]
                         #:null [null-value polars-null])
  (make-immutable-hash (frame-columns 'dataframe->hash d names null-value)))

(define (dataframe->f64vector d
                              #:columns [names (dataframe-column-names d)]
                              #:order [order 'fortran]
                              #:null [null-value +nan.0])
  (define who 'dataframe->f64vector)
  (call-with-columns
   who d names
   (lambda (columns)
     (for ([s (in-list columns)])
       (check-f64-convertible who "not a numeric column" "column" s))
     (define nrows (dataframe-height d))
     (define ncols (length names))
     (define out (make-f64vector (* nrows ncols)))
     (for ([s (in-list columns)] [j (in-naturals)])
       (define-values (offset stride)
         (if (eq? order 'fortran)
             (values (* j nrows) 1)
             (values j ncols)))
       (copy-as-f64! who "column" s out offset stride null-value))
     (values out nrows ncols))))

(module+ test
  (require rackunit
           (only-in racket/sequence sequence->list)
           (only-in polars/private/foreign series-head series-new-i64 series-new-str series-ref))

  (define (gappy-ints n)
    (for/list ([i (in-range n)])
      (if (memv (modulo i 7) '(0 3)) polars-null (- (* i 1000) 7))))
  (define (gappy-strs n)
    (for/list ([i (in-range n)])
      (if (memv (modulo i 5) '(1 4)) polars-null (make-string (modulo i 4) #\y))))

  (for* ([chunk-rows '(1 2 3 7)]
         [n (list 0 (sub1 chunk-rows) chunk-rows (add1 chunk-rows) (* 2 chunk-rows)
                  (add1 (* 2 chunk-rows)))]
         [s (list (series-head (series-new-i64 "x" (gappy-ints (add1 n))) n)
                  (series-head (series-new-str "x" (gappy-strs (add1 n))) n))])
    (check-equal? (sequence->list (in-series s #:chunk-rows chunk-rows))
                  (for/list ([i (in-range n)]) (series-ref s i)))))
