#lang racket/base

(require (only-in ffi/unsafe
                  -> _bytes _double _float _fun _int16 _int32 _int64 _int8 _pointer _size
                  _uint16 _uint32 _uint64 _uint8 ctype-sizeof malloc ptr-ref)
         (only-in ffi/vector
                  _f64vector _s64vector f64vector-length make-f64vector make-s64vector
                  s64vector->cpointer s64vector-length)
         (only-in gregor jdn->date posix->datetime)
         (only-in gregor/time time)
         (only-in racket/match match)
         (only-in threading ~>>)
         (only-in polars/private/foreign
                  _Series-ptr dataframe-column dataframe-column-names dataframe-height
                  define-compat duration-value->period polars-null series-drop
                  series-dtype series-len series-name series-null-count))

(provide dataframe->columns
         dataframe->f64vector
         in-series
         series->f64vector
         series->list
         series->vector)

;; Destinations include GC memory the collector may move: never #:blocking?.
(define-syntax-rule (define-physical-copies name ...)
  (begin
    (define-compat name
      (_fun _Series-ptr _size _size _pointer _size _bytes _size -> _int64))
    ...))

(define-physical-copies
  series-copy-i8 series-copy-i16 series-copy-i32 series-copy-i64
  series-copy-u8 series-copy-u16 series-copy-u32 series-copy-u64
  series-copy-f32 series-copy-f64 series-copy-bool)

(define-compat series-str-byte-len
  (_fun _Series-ptr _size _size -> _int64))

(define-compat series-copy-str
  (_fun (s start count buf offsets valid) ::
        (s : _Series-ptr) (start : _size) (count : _size)
        (buf : _bytes) (_size = (bytes-length buf))
        (offsets : _s64vector) (_size = (s64vector-length offsets))
        (valid : _bytes) (_size = (if valid (bytes-length valid) 0))
        -> _int64))

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

(define (checked who dtype status)
  (when (negative? status)
    (error who "could not copy a series of dtype ~v (status ~a)" dtype status))
  status)

(define (validity s count)
  (and (positive? (series-null-count s)) (make-bytes count)))

(define block-rows 65536)

(define (block-size count)
  (max 1 (min count block-rows)))

