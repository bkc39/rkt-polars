#lang racket/base

(require (only-in ffi/unsafe
                  -> _byte _bytes _double _float _fun _int16 _int32 _int64 _int8 _pointer _size
                  _uint16 _uint32 _uint64 _uint8 ptr-add ptr-ref)
         (only-in ffi/unsafe/alloc allocator)
         (only-in ffi/vector _f64vector f64vector-length make-f64vector)
         (only-in racket/match match)
         syntax/parse/define
         (only-in threading ~>>)
         (only-in polars/private/foreign
                  _Series-ptr _Series-ptr/null copy-zoned-datetimes dataframe-column
                  dataframe-column-names dataframe-height decimal-ref define-compat
                  duration-value->period polars-null series-copy-decimal series-copy-i64
                  series-drop series-dtype series-len series-name series-null-count)
         (only-in polars/private/resource with-raw-buffer with-release)
         (only-in polars/private/temporal
                  days->date epoch->datetime epoch->moment nanoseconds->time))

(provide check-column-names
         dataframe->columns
         dataframe->f64vector
         dataframe->hash
         dataframe->rows
         in-dataframe-rows
         in-series
         series->f64vector
         series->list
         series->vector)

;; Validity and string buffers are GC memory the collector may move: never #:blocking?.
(define-syntax-parse-rule (define-copies name:id ...)
  (begin
    (define-compat name
      (_fun _Series-ptr _size _size _pointer _size _bytes _size -> _int64))
    ...))

(define-copies
  series-copy-i8 series-copy-i16 series-copy-i32
  series-copy-u8 series-copy-u16 series-copy-u32 series-copy-u64
  series-copy-f32 series-copy-f64 series-copy-bool)

(define-compat series-str-byte-len
  (_fun _Series-ptr _size _size -> _int64))

(define-compat series-copy-str
  (_fun _Series-ptr _size _size _bytes _size _pointer _size _bytes _size -> _int64))

