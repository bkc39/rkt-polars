#lang racket/base

(require ffi/unsafe
         ffi/unsafe/alloc
         (only-in racket/contract/base [-> ->/c] contract-out)
         (only-in racket/provide matching-identifiers-out)
         syntax/parse/define
         (only-in polars/private/c-integer size/c)
         (only-in polars/private/compat-opt polars-null?)
         (only-in polars/private/compat-ffi _c-string define-compat)
         (only-in polars/private/owned Series-ptr? _Series-ptr/null)
         (only-in polars/private/reason call/foreign-error call/polars-reason)
         (only-in (submod polars/private/owned internal) series-drop)
         (only-in (submod polars/private/series-core internal) named)
         (only-in polars/private/resource utf-8-name/c with-raw-buffer)
         (for-syntax racket/base racket/syntax syntax/parse))

(provide (except-out (all-defined-out)
                     bool/null->u8 new-series new-series/valid series-new-null strings->series
                     vector-has-null?
                     (matching-identifiers-out
                      #rx"^series-new-(?:[iu](?:8|16|32|64)|f32|f64|bool|str)(?:/vec)?$"
                      (all-defined-out)))
         (contract-out
          [series-new-null (->/c utf-8-name/c size/c Series-ptr?)]))

(define-syntax-parse-rule (provide-series-constructors [from-list:id from-vector:id] ...)
  (provide (contract-out [from-list (->/c utf-8-name/c list? Series-ptr?)] ...
                         [from-vector (->/c utf-8-name/c vector? Series-ptr?)] ...)))

(provide-series-constructors [series-new-i8 series-new-i8/vec] [series-new-i16 series-new-i16/vec]
                             [series-new-i32 series-new-i32/vec] [series-new-i64 series-new-i64/vec]
                             [series-new-u8 series-new-u8/vec] [series-new-u16 series-new-u16/vec]
                             [series-new-u32 series-new-u32/vec] [series-new-u64 series-new-u64/vec]
                             [series-new-f32 series-new-f32/vec] [series-new-f64 series-new-f64/vec]
                             [series-new-bool series-new-bool/vec]
                             [series-new-str series-new-str/vec])

(define (values+valid input-values default-value)
  (for/lists (clean-values valid)
             ([value input-values])
    (if (polars-null? value)
        (values default-value 0)
        (values value 1))))

(define (contains-polars-null? values)
  (ormap polars-null? values))

(define (vector-has-null? xs)
  (for/or ([x (in-vector xs)])
    (polars-null? x)))

(define (new-series who name make)
  ((named who name) (call/polars-reason who make)))

(define (new-series/valid who name xs default opt-raw)
  (define-values (clean valid) (values+valid xs default))
  (new-series who name (lambda () (opt-raw clean valid))))

