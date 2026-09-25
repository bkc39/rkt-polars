#lang racket/base

(require racket/contract/base
         (only-in ffi/vector f64vector?)
         (only-in polars/private/bulk
                  dataframe->columns dataframe->f64vector in-series
                  series->f64vector series->list series->vector)
         (only-in polars/private/generic/core dataframe? series?))

(provide
 (contract-out
  [series->list (->* (series?) (#:null any/c) list?)]
  [series->vector (->* (series?) (#:null any/c) vector?)]
  [series->f64vector (->* (series?) (#:null (or/c real? 'error)) f64vector?)]
  [in-series (->* (series?) (#:null any/c) sequence?)]
  [dataframe->columns
   (->* (dataframe?)
        (#:columns (listof string?) #:null any/c)
        (listof (cons/c string? vector?)))]
  [dataframe->f64vector
   (->* (dataframe?)
        (#:columns (listof string?) #:order (or/c 'fortran 'c) #:null (or/c real? 'error))
        (values f64vector? exact-nonnegative-integer? exact-nonnegative-integer?))]))

(module+ test
  (require rackunit
           racket/match
           (only-in ffi/vector f64vector->list f64vector-length f64vector-ref)
           (only-in racket/contract exn:fail:contract:blame?)
           (only-in racket/dict in-dict)
           (only-in racket/list append-map)
           (only-in racket/sequence sequence->list)
           (prefix-in contracted: (submod ".."))
           polars/private/generic/core
           (only-in polars/private/foreign polars-null polars-null? series-drop-count series-name)
           (only-in polars/private/generic/reshape cast head rename slice vstack)
           (only-in polars/private/generic/test-fixtures frame withnull)
           (only-in threading ~>))

  (random-seed 88)

  (define (big) (for/fold ([a 0]) ([_ 3]) (+ (* a 4294967087) (random 4294967087))))
  (define (int-in lo hi) (+ lo (modulo (big) (- hi lo -1))))
  (define (sample edges draw)
    (append edges (for/list ([_ 40]) (if (< (random) 0.3) polars-null (draw)))))
  (define (ints lo hi) (sample (list lo hi 0) (lambda () (int-in lo hi))))
  (define (all-null dtype)
    (~> (list polars-null polars-null) (series #:dtype 'int64) (cast dtype)))

  (define int-dtypes
    `((int8 -128 127) (int16 -32768 32767) (int32 ,(- (expt 2 31)) ,(sub1 (expt 2 31)))
      (int64 ,(- (expt 2 63)) ,(sub1 (expt 2 63)))
      (uint8 0 255) (uint16 0 65535) (uint32 0 ,(sub1 (expt 2 32)))
      (uint64 0 ,(sub1 (expt 2 64)))))
  (define int-series
    (for/list ([spec (in-list int-dtypes)])
      (match-define (list dtype lo hi) spec)
      (series (ints lo hi) #:dtype dtype #:name "x")))
  (define float-series
    (list (series (sample (list -0.0 +inf.0 -inf.0 +nan.0 5e-324 1.7976931348623157e308)
                          (lambda () (* (- (random) 0.5) 1e9)))
                  #:dtype 'float64 #:name "x")
          (series (sample (list 0.1 -0.0 +inf.0 -inf.0 +nan.0 3.4028234663852886e38)
                          (lambda () (* (- (random) 0.5) 1e3)))
                  #:dtype 'float32 #:name "x")))
  (define (epoch-range unit)
    (case unit
      [(milliseconds) (values -62167219200000 253402300799999)]
      [(microseconds) (values -62167219200000000 253402300799999999)]
      [else (values (- (expt 2 62)) (expt 2 62))]))
  (define temporal-series
    (append
     (list (~> (ints -719528 2932896) (series #:dtype 'int32 #:name "x") (cast 'date))
           (~> (ints 0 86399999999999) (series #:dtype 'int64 #:name "x") (cast 'time)))
     (for*/list ([unit '(milliseconds microseconds nanoseconds)] [kind '(datetime duration)])
       (define-values (lo hi) (epoch-range unit))
       (~> (append (list -1 -1500 1500) (ints lo hi))
           (series #:dtype 'int64 #:name "x")
           (cast (list kind unit))))))
  (define other-series
    (list (series (sample (list #t #f) (lambda () (< (random) 0.5))) #:name "x")
          (series (sample (list "" "héllo" "日本語" "😀" (make-string 10000 #\z))
                          (lambda () (number->string (big) 16)))
                  #:name "x")
          (all-null 'null)))
  (define base-series (append int-series float-series temporal-series other-series))

  (define (two-chunks s)
    (define f (dataframe (list (rename s "c"))))
    (ref (vstack f f) "c"))
  (define (variants s)
    (list s (head s 0) (slice s 3 (max 0 (- (len s) 5))) (two-chunks s)
          (all-null (dtype s))))
  (define all-variants (append-map variants base-series))

  (define (ref-list s v)
    (for/list ([i (in-range (len s))])
      (define x (ref s i))
      (if (polars-null? x) v x)))

  (for* ([s (in-list all-variants)] [v (list polars-null 'missing)])
    (define expected (ref-list s v))
    (check-equal? (series->list s #:null v) expected (format "~s" (dtype s)))
    (check-equal? (series->vector s #:null v) (list->vector expected))
    (check-equal? (sequence->list (in-series s #:null v)) expected))
  (for ([s (in-list all-variants)])
    (check-equal? (sequence->list s) (ref-list s polars-null)))
  (check-false (~> frame (ref "user") series->vector immutable?))

  (define numeric-variants
    (filter (lambda (s)
              (memq (dtype s)
                    '(int8 int16 int32 int64 uint8 uint16 uint32 uint64 float32 float64)))
            all-variants))
  (define (f64s s [v +nan.0])
    (~> s (series->f64vector #:null v) f64vector->list))
  (for* ([s (in-list numeric-variants)] [v (list +nan.0 0 -1.5 +inf.0)])
    (check-equal? (f64s s v)
                  (for/list ([x (in-list (ref-list s 'n))])
                    (if (eq? x 'n) (real->double-flonum v) (exact->inexact x)))))
  (check-equal? (~> (list (add1 (expt 2 53))) series f64s) '(9007199254740992.0))
  (check-equal? (~> (list (sub1 (expt 2 64))) (series #:dtype 'uint64) f64s)
                '(1.8446744073709552e19))
  (check-equal? (~> (list (- (expt 2 63))) series f64s) '(-9.223372036854776e18))
  (check-equal? (~> '(0.1) (series #:dtype 'float32) f64s) '(0.10000000149011612))
  (check-equal? (f64s (all-null 'null)) '(+nan.0 +nan.0))
  (check-equal? (~> (list #t #f polars-null) series f64s) '(1.0 0.0 +nan.0))

  (define (null-error who field name row)
    (regexp (format "^~a: null value\n  ~a: \"~a\"\n  row: ~a$" who field name row)))
  (check-exn (null-error "series->f64vector" "series" "x" 1)
             (lambda ()
               (~> (list 1 polars-null 3) (series #:name "x") (series->f64vector #:null 'error))))
  (for ([row '(0 2 4)])
    (define xs (for/list ([i 5]) (if (= i row) polars-null i)))
    (check-exn (null-error "series->f64vector" "series" "x" row)
               (lambda () (series->f64vector (series xs #:name "x") #:null 'error))))
  (define second-chunk-null
    (~> (dataframe (list (series '(1 2 3) #:name "x")))
        (vstack (dataframe (list (series (list 4 polars-null 6) #:name "x"))))
        (ref "x")))
  (check-exn (null-error "series->f64vector" "series" "x" 4)
             (lambda () (series->f64vector second-chunk-null #:null 'error)))
  (define gappy (series (list 1 2 3 polars-null 5) #:name "x"))
  (check-exn (null-error "series->f64vector" "series" "x" 1)
             (lambda () (~> gappy (slice 2 3) (series->f64vector #:null 'error))))
  (check-equal? (~> '(1 2) series f64s) '(1.0 2.0))
  (check-equal? (~> (series '(1 2)) (series->f64vector #:null 'error) f64vector->list)
                '(1.0 2.0))
  (check-equal? (~> gappy (head 0) (series->f64vector #:null 'error) f64vector-length) 0)
  (check-exn #rx"not a numeric series"
             (lambda ()
               (~> (list polars-null) (series #:dtype 'string) (series->f64vector #:null 'error))))

  (for ([s (in-list (append temporal-series (list (series '("a") #:name "x"))))])
    (define rx
      (regexp (format "^series->f64vector: not a numeric series\n  series: \"x\"\n  dtype: '~a$"
                      (regexp-quote (format "~s" (dtype s))))))
    (check-exn rx (lambda () (series->f64vector s))))
  (define (not-blame? e) (and (exn:fail:contract? e) (not (exn:fail:contract:blame? e))))
  (define bin (cast (series '("a") #:name "b") 'binary))
  (for* ([b (list bin (head bin 0) (cast (all-null 'string) 'binary))]
         [(who convert) (in-dict (list (cons "series->list" series->list)
                                       (cons "series->vector" series->vector)
                                       (cons "in-series" in-series)
                                       (cons "in-series" sequence->list)))])
    (define rx (regexp (format "^~a: unsupported dtype\n  series: \"~a\"\n  dtype: 'binary$"
                               who (series-name b))))
    (check-exn rx (lambda () (convert b)))
    (check-exn not-blame? (lambda () (convert b))))

  (for ([thunk (list (lambda () (contracted:series->list 5))
                     (lambda () (contracted:series->vector frame))
                     (lambda () (contracted:series->f64vector withnull #:null "x"))
                     (lambda () (contracted:series->f64vector withnull #:null 'nan))
                     (lambda () (contracted:in-series '(1 2)))
                     (lambda () (contracted:dataframe->columns withnull))
                     (lambda () (contracted:dataframe->columns frame #:columns '(a)))
                     (lambda () (contracted:dataframe->f64vector frame #:order 'row))
                     (lambda () (contracted:dataframe->f64vector frame #:columns "a"))
                     (lambda () (contracted:dataframe->f64vector frame #:null 'nan)))])
    (check-exn exn:fail:contract:blame? thunk))
  (check-exn #rx"^series->list: contract violation\n  expected: series\\?\n  given: 5"
             (lambda () (contracted:series->list 5)))
  (check-exn (regexp (string-append "^dataframe->f64vector: contract violation\n"
                                     "  expected: \\(or/c \\(quote fortran\\) \\(quote c\\)\\)\n"
                                     "  given: 'row"))
             (lambda () (contracted:dataframe->f64vector frame #:order 'row)))

  (define mixed
    (dataframe
     (list (series (list 1 -2 polars-null 127) #:dtype 'int8 #:name "i8")
           (series (list (add1 (expt 2 53)) polars-null 3 -4) #:name "i64")
           (series (list (sub1 (expt 2 64)) 0 polars-null 7) #:dtype 'uint64 #:name "u64")
           (series (list 0.1 polars-null 2.5 -1.0) #:dtype 'float32 #:name "f32")
           (series (list -0.0 +nan.0 polars-null 4.5) #:name "f64"))))
  (define (matrix-matches? d cols order v)
    (define-values (m nrows ncols)
      (dataframe->f64vector d #:columns cols #:order order #:null v))
    (and (equal? (list nrows ncols (f64vector-length m))
                 (list (height d) (length cols) (* (height d) (length cols))))
         (for*/and ([(name j) (in-parallel cols (in-naturals))]
                    [(x i) (in-parallel (f64s (ref d name) v) (in-naturals))])
           (equal? (f64vector-ref m (if (eq? order 'fortran)
                                        (+ (* j nrows) i)
                                        (+ (* i ncols) j)))
                   x))))
  (for* ([d (list mixed (vstack mixed mixed))]
         [cols (list (column-names mixed) '("f64" "i8") '("u64"))]
         [order '(fortran c)]
         [v (list +nan.0 0)])
    (check-true (matrix-matches? d cols order v) (format "~a ~a ~a" cols order v)))
  (let-values ([(m nrows ncols) (dataframe->f64vector mixed)]
               [(m/c _nrows _ncols) (dataframe->f64vector mixed #:order 'c)])
    (check-equal? (list nrows ncols) '(4 5))
    (check-equal? (f64vector->list m/c)
                  (for*/list ([i nrows] [j ncols]) (f64vector-ref m (+ (* j nrows) i)))))
  (let-values ([(m nrows ncols) (dataframe->f64vector (head mixed 0))])
    (check-equal? (list (f64vector-length m) nrows ncols) '(0 0 5)))
  (let-values ([(m nrows ncols) (dataframe->f64vector mixed #:columns '())])
    (check-equal? (list (f64vector-length m) nrows ncols) '(0 4 0)))

  (define bad
    (dataframe (list (series (list 1 polars-null) #:name "a")
                     (series '("x" "y") #:name "s")
                     (series (list 0.5 polars-null) #:name "b"))))
  (define (frame-error who what name)
    (regexp (format "^~a: ~a\n  column: \"~a\"" who what name)))
  (for ([thunk (list (lambda () (dataframe->f64vector bad))
                     (lambda () (dataframe->f64vector bad #:null 'error)))])
    (check-exn (frame-error "dataframe->f64vector" "not a numeric column" "s") thunk)
    (check-exn #rx"\n  dtype: 'string$" thunk)
    (check-exn not-blame? thunk))
  (check-exn (null-error "dataframe->f64vector" "column" "a" 1)
             (lambda () (dataframe->f64vector bad #:columns '("a" "b") #:null 'error)))
  (check-exn (null-error "dataframe->f64vector" "column" "b" 1)
             (lambda () (dataframe->f64vector bad #:columns '("b" "a") #:null 'error)))
  (for ([(who convert) (in-dict (list (cons "dataframe->f64vector" dataframe->f64vector)
                                      (cons "dataframe->columns" dataframe->columns)))])
    (define ((go cols)) (convert bad #:columns cols))
    (check-exn (frame-error who "no such column" "nope") (go '("a" "nope")))
    (check-exn (frame-error who "duplicate column" "a") (go '("a" "a")))
    (check-exn not-blame? (go '("a" "a"))))

  (define binary-frame
    (dataframe (list (series '(1 2) #:name "a") (cast (series '("p" "q") #:name "b") 'binary))))
  (check-exn (frame-error "dataframe->columns" "unsupported dtype" "b")
             (lambda () (dataframe->columns binary-frame)))
  (for ([v (list polars-null 'missing)])
    (check-equal? (dataframe->columns mixed #:null v)
                  (for/list ([name (column-names mixed)])
                    (cons name (series->vector (ref mixed name) #:null v)))))
  (check-equal? (dataframe->columns mixed #:columns '("f64" "i8"))
                (list (cons "f64" (series->vector (ref mixed "f64")))
                      (cons "i8" (series->vector (ref mixed "i8")))))

  (define (settle!)
    (for ([_ (in-range 4)])
      (collect-garbage)
      (sleep 0.1)))
  (define (drops-during thunk)
    (settle!)
    (define before (series-drop-count))
    (with-handlers ([exn:fail? void]) (thunk))
    (- (series-drop-count) before))
  (check-equal? (drops-during (lambda () (dataframe->f64vector mixed #:columns '("i8" "f64"))))
                2)
  (check-equal? (drops-during (lambda () (dataframe->f64vector bad))) 3)
  (check-equal? (drops-during (lambda () (dataframe->f64vector bad #:columns '("nope")))) 0)
  (check-equal? (drops-during (lambda () (dataframe->columns mixed))) 5)
  (check-equal? (drops-during (lambda () (dataframe->columns binary-frame))) 2)
  (check-equal? (drops-during (lambda ()
                                (for ([_ (in-range 100)])
                                  (series->list withnull)
                                  (series->f64vector withnull)
                                  (for ([x withnull]) x))))
                0)
  (let ([wanted 20]
        [before (begin (settle!) (series-drop-count))])
    (for ([_ (in-range wanted)])
      (~> mixed (ref "i8") series->list))
    (settle!)
    (check >= (- (series-drop-count) before) (quotient wanted 2)))

  (check-equal? (~> (list 3 polars-null 1) (series #:name "x") series->list)
                (list 3 polars-null 1))
  (define to-dict (dataframe (list (series '("a" "b") #:name "k")
                                   (series (list 1 polars-null) #:name "v"))))
  (check-equal? (dataframe->columns to-dict)
                (list (cons "k" (vector "a" "b")) (cons "v" (vector 1 polars-null))))
  (define to-numpy (dataframe (list (series (list 1 2 polars-null) #:name "a")
                                    (series '(0.5 1.5 2.5) #:name "b"))))
  (let-values ([(m nrows ncols) (dataframe->f64vector to-numpy)])
    (check-equal? (list (f64vector->list m) nrows ncols) '((1.0 2.0 +nan.0 0.5 1.5 2.5) 3 2)))
  (let-values ([(m _nrows _ncols) (dataframe->f64vector to-numpy #:order 'c)])
    (check-equal? (f64vector->list m) '(1.0 0.5 2.0 1.5 +nan.0 2.5)))
  (check-equal? (~> (list 1 polars-null 3) series f64s) '(1.0 +nan.0 3.0))
  (let-values ([(m _nrows _ncols)
                (dataframe->f64vector (dataframe (list (series '(#t #f) #:name "a")
                                                       (series '(0.5 1.5) #:name "b"))))])
    (check-equal? (f64vector->list m) '(1.0 0.0 0.5 1.5))))