(define-compat series-copy-cat
  (_fun _Series-ptr _size _size _pointer _size _bytes _size -> _Series-ptr/null)
  #:wrap (allocator series-drop))

(define-compat series-copy-as-f64
  (_fun (s dst offset stride null-value) ::
        (s : _Series-ptr)
        (dst : _f64vector) (_size = (f64vector-length dst))
        (offset : _size) (stride : _size) (null-value : _double)
        -> _int64))

(define (convertible? dtype)
  (match dtype
    [(or 'int8 'int16 'int32 'int64 'uint8 'uint16 'uint32 'uint64 'float32 'float64
         'boolean 'string 'date 'time 'null 'categorical
         `(datetime ,_ ,_) `(duration ,_) `(decimal ,_ ,_) `(enum . ,_))
     #t]
    [_ #f]))

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

(define (has-nulls? s)
  (positive? (series-null-count s)))

(define (valid-len valid)
  (if valid (bytes-length valid) 0))

(define-syntax-parse-rule (collect shape:id count:id valid:id null-value:id i:id element:expr)
  (cond
    [(and (eq? shape 'list) valid)
     (for/fold ([acc '()]) ([i (in-range (sub1 count) -1 -1)])
       (cons (if (eq? 0 (bytes-ref valid i)) null-value element) acc))]
    [(eq? shape 'list)
     (for/fold ([acc '()]) ([i (in-range (sub1 count) -1 -1)])
       (cons element acc))]
    [valid
     (for/vector #:length count ([i (in-range count)])
       (if (eq? 0 (bytes-ref valid i)) null-value element))]
    [else
     (for/vector #:length count ([i (in-range count)])
       element)]))

(define-syntax-parse-rule (with-scratch scratch:expr ([name:id count:expr ctype:expr])
                            body:expr ...+)
  (let ([given scratch]
        [run (lambda (name) body ...)])
    (if given
        (run given)
        (with-raw-buffer ([name count ctype]) (run name)))))

(define-syntax-parse-rule (define-physical-rows name:id ctype:id copy!:id convert:expr)
  (define (name shape who s dtype arg start count valid null-value scratch)
    (with-scratch scratch ([dst count ctype])
      (checked who dtype (copy! s start count dst count valid (valid-len valid)))
      (collect shape count valid null-value i (convert arg (ptr-ref dst ctype i))))))

(define-physical-rows int8-rows _int8 series-copy-i8 (lambda (_ v) v))
(define-physical-rows int16-rows _int16 series-copy-i16 (lambda (_ v) v))
(define-physical-rows int32-rows _int32 series-copy-i32 (lambda (_ v) v))
(define-physical-rows int64-rows _int64 series-copy-i64 (lambda (_ v) v))
(define-physical-rows uint8-rows _uint8 series-copy-u8 (lambda (_ v) v))
(define-physical-rows uint16-rows _uint16 series-copy-u16 (lambda (_ v) v))
(define-physical-rows uint32-rows _uint32 series-copy-u32 (lambda (_ v) v))
(define-physical-rows uint64-rows _uint64 series-copy-u64 (lambda (_ v) v))
(define-physical-rows float32-rows _float series-copy-f32 (lambda (_ v) v))
(define-physical-rows float64-rows _double series-copy-f64 (lambda (_ v) v))
(define-physical-rows boolean-rows _uint8 series-copy-bool (lambda (_ v) (not (eq? 0 v))))
(define-physical-rows date-rows _int32 series-copy-i32 (lambda (_ v) (days->date v)))
(define-physical-rows time-rows _int64 series-copy-i64 (lambda (_ v) (nanoseconds->time v)))
(define-physical-rows datetime-rows _int64 series-copy-i64 epoch->datetime)
(define-physical-rows duration-rows _int64 series-copy-i64 duration-value->period)

(define (zoned-rows shape who s dtype unit zone start count valid null-value scratch)
  (with-scratch scratch ([instants (* 2 count) _int64])
    (define walls (ptr-add instants count _int64))
    (copy-zoned-datetimes who s dtype start count instants walls valid)
    (collect shape count valid null-value i
             (epoch->moment unit (ptr-ref instants _int64 i) (ptr-ref walls _int64 i) zone))))

(define (string-rows shape who s dtype start count valid null-value scratch)
  (define buf (~>> (series-str-byte-len s start count) (checked who dtype) make-bytes))
  (with-scratch scratch ([offsets (add1 count) _int64])
    (checked who dtype (series-copy-str s start count buf (bytes-length buf)
                                        offsets (add1 count) valid (valid-len valid)))
    (collect shape count valid null-value i
             (bytes->string/utf-8 buf #f
                                  (ptr-ref offsets _int64 i)
                                  (ptr-ref offsets _int64 (add1 i))))))

;; A scratch buffer of this many bytes per row, plus one row, holds what any
;; dtype needs: a decimal's two words per row, or a categorical's code per row
;; followed by its table's offsets (the table has at most a row per row).
(define scratch-bytes-per-row 16)

(define (scratch-bytes count)
  (* scratch-bytes-per-row (add1 count)))

(define (codes-bytes count)
  (* 8 (quotient (add1 count) 2)))

(define (categorical-rows shape who s dtype start count valid null-value scratch)
  (with-scratch scratch ([codes count _uint32])
    (with-release ([table (series-copy-cat s start count codes count valid (valid-len valid))
                          series-drop])
      (unless table
        (checked who dtype -1))
      (define names (string-rows 'vector who table 'string 0 (series-len table) #f polars-null
                                 (and scratch (ptr-add scratch (codes-bytes count)))))
      (define symbols (for/vector #:length (vector-length names) ([name (in-vector names)])
                        (string->symbol name)))
      (collect shape count valid null-value i (vector-ref symbols (ptr-ref codes _uint32 i))))))

(define (decimal-rows shape who s dtype scale start count valid null-value scratch)
  (with-scratch scratch ([words (* 2 count) _uint64])
    (checked who dtype (series-copy-decimal s start count words (* 2 count) valid (valid-len valid)))
    (collect shape count valid null-value i (decimal-ref words i scale))))

(define (rows shape who s dtype start count null-value
              #:scratch [scratch #f]
              #:nulls? [nulls? (has-nulls? s)])
  (define valid (and nulls? (make-bytes count)))
  (define (physical typed-rows [arg #f])
    (typed-rows shape who s dtype arg start count valid null-value scratch))
  (match dtype
    ['int8 (physical int8-rows)]
    ['int16 (physical int16-rows)]
    ['int32 (physical int32-rows)]
    ['int64 (physical int64-rows)]
    ['uint8 (physical uint8-rows)]
    ['uint16 (physical uint16-rows)]
    ['uint32 (physical uint32-rows)]
    ['uint64 (physical uint64-rows)]
    ['float32 (physical float32-rows)]
    ['float64 (physical float64-rows)]
    ['boolean (physical boolean-rows)]
    ['date (physical date-rows)]
    ['time (physical time-rows)]
    [`(datetime ,unit #f) (physical datetime-rows unit)]
    [`(datetime ,unit ,zone)
     (zoned-rows shape who s dtype unit zone start count valid null-value scratch)]
    [`(duration ,_) (physical duration-rows dtype)]
    ['string (string-rows shape who s dtype start count valid null-value scratch)]
    [(or 'categorical `(enum . ,_))
     (categorical-rows shape who s dtype start count valid null-value scratch)]
    [`(decimal ,_ ,scale)
     (decimal-rows shape who s dtype scale start count valid null-value scratch)]
    ['null (if (eq? shape 'list)
               (for/list ([_ (in-range count)]) null-value)
               (make-vector count null-value))]))

(define (column->vector who field s null-value)
  (rows 'vector who s (convertible-dtype who field s) 0 (series-len s) null-value))

(define (series->list s #:null [null-value polars-null])
  (define dtype (convertible-dtype 'series->list "series" s))
  (rows 'list 'series->list s dtype 0 (series-len s) null-value))

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
         (set! chunk (rows 'vector 'in-series s dtype i count null-value)))
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
    (unless (hash-ref present name #f)
      (raise-arguments-error who "no such column" "column" name))
    (when (hash-ref seen name #f)
      (raise-arguments-error who "duplicate column" "column" name))
    (hash-set seen name #t)))

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

(define row-buffer-size 512)

(define (frame-rows who d names named? null-value buffer-size)
  (check-column-names who d names)
  (define columns (for/list ([name (in-list names)]) (dataframe-column d name)))
  (define dtypes (for/list ([s (in-list columns)]) (convertible-dtype who "column" s)))
  (define nullable (for/list ([s (in-list columns)]) (has-nulls? s)))
  (define keys (for/list ([name (in-list names)]) (string->immutable-string name)))
  (define width (length columns))
  (define n (dataframe-height d))
  (define (buffer start)
    (define count (min buffer-size (- n start)))
    (with-raw-buffer ([scratch (scratch-bytes count) _byte])
      (for/vector #:length width ([s (in-list columns)]
                                  [dtype (in-list dtypes)]
                                  [nulls? (in-list nullable)])
        (rows 'vector who s dtype start count null-value #:scratch scratch #:nulls? nulls?))))
  (define (row block j)
    (if named?
        (for/hash ([key (in-list keys)] [column (in-vector block)])
          (values key (vector-ref column j)))
        (for/vector #:length width ([column (in-vector block)])
          (vector-ref column j))))
  (make-do-sequence
   (lambda ()
     (define start 0)
     (define block #f)
     (define (element i)
       (unless (and block (< (- i start) buffer-size))
         (set! start i)
         (set! block (buffer i)))
       (row block (- i start)))
     (values element add1 0 (lambda (i) (< i n)) #f #f))))

(define (in-dataframe-rows d
                           #:columns [names (dataframe-column-names d)]
                           #:named? [named? #f]
                           #:null [null-value polars-null]
                           #:buffer-size [buffer-size row-buffer-size])
  (frame-rows 'in-dataframe-rows d names named? null-value buffer-size))

(define (dataframe->rows d
                         #:columns [names (dataframe-column-names d)]
                         #:named? [named? #f]
                         #:null [null-value polars-null])
  (for/list ([row (frame-rows 'dataframe->rows d names named? null-value row-buffer-size)])
    row))

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
           (only-in gregor ->datetime/local ->tzid ->utc-offset datetime)
           (only-in racket/sequence sequence->list)
           (only-in polars/private/foreign
                    dataframe-new polars-null? series-cast series-drop-count series-head
                    series-new-i64 series-new-str series-ref))

  (define (gappy-ints n)
    (for/list ([i (in-range n)])
      (if (memv (modulo i 7) '(0 3)) polars-null (- (* i 1000) 7))))
  (define (gappy-strs n)
    (for/list ([i (in-range n)])
      (if (memv (modulo i 5) '(1 4)) polars-null (make-string (modulo i 4) #\y))))

  (for* ([chunk-rows '(1 2 3 7)]
         [n (list 0 (sub1 chunk-rows) chunk-rows (add1 chunk-rows) (* 2 chunk-rows)
                  (add1 (* 2 chunk-rows)))]
         [s (let ([strs (series-head (series-new-str "x" (gappy-strs (add1 n))) n)])
              (list (series-head (series-new-i64 "x" (gappy-ints (add1 n))) n)
                    strs
                    (series-cast strs 'categorical)
                    (series-cast strs '(enum yyy || yy y))))])
    (define refs (for/list ([i (in-range n)]) (series-ref s i)))
    (check-equal? (sequence->list (in-series s #:chunk-rows chunk-rows)) refs)
    (check-equal? (series->list s) refs))

  (for* ([chunk-rows '(1 3 7)]
         [unit '(milliseconds microseconds nanoseconds)]
         [zone '("Europe/Brussels" "America/New_York" "UTC")])
    (define n 11)
    (define zoned
      (series-cast (series-new-i64 "t" (for/list ([i (in-range n)])
                                         (if (= i 4) polars-null (* (- i 5) 1800000 i))))
                   (list 'datetime unit zone)))
    (define refs (for/list ([i (in-range n)]) (series-ref zoned i)))
    (check-equal? (sequence->list (in-series zoned #:chunk-rows chunk-rows)) refs)
    (check-equal? (series->list zoned) refs)
    (check-equal? (vector->list (series->vector zoned)) refs)
    (check-equal? (for/list ([row (in-dataframe-rows (dataframe-new (list zoned))
                                                     #:buffer-size chunk-rows)])
                    (vector-ref row 0))
                  refs))

  (define (wall-clock v)
    (if (polars-null? v) v (list (->datetime/local v) (->utc-offset v) (->tzid v))))
  (for ([value (list 9223369200000000001 (+ (- (sub1 (expt 2 63))) 3600000000000))]
        [zone '("Asia/Tokyo" "America/New_York")]
        [expected (list (list (datetime 2262 4 12 8 0 0 1) 32400 "Asia/Tokyo")
                        (list (datetime 1677 9 20 20 16 41 145224193) -17762
                              "America/New_York"))])
    (define edge (series-cast (series-new-i64 "t" (list polars-null value))
                              (list 'datetime 'nanoseconds zone)))
    (check-equal? (map wall-clock (series->list edge)) (list polars-null expected))
    (check-equal? (for/list ([row (in-dataframe-rows (dataframe-new (list edge))
                                                     #:buffer-size 1)])
                    (wall-clock (vector-ref row 0)))
                  (list polars-null expected)))

  (define carriers (series-cast (series-new-str "c" '("UA" "AA" "UA")) 'categorical))
  (define (released-by thunk)
    (for ([_ (in-range 4)]) (collect-garbage))
    (define before (series-drop-count))
    (for ([_ (in-range 20)]) (thunk))
    (for ([_ (in-range 4)]) (collect-garbage) (sleep 0.1))
    (- (series-drop-count) before))
  (check >= (released-by (lambda () (series->list carriers))) 20))