(define-syntax-rule (collect-blocks shape start count block fetch! valid null-value value-at)
  (let ()
    (define-syntax-rule (row k)
      (if (and valid (eq? 0 (bytes-ref valid k))) null-value (value-at k)))
    (if (eq? shape 'list)
        (for/fold ([acc '()])
                  ([from (in-range (* block (quotient (sub1 count) block)) -1 (- block))])
          (define m (min block (- count from)))
          (fetch! (+ start from) m)
          (for/fold ([acc acc]) ([k (in-range (sub1 m) -1 -1)])
            (cons (row k) acc)))
        (let ([out (make-vector count)])
          (for ([from (in-range 0 count block)])
            (define m (min block (- count from)))
            (fetch! (+ start from) m)
            (for ([k (in-range m)])
              (vector-set! out (+ from k) (row k))))
          out))))

(define-syntax-rule (physical-rows shape who s dtype start count null-value copy! ctype ->value)
  (let* ([block (block-size count)]
         [dst (malloc block ctype 'atomic-interior)]
         [valid (validity s block)])
    (define (fetch! from m)
      (checked who dtype (copy! s from m dst block valid (if valid block 0))))
    (define-syntax-rule (value-at k) (->value (ptr-ref dst ctype k)))
    (collect-blocks shape start count block fetch! valid null-value value-at)))

(define (string-rows shape who s dtype start count null-value)
  (define block (block-size count))
  (define offsets (make-s64vector (add1 block)))
  (define p (s64vector->cpointer offsets))
  (define valid (validity s block))
  (define buf #"")
  (define (fetch! from m)
    (set! buf (~>> (series-str-byte-len s from m) (checked who dtype) make-bytes))
    (checked who dtype (series-copy-str s from m buf offsets valid)))
  (define-syntax-rule (value-at k)
    (bytes->string/utf-8 buf #f (ptr-ref p _int64 k) (ptr-ref p _int64 (add1 k))))
  (collect-blocks shape start count block fetch! valid null-value value-at))

(define (convertible? dtype)
  (match dtype
    [(or 'int8 'int16 'int32 'int64 'uint8 'uint16 'uint32 'uint64 'float32 'float64
         'boolean 'string 'date 'time 'null
         `(datetime ,_ ,_) `(duration ,_))
     #t]
    [_ #f]))

(define (reject who message field s dtype)
  (raise-arguments-error who message field (series-name s) "dtype" dtype))

(define (rows shape who s dtype start count null-value)
  (define-syntax-rule (physical copy! ctype ->value)
    (physical-rows shape who s dtype start count null-value copy! ctype ->value))
  (match dtype
    ['int8 (physical series-copy-i8 _int8 values)]
    ['int16 (physical series-copy-i16 _int16 values)]
    ['int32 (physical series-copy-i32 _int32 values)]
    ['int64 (physical series-copy-i64 _int64 values)]
    ['uint8 (physical series-copy-u8 _uint8 values)]
    ['uint16 (physical series-copy-u16 _uint16 values)]
    ['uint32 (physical series-copy-u32 _uint32 values)]
    ['uint64 (physical series-copy-u64 _uint64 values)]
    ['float32 (physical series-copy-f32 _float values)]
    ['float64 (physical series-copy-f64 _double values)]
    ['boolean (physical series-copy-bool _uint8 byte->boolean)]
    ['string (string-rows shape who s dtype start count null-value)]
    ['date (physical series-copy-i32 _int32 days->date)]
    ['time (physical series-copy-i64 _int64 nanoseconds->time)]
    [`(datetime ,unit ,_) (physical series-copy-i64 _int64 (epoch->datetime unit))]
    [`(duration ,_)
     (physical series-copy-i64 _int64 (lambda (v) (duration-value->period dtype v)))]
    ['null
     (define-syntax-rule (value-at k) null-value)
     (collect-blocks shape start count (block-size count) void #f null-value value-at)]))

(define (series-rows shape who field s null-value)
  (define dtype (series-dtype s))
  (unless (convertible? dtype)
    (reject who "unsupported dtype" field s dtype))
  (rows shape who s dtype 0 (series-len s) null-value))

(define (series->list s #:null [null-value polars-null])
  (series-rows 'list 'series->list "series" s null-value))

(define (series->vector s #:null [null-value polars-null])
  (series-rows 'vector 'series->vector "series" s null-value))

(define series-chunk-rows 4096)

(define (in-series s #:null [null-value polars-null] #:chunk-rows [chunk-rows series-chunk-rows])
  (define dtype (series-dtype s))
  (unless (convertible? dtype)
    (reject 'in-series "unsupported dtype" "series" s dtype))
  (define n (series-len s))
  (make-do-sequence
   (lambda ()
     (define chunk-start 0)
     (define chunk (vector))
     (define (element i)
       (unless (< (- i chunk-start) (vector-length chunk))
         (set! chunk-start i)
         (set! chunk (rows 'vector 'in-series s dtype i (min chunk-rows (- n i)) null-value)))
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

(define (dataframe->columns d
                            #:columns [names (dataframe-column-names d)]
                            #:null [null-value polars-null])
  (call-with-columns
   'dataframe->columns d names
   (lambda (columns)
     (for ([s (in-list columns)])
       (define dtype (series-dtype s))
       (unless (convertible? dtype)
         (reject 'dataframe->columns "unsupported dtype" "column" s dtype)))
     (for/list ([name (in-list names)] [s (in-list columns)])
       (cons name (series-rows 'vector 'dataframe->columns "column" s null-value))))))

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
                  (for/list ([i (in-range n)]) (series-ref s i))))

  (for ([n (list (sub1 block-rows) block-rows (add1 block-rows) (+ (* 2 block-rows) 5))])
    (define xs (gappy-ints n))
    (define s (series-new-i64 "x" xs))
    (check-equal? (series->list s) xs)
    (check-equal? (series->vector s) (list->vector xs))
    (define strs (gappy-strs n))
    (check-equal? (series->list (series-new-str "s" strs)) strs)))