(define-syntax-parse-rule (define-series-constructors rs-type:id ctype:id default-value:expr)
  #:with list-constructor-name (format-id #'rs-type "series-new-~a" #'rs-type)
  #:with vector-constructor-name (format-id #'rs-type
                                            "series-new-~a/vec"
                                            #'rs-type)
  #:with list-constructor-raw-name (format-id #'rs-type "series-new-~a/raw" #'rs-type)
  #:with vector-constructor-raw-name (format-id #'rs-type
                                                "series-new-~a/vec/raw"
                                                #'rs-type)
  #:with opt-constructor-name (format-id #'rs-type "series-new-~a/opt/raw" #'rs-type)
  #:with rust-id (format-id #'rs-type "series_new_~a_v2" #'rs-type)
  #:with rust-opt-id (format-id #'rs-type "series_new_opt_~a_v2" #'rs-type)
  (begin
    (define-compat list-constructor-raw-name
      (_fun (v : (_list i ctype))
            (_size = (length v))
            -> _Series-ptr/null)
      #:c-id rust-id
      #:wrap (allocator series-drop))
    (define-compat vector-constructor-raw-name
      (_fun (v : (_vector i ctype))
            (_size = (vector-length v))
            -> _Series-ptr/null)
      #:c-id rust-id
      #:wrap (allocator series-drop))
    (define-compat opt-constructor-name
      (_fun (v : (_list i ctype))
            (valid : (_list i _uint8))
            (_size = (length v))
            -> _Series-ptr/null)
      #:c-id rust-opt-id
      #:wrap (allocator series-drop))
    (define (list-constructor-name name xs)
      (if (contains-polars-null? xs)
          (new-series/valid 'list-constructor-name name xs default-value opt-constructor-name)
          (new-series 'list-constructor-name name (lambda () (list-constructor-raw-name xs)))))
    (define (vector-constructor-name name xs)
      (if (vector-has-null? xs)
          (new-series/valid 'vector-constructor-name name (vector->list xs) default-value
                            opt-constructor-name)
          (new-series 'vector-constructor-name name
                      (lambda () (vector-constructor-raw-name xs)))))))

(define-series-constructors i32 _int32 0)

(define-series-constructors i8 _int8 0)
(define-series-constructors i16 _int16 0)

(define-series-constructors f64 _double 0.0)

(define-series-constructors f32 _float 0.0)

(define-series-constructors i64 _int64 0)

(define-series-constructors u32 _uint32 0)

(define-series-constructors u8 _uint8 0)
(define-series-constructors u16 _uint16 0)

(define-series-constructors u64 _uint64 0)

(define-compat series-new-bool/raw
  (_fun (v : (_list i _uint8))
        (_size = (length v))
        -> _Series-ptr/null)
  #:c-id series_new_bool_v2
  #:wrap (allocator series-drop))

(define-compat series-new-bool/vec/raw
  (_fun (v : (_vector i _uint8))
        (_size = (vector-length v))
        -> _Series-ptr/null)
  #:c-id series_new_bool_v2
  #:wrap (allocator series-drop))

(define-compat series-new-bool/opt/raw
  (_fun (v : (_list i _uint8))
        (valid : (_list i _uint8))
        (_size = (length v))
        -> _Series-ptr/null)
  #:c-id series_new_opt_bool_v2
  #:wrap (allocator series-drop))

(define (bool->u8 b) (if b 1 0))

(define (bool/null->u8 b)
  (if (polars-null? b) b (bool->u8 b)))

(define (series-new-bool name bools)
  (if (contains-polars-null? bools)
      (new-series/valid 'series-new-bool name (map bool/null->u8 bools) 0 series-new-bool/opt/raw)
      (new-series 'series-new-bool name (lambda () (series-new-bool/raw (map bool->u8 bools))))))

(define (series-new-bool/vec name bools)
  (cond
    [(vector-has-null? bools)
     (new-series/valid 'series-new-bool/vec name (map bool/null->u8 (vector->list bools)) 0
                       series-new-bool/opt/raw)]
    [else
     (define u8s
       (for/vector #:length (vector-length bools) ([b (in-vector bools)])
         (bool->u8 b)))
     (new-series 'series-new-bool/vec name (lambda () (series-new-bool/vec/raw u8s)))]))

(define-compat series-new-null/raw
  (_fun _size -> _Series-ptr/null)
  #:c-id series_new_null_v2
  #:wrap (allocator series-drop))

(define (series-new-null name length)
  (new-series 'series-new-null name (lambda () (series-new-null/raw length))))

(define-compat series-new-str/raw
  (_fun (_c-string = "") _bytes _size _pointer _size _bytes _size -> _Series-ptr/null)
  #:c-id series_new_str_packed
  #:wrap (allocator series-drop))

;; One UTF-8 buffer and row offsets, not a list of C strings: the collector
;; moves strings while such a list is filled (#143).
(define (strings->series who name strings)
  (define count (length strings))
  (define valid (and (contains-polars-null? strings) (make-bytes count 1)))
  (with-raw-buffer ([offsets (add1 count) _int64])
    (ptr-set! offsets _int64 0 0)
    (define size
      (for/fold ([end 0]) ([s (in-list strings)] [row (in-naturals)])
        (define next
          (cond
            [(string? s) (+ end (string-utf-8-length s))]
            [(polars-null? s) (bytes-set! valid row 0) end]
            [else (raise-argument-error who "(or/c string? polars-null?)" s)]))
        (ptr-set! offsets _int64 (add1 row) next)
        next))
    (define buf (make-bytes size))
    (for/fold ([end 0]) ([s (in-list strings)] #:when (string? s))
      (define utf-8 (string->bytes/utf-8 s))
      (bytes-copy! buf end utf-8)
      (+ end (bytes-length utf-8)))
    ((named who name)
     (call/foreign-error
      who
      (lambda () (series-new-str/raw buf size offsets (add1 count) valid (if valid count 0)))
      "operation failed"))))

(define (series-new-str name strings)
  (strings->series 'series-new-str name strings))

(define (series-new-str/vec name strings)
  (strings->series 'series-new-str/vec name (vector->list strings)))

(define-cstruct _YMDHMS
  ([year _int]
   [month _uint32]
   [day _uint32]
   [hour _uint32]
   [minute _uint32]
   [sescond _uint32]))

(define default-ymdhms (make-YMDHMS 1970 1 1 0 0 0))

(define-series-constructors ymdhms _YMDHMS default-ymdhms)

(module+ internal
  (provide series-new-null strings->series))
