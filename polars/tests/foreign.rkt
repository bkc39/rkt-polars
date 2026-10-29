#lang racket/base

(module+ test
  (require rackunit
           (only-in ffi/unsafe
                    _fun _int64 _pointer _string/utf-8 _void cast function-ptr make-ctype ptr-add)
           (only-in gregor
                    ->datetime/local ->posix ->tzid ->utc-offset date datetime iso8601->time
                    moment posix->datetime)
           (only-in gregor/period milliseconds)
           (only-in racket/match == match match* match-define)
           (only-in polars/private/c-integer int32/c int64/c size/c uint32/c uint64/c uint8/c)
           (only-in polars/private/foreign
                    ->compat-dtype CompatOptI64-value DataFrame-ptr? Series-ptr? YMDHMS? _Series-ptr
                    define-compat
                    copy-zoned-datetimes dataframe-column dataframe-column-name
                    dataframe-column-names dataframe-drop-columns dataframe-drop-count
                    dataframe-drop-nulls dataframe-empty dataframe-filter
                    dataframe-group-by-count dataframe-group-by-max dataframe-group-by-mean
                    dataframe-group-by-min dataframe-group-by-sum dataframe-height
                    dataframe-join-asof/raw dataframe-make dataframe-new dataframe-pivot
                    dataframe-rename dataframe-select dataframe-shape dataframe-unique
                    dataframe-unpivot dataframe-width dataframe-with-column dtype-short-names
                    enum-dtype? make-YMDHMS polars-null respell series-add series-add-f64
                    series-and series-cast series-div series-div-f64 series-drop-count
                    series-drop-nulls series-dt-convert-time-zone series-dt-replace-time-zone
                    series-dtype series-empty series-enum-categories/raw series-eq series-eq-f64
                    series-eq-str series-ge series-ge-f64 series-gt series-gt-f64
                    series-is-not-null series-is-null series-le series-le-f64 series-len
                    series-lt series-lt-f64 series-max-f32 series-max-f64 series-max-i16
                    series-max-i32 series-max-i64 series-max-i8 series-max-u16 series-max-u32
                    series-max-u64 series-max-u8 series-mean-f32 series-mean-f64 series-mean-i16
                    series-mean-i32 series-mean-i64 series-mean-i8 series-mean-u16
                    series-mean-u32 series-mean-u64 series-mean-u8 series-min-f32 series-min-f64
                    series-min-i16 series-min-i32 series-min-i64 series-min-i8 series-min-u16
                    series-min-u32 series-min-u64 series-min-u8 series-mod series-mod-f64
                    series-mul series-mul-f64 series-n-unique series-name series-ne
                    series-ne-f64 series-ne-str series-new-bool series-new-bool/vec
                    series-new-f32 series-new-f32/vec series-new-f64 series-new-f64/vec
                    series-new-i16 series-new-i16/vec series-new-i32 series-new-i32/vec
                    series-new-i64 series-new-i64/vec series-new-i8 series-new-i8/vec
                    series-new-str series-new-str/vec series-new-u16 series-new-u16/vec
                    series-new-u32 series-new-u32/vec series-new-u64 series-new-u64/vec
                    series-new-u8 series-new-u8/vec series-new-ymdhms series-new-ymdhms/vec
                    series-not series-null-count series-or series-ref series-rename
                    series-reverse series-sub series-sub-f64 series-sum-f32 series-sum-f64
                    series-sum-i16 series-sum-i32 series-sum-i64 series-sum-i8 series-sum-u16
                    series-sum-u32 series-sum-u64 series-sum-u8 series-time-zone series-unique
                    series-xor str-block-drop-count zoned-datetime-dtype? last-error-message
                    _c-string _c-string/null)
           (only-in polars/private/expr col expr-meta-output-name/raw expr-meta-root-names)
           (only-in (submod polars/private/foreign enum-misses) enum-misses-shown)
           (only-in (submod polars/private/foreign internal)
                    block-reader dataframe-drop dataframe-head dataframe-hstack dataframe-join
                    dataframe-join-asof dataframe-slice dataframe-sort dataframe-tail
                    dataframe-vstack series-add-i32 series-add-i64 series-add-u32 series-add-u64
                    series-div-i32 series-div-i64 series-div-u32 series-div-u64 series-drop
                    series-eq-i32 series-ge-i32 series-gt-i32 series-head series-le-i32
                    series-lt-i32 series-mod-i32 series-mod-i64 series-mod-u32 series-mod-u64
                    series-mul-i32 series-mul-i64 series-mul-u32 series-mul-u64 series-ne-i32
                    series-new-null series-ref-bytes series-ref-cat series-slice series-sort
                    series-std series-strings series-sub-i32 series-sub-i64 series-sub-u32
                    series-sub-u64 series-tail series-var)
           (only-in polars/private/bulk series->list)
           (only-in polars/private/resource with-raw-buffer with-release)
           (only-in threading ~>)
           (only-in (submod polars/private/resource internal) str-block->string)
           (only-in racket/list append-map)
           (only-in racket/string string-join)
           (only-in racket/contract exn:fail:contract:blame?)
           (prefix-in contracted: polars/private/foreign)
           (only-in polars/tests/test-helpers
                    drops-during not-utf-8-expected polars-dir polars-sources read-source refusal
                    refusal-misses
                    refused settle!
                    with-planted-sources)
           (only-in polars/tests/generic/test-fixtures nul-expected nul-names))

  (define empty-series-ptr
    (series-empty))
  (check-pred Series-ptr? empty-series-ptr)
  (check-pred void? (series-drop empty-series-ptr))

  (check-equal? (series-name (series-empty)) "")
  (check-equal? (series-dtype (series-empty)) 'int32)
  (check-equal?
   (let ([s (series-empty)])
     (series-rename s "hello")
     (series-name s))
   "hello")

  (define s (series-new-i32 "x" '(3 1 4 1 5 9 2 6)))
  (check-equal? (series-len (series-head s 3)) 3)
  (check-equal? (series-sum-i32 (series-head s 3)) 8) ;; 3+1+4
  (check-equal? (series-len (series-tail s 3)) 3)
  (check-equal? (series-sum-i32 (series-tail s 3)) 17) ;; 9+2+6
  (check-equal? (series-len (series-slice s 2 3)) 3)
  (check-equal? (series-sum-i32 (series-slice s 2 3)) 10) ;; 4+1+5
  (check-equal? (series-len (series-reverse s)) 8)
  (check-equal? (series-sum-i32 (series-reverse s)) (series-sum-i32 s))
  (check-equal? (series-len (series-unique s)) 7) ;; one duplicate (1)

  ;; sort
  (check-equal? (series-min-i32 (series-head (series-sort s) 1)) 1)
  (check-equal? (series-max-i32
                 (series-head (series-sort s #:descending #t) 1))
                9)

  ;; drop_nulls on a series with no nulls is a no-op
  (check-equal? (series-len (series-drop-nulls s)) 8)

  (define red-i32 (series-new-i32 "x" '(3 1 4 1 5 9 2 6)))
  (check-equal? (series-min-i32 red-i32) 1)
  (check-equal? (series-max-i32 red-i32) 9)
  (check-= (series-mean-i32 red-i32) (/ 31.0 8.0) 1e-9)
  (check-equal? (series-n-unique red-i32) 7) ;; {1,2,3,4,5,6,9}

  (define red-f64 (series-new-f64 "y" '(1.5 2.0 4.25 8.0)))
  (check-equal? (series-min-f64 red-f64) 1.5)

  (define red-i64 (series-new-i64 "wide" (list 1099511627776 polars-null 4)))
  (check-equal? (series-sum-i64 red-i64) 1099511627780)
  (check-equal? (series-min-i64 red-i64) 4)
  (check-equal? (series-max-i64 red-i64) 1099511627776)
  (check-= (series-mean-i64 red-i64) (/ 1099511627780.0 2.0) 1e-9)

  (define red-u32 (series-new-u32 "count" (list 1 2 polars-null 7)))
  (check-equal? (series-sum-u32 red-u32) 10)
  (check-equal? (series-min-u32 red-u32) 1)
  (check-equal? (series-max-u32 red-u32) 7)
  (check-= (series-mean-u32 red-u32) (/ 10.0 3.0) 1e-9)

  (define red-u64 (series-new-u64 "big" (list 10 20 4294967296)))
  (check-equal? (series-sum-u64 red-u64) 4294967326)
  (check-equal? (series-min-u64 red-u64) 10)
  (check-equal? (series-max-u64 red-u64) 4294967296)
  (check-= (series-mean-u64 red-u64) (/ 4294967326.0 3.0) 1e-6)

  (define red-i8 (series-new-i8 "tiny" (list -4 polars-null 9)))
  (check-equal? (series-sum-i8 red-i8) 5)
  (check-equal? (series-min-i8 red-i8) -4)
  (check-equal? (series-max-i8 red-i8) 9)
  (check-= (series-mean-i8 red-i8) 2.5 1e-9)

  (define red-i16 (series-new-i16 "short" (list -300 polars-null 1200)))
  (check-equal? (series-sum-i16 red-i16) 900)
  (check-equal? (series-min-i16 red-i16) -300)
  (check-equal? (series-max-i16 red-i16) 1200)
  (check-= (series-mean-i16 red-i16) 450.0 1e-9)

  (define red-u8 (series-new-u8 "byte" (list 3 polars-null 12)))
  (check-equal? (series-sum-u8 red-u8) 15)
  (check-equal? (series-min-u8 red-u8) 3)
  (check-equal? (series-max-u8 red-u8) 12)
  (check-= (series-mean-u8 red-u8) 7.5 1e-9)

  (define red-u16 (series-new-u16 "ushort" (list 300 polars-null 1200)))
  (check-equal? (series-sum-u16 red-u16) 1500)
  (check-equal? (series-min-u16 red-u16) 300)
  (check-equal? (series-max-u16 red-u16) 1200)
  (check-= (series-mean-u16 red-u16) 750.0 1e-9)

  (define red-f32 (series-new-f32 "single" (list 1.5 polars-null 2.25)))
  (check-= (series-sum-f32 red-f32) 3.75 1e-6)
  (check-= (series-min-f32 red-f32) 1.5 1e-6)
  (check-= (series-max-f32 red-f32) 2.25 1e-6)
  (check-= (series-mean-f32 red-f32) 1.875 1e-6)

  (check-equal? (series-n-unique
                 (series-new-str "s" '("a" "b" "a" "c" "b")))
                3)

  (check-equal? (series-len (series-empty)) 0)
  (check-equal? (series-null-count (series-empty)) 0)

  (check-pred Series-ptr? (series-new-i32 "" '(1 2 3)))
  (check-equal?
   (series-len (series-new-i32 "series" '(0 1)))
   2)
  (check-equal?
   (series-dtype (series-new-i32 "series" '(0 1)))
   'int32)
  (check-equal?
   (series-sum-i32 (series-new-i32 "" '(1 2 3 4)))
   10)
  (check-exn #rx"^series-sum-i32: invalid series dtype: expected `Int32`, got `f64`"
             (lambda () (series-sum-i32 (series-new-f64 "" '(1.0 2.0)))))
  (check-exn
   #rx"^series-new-i32: contract violation\n  expected: [^\n]*utf-8\\?[^\n]*\n  given: #f"
   (lambda ()
     (series-new-i32 #f '(1))))

  (check-pred Series-ptr? (series-new-i32/vec "" (vector 1 2 3)))
  (check-equal?
   (series-len (series-new-i32/vec "" (vector 0)))
   1)

  (check-pred Series-ptr? (series-new-i8 "x" '(-8 0 12)))
  (check-equal? (series-dtype (series-new-i8 "x" '(-8 0 12))) 'int8)
  (check-pred Series-ptr? (series-new-i8/vec "x" (vector -8 0 12)))
  (check-pred Series-ptr? (series-new-i16 "x" '(-300 0 1200)))
  (check-equal? (series-dtype (series-new-i16 "x" '(-300 0 1200))) 'int16)
  (check-pred Series-ptr? (series-new-i16/vec "x" (vector -300 0 1200)))

  (check-pred Series-ptr? (series-new-f64 "" '(1.1 2.17)))
  (check-equal?
   (series-len (series-new-f64 "series" '(0.0 1.2)))
   2)
  (check-equal?
   (series-dtype (series-new-f64 "series" '(0.0 1.2)))
   'float64)
  (check-equal?
   (series-sum-f64 (series-new-f64 "" '(1.5 2.0 4.25 8.0)))
   15.75)
  (check-equal?
   (series-mean-f64 (series-new-f64 "" '(1.0 2.0 3.0 4.0)))
   2.5)
  (check-equal?
   (series-max-f64 (series-new-f64 "" '(1.5 2.0 4.25 8.0)))
   8.0)
  (check-exn
   #rx"^series-new-f64: contract violation\n  expected: [^\n]*utf-8\\?[^\n]*\n  given: #f"
   (lambda ()
     (series-new-f64 #f '(1.0))))
  (check-exn
   #rx"given value does not fit primitive C type"
   (λ ()
     (series-new-f64 "no-name" '(0))))

  (check-pred Series-ptr? (series-new-f64/vec "" (vector 17.29 40.2)))
  (check-equal?
   (series-len (series-new-f64/vec "" (vector 17.29 40.2)))
   2)

  (check-pred Series-ptr? (series-new-f32 "" '(1.5 2.25)))
  (check-equal? (series-dtype (series-new-f32 "x" '(1.5 2.25))) 'float32)
  (check-pred Series-ptr? (series-new-f32/vec "" (vector 1.5 2.25)))

  (check-pred Series-ptr? (series-new-i64 "" '(1 2 3)))
  (check-equal? (series-len (series-new-i64 "x" '(1 2))) 2)
  (check-equal? (series-dtype (series-new-i64 "x" '(1 2))) 'int64)
  (check-pred Series-ptr? (series-new-i64/vec "" (vector 1 2 3)))

  (check-pred Series-ptr? (series-new-u32 "" '(1 2 3)))
  (check-equal? (series-len (series-new-u32 "x" '(0 1 2))) 3)
  (check-equal? (series-dtype (series-new-u32 "x" '(0 1))) 'uint32)
  (check-pred Series-ptr? (series-new-u32/vec "" (vector 1 2 3)))

  (check-pred Series-ptr? (series-new-u8 "x" '(0 1 255)))
  (check-equal? (series-dtype (series-new-u8 "x" '(0 1 255))) 'uint8)
  (check-pred Series-ptr? (series-new-u8/vec "x" (vector 0 1 255)))
  (check-pred Series-ptr? (series-new-u16 "x" '(0 1 65535)))
  (check-equal? (series-dtype (series-new-u16 "x" '(0 1 65535))) 'uint16)
  (check-pred Series-ptr? (series-new-u16/vec "x" (vector 0 1 65535)))

  (check-pred Series-ptr? (series-new-u64 "" '(1 2 3)))
  (check-equal? (series-len (series-new-u64 "x" '(0 1 2))) 3)
  (check-equal? (series-dtype (series-new-u64 "x" '(0 1))) 'uint64)
  (check-pred Series-ptr? (series-new-u64/vec "" (vector 1 2 3)))

  (for ([n (in-list '(0 3))])
    (define nulls (series-new-null "nothing" n))
    (check-equal? (list (series-name nulls) (series-len nulls) (series-dtype nulls)
                        (series-null-count nulls))
                  (list "nothing" n 'null n)))
  (check-exn #rx"^series-new-null: contract violation"
             (lambda () (contracted:series-new-null #f 0)))
  (check-exn (refused 'series-new-str #"\377" #:expected not-utf-8-expected)
             (lambda () (series-new-str #"\377" '("a"))))
  (check-equal? (series-name (series-new-bool/vec #"q" (vector #t))) "q")
  (check-pred Series-ptr? (series-new-bool "" '(#t #f #t)))
  (check-equal? (series-len (series-new-bool "x" '(#t #f))) 2)
  (check-equal? (series-dtype (series-new-bool "x" '(#t #f))) 'boolean)
  (check-pred Series-ptr? (series-new-bool/vec "" (vector #t #f #t)))

  (check-pred Series-ptr? (series-new-str "" '("foo" "bar" "baz" "")))
  (check-equal?
   (series-len (series-new-str "str" '("" "")))
   2)
  (check-exn
   #rx"contract violation"
   (λ ()
     (series-new-str "" '(symbol))))
  (check-exn #rx"^series-new-str/vec: contract violation.*given: #f"
             (lambda () (series-new-str/vec "" (vector "a" #f))))

  (define mixed-strings
    (list "héllo" polars-null "" "東京 😀" polars-null "a string past twelve bytes" "a\u0000b"))
  (define mixed-series (series-new-str "mixed" mixed-strings))
  (check-equal? (series-null-count mixed-series) 2)
  (check-equal? (for/list ([i (in-range (series-len mixed-series))]) (series-ref mixed-series i))
                mixed-strings)
  (check-equal? (series-ref (series-new-str/vec "v" (list->vector mixed-strings)) 3) "東京 😀")

  (check-pred Series-ptr? (series-new-str/vec "" (vector "foo" "bar" "baz" "")))
  (check-equal?
   (series-name (series-new-str "str" '("" "")))
   "str")
  (check-equal?
   (series-dtype (series-new-str "str" '("" "")))
   'string)

  (check-pred YMDHMS?
              (make-YMDHMS 2014 7 11 12 0 0))

  (let ([bytes-of (series-cast (series-new-str "b" (list "a\u0000é" polars-null "")) 'binary)])
    (check-equal? (map (lambda (i) (series-ref-bytes 'test bytes-of i 10)) '(0 1 2))
                  (list #"a\0\303\251" polars-null #""))
    (check-equal? (for/list ([limit (in-list '(0 1 3 4 5))])
                    (series-ref-bytes 'test bytes-of 0 limit))
                  (list #"" #"a" #"a\0\303" #"a\0\303\251" #"a\0\303\251"))
    (check-equal? (series-ref-bytes 'test bytes-of 1 0) polars-null)
    (check-exn #rx"^test: cannot read a binary value at index 3$"
               (lambda () (series-ref-bytes 'test bytes-of 3 10)))
    (check-exn #rx"^test: cannot read a binary value at index 0$"
               (lambda () (series-ref-bytes 'test (series-new-str "s" '("a")) 0 10))))

  (define-values (ex0 ex1)
    (values
     (list (make-YMDHMS 2010 1 1 0 0 0))
     (list (make-YMDHMS 2010 1 1 0 0 0)
           (make-YMDHMS 2011 1 1 0 0 0)
           (make-YMDHMS 2012 1 1 0 0 0))))
  (check-pred Series-ptr?
              (series-new-ymdhms "" ex0))
  (check-equal?
   (series-len (series-new-ymdhms "name" ex1))
   3)
  (check-pred Series-ptr?
              (series-new-ymdhms/vec "" (list->vector ex0)))
  (check-equal?
   (series-len (series-new-ymdhms/vec "name"
                                      (list->vector ex1)))
   3)
  (check-equal?
   (series-dtype (series-new-ymdhms "name" ex1))
   '(datetime milliseconds #f))

  (for ([ctor+dtype
         (in-list (list (list series-new-i8 series-new-i8/vec 'int8)
                        (list series-new-i16 series-new-i16/vec 'int16)
                        (list series-new-i32 series-new-i32/vec 'int32)
                        (list series-new-i64 series-new-i64/vec 'int64)
                        (list series-new-u8 series-new-u8/vec 'uint8)
                        (list series-new-u16 series-new-u16/vec 'uint16)
                        (list series-new-u32 series-new-u32/vec 'uint32)
                        (list series-new-u64 series-new-u64/vec 'uint64)
                        (list series-new-f32 series-new-f32/vec 'float32)
                        (list series-new-f64 series-new-f64/vec 'float64)
                        (list series-new-bool series-new-bool/vec 'boolean)
                        (list series-new-str series-new-str/vec 'string)
                        (list series-new-ymdhms series-new-ymdhms/vec
                              '(datetime milliseconds #f))))])
    (match-define (list new-list new-vector dtype) ctor+dtype)
    (for ([empty (in-list (list (new-list "e" '()) (new-vector "e" (vector))))])
      (check-equal? (list (series-name empty) (series-len empty) (series-dtype empty))
                    (list "e" 0 dtype)
                    (format "~s" dtype))))

  (define-namespace-anchor ref-anchor)
  (define ref-i32 (series-new-i32 "x" (list 10 polars-null -3)))
  (check-equal? (series-len ref-i32) 3)
  (check-equal? (series-null-count ref-i32) 1)
  (check-equal? (series-ref ref-i32 0) 10)
  (check-equal? (series-ref ref-i32 1) polars-null)
  (check-equal? (series-ref ref-i32 2) -3)

  (define ref-i64 (series-new-i64 "x" (list 1099511627776 polars-null)))
  (check-equal? (series-ref ref-i64 0) 1099511627776)
  (check-equal? (series-ref ref-i64 1) polars-null)
  (define client-ref-i64
    (parameterize ([current-namespace (namespace-anchor->empty-namespace ref-anchor)])
      (namespace-require 'racket/base)
      (eval '(module client racket/base
               (require (only-in polars/private/foreign series-ref-i64/raw))
               (provide client-ref)
               (define (client-ref s index) (series-ref-i64/raw s index))))
      (dynamic-require ''client 'client-ref)))
  (for ([index (in-list '(-1 a 2 5))])
    (check-exn #rx"^series-ref-i64/raw: contract violation\n.*\n  blaming: client\n"
               (lambda () (client-ref-i64 ref-i64 index))))
  (check-equal? (CompatOptI64-value (client-ref-i64 ref-i64 0)) 1099511627776)
  (define client-ref-bytes
    (parameterize ([current-namespace (namespace-anchor->empty-namespace ref-anchor)])
      (namespace-require 'racket/base)
      (eval '(module bytes-client racket/base
               (require (only-in polars/private/foreign series-ref-bytes))
               (provide client-ref-bytes)
               (define (client-ref-bytes s index) (series-ref-bytes 'client s index 4))))
      (dynamic-require ''bytes-client 'client-ref-bytes)))
  (define ref-binary (series-cast (series-new-str "b" '("abcdef")) 'binary))
  (for ([index (in-list '(-1 a 1))])
    (check-exn #rx"^series-ref-bytes: contract violation\n.*\n  blaming: bytes-client\n"
               (lambda () (client-ref-bytes ref-binary index))))
  (check-equal? (client-ref-bytes ref-binary 0) #"abcd")

  (define ref-i8 (series-new-i8 "x" (list -8 polars-null 12)))
  (check-equal? (series-ref ref-i8 0) -8)
  (check-equal? (series-ref ref-i8 1) polars-null)
  (check-equal? (series-ref ref-i8 2) 12)

  (define ref-i16 (series-new-i16 "x" (list -300 polars-null 1200)))
  (check-equal? (series-ref ref-i16 0) -300)
  (check-equal? (series-ref ref-i16 1) polars-null)
  (check-equal? (series-ref ref-i16 2) 1200)

  (define ref-u32 (series-new-u32 "x" (list 0 polars-null 4294967295)))
  (check-equal? (series-ref ref-u32 0) 0)
  (check-equal? (series-ref ref-u32 1) polars-null)
  (check-equal? (series-ref ref-u32 2) 4294967295)

  (define ref-u8 (series-new-u8 "x" (list 0 polars-null 255)))
  (check-equal? (series-ref ref-u8 0) 0)
  (check-equal? (series-ref ref-u8 1) polars-null)
  (check-equal? (series-ref ref-u8 2) 255)

  (define ref-u16 (series-new-u16 "x" (list 0 polars-null 65535)))
  (check-equal? (series-ref ref-u16 0) 0)
  (check-equal? (series-ref ref-u16 1) polars-null)
  (check-equal? (series-ref ref-u16 2) 65535)

  (define ref-u64 (series-new-u64 "x" (list 0 polars-null 4294967296)))
  (check-equal? (series-ref ref-u64 2) 4294967296)

  (define ref-f32 (series-new-f32 "x" (list 1.5 polars-null 2.25)))
  (check-equal? (series-dtype ref-f32) 'float32)
  (check-equal? (series-null-count ref-f32) 1)
  (check-= (series-ref ref-f32 0) 1.5 1e-6)
  (check-equal? (series-ref ref-f32 1) polars-null)

  (define ref-f64 (series-new-f64 "x" (list 1.5 polars-null 2.25)))
  (check-equal? (series-dtype ref-f64) 'float64)
  (check-equal? (series-null-count ref-f64) 1)
  (check-equal? (series-ref ref-f64 0) 1.5)
  (check-equal? (series-ref ref-f64 1) polars-null)

  (define ref-bool (series-new-bool "x" (list #t #f polars-null)))
  (check-equal? (series-ref ref-bool 0) #t)
  (check-equal? (series-ref ref-bool 1) #f)
  (check-equal? (series-ref ref-bool 2) polars-null)

  (define ref-str (series-new-str "x" (list "alpha" polars-null "")))
  (check-equal? (series-ref ref-str 0) "alpha")
  (check-equal? (series-ref ref-str 1) polars-null)
  (check-equal? (series-ref ref-str 2) "")

  (define ref-dt
    (series-new-ymdhms
     "x"
     (list (make-YMDHMS 2024 1 2 3 4 5)
           polars-null)))
  (check-equal? (series-ref ref-dt 0) (datetime 2024 1 2 3 4 5))
  (check-equal? (series-ref ref-dt 1) polars-null)
  (for ([unit '(milliseconds microseconds nanoseconds)]
        [k '(1000 1000000 1000000000)])
    (define ticks (series-cast (series-new-i64 "t" (list 1500 -1 polars-null))
                               (list 'datetime unit)))
    (check-equal? (series-ref ticks 0) (posix->datetime (/ 1500 k)))
    (check-equal? (series-ref ticks 1) (posix->datetime (/ -1 k)))
    (check-equal? (series-ref ticks 2) polars-null))
  (check-equal? (series-ref (series-cast (series-new-i64 "t" '(1500)) '(datetime milliseconds)) 0)
                (datetime 1970 1 1 0 0 1 500000000))

  (define ref-date
    (series-cast (series-new-i32 "d" (list 19724 polars-null -1)) 'date))
  (check-equal? (series-dtype ref-date) 'date)
  (check-equal? (series-ref ref-date 0) (date 2024 1 2))
  (check-equal? (series-ref ref-date 1) polars-null)
  (check-equal? (series-ref ref-date 2) (date 1969 12 31))

  (define ref-duration
    (series-cast (series-new-i64 "dur" (list 1500 polars-null -250))
                 '(duration milliseconds)))
  (check-equal? (series-dtype ref-duration) '(duration milliseconds))
  (check-equal? (series-ref ref-duration 0) (milliseconds 1500))
  (check-equal? (series-ref ref-duration 1) polars-null)
  (check-equal? (series-ref ref-duration 2) (milliseconds -250))

  (define ref-time
    (series-cast (series-new-i64 "tod" (list 11045123456789 polars-null 0))
                 'time))
  (check-equal? (series-dtype ref-time) 'time)
  (check-equal? (series-ref ref-time 0) (iso8601->time "03:04:05.123456789"))
  (check-equal? (series-ref ref-time 1) polars-null)
  (check-equal? (series-ref ref-time 2) (iso8601->time "00:00:00"))

  (define ref-vec (series-new-i32/vec "x" (vector 1 polars-null 3)))
  (check-equal? (series-ref ref-vec 1) polars-null)

  (check-exn #rx"nonnegative"
             (lambda () (series-ref ref-i32 -1)))
  (check-exn #rx"out of bounds"
             (lambda () (series-ref ref-i32 3)))

  (define (cast-message s dtype)
    (with-handlers ([exn:fail? exn-message])
      (series-cast s dtype)
      #f))
  (define (strings . values)
    (series-new-str "s" values))
  (define (numbered n)
    (for/list ([i (in-range n)])
      (format "v~a" (+ 100 i))))

  (check-equal? (cast-message (strings "TEB" polars-null "XYZ" "TEB" "EWR") '(enum EWR JFK LGA))
                "series-cast: 3 of 4 values are not in '(enum EWR JFK LGA): TEB XYZ")
  (check-equal? (cast-message (strings "Very High") '(enum))
                "series-cast: 1 of 1 value is not in '(enum): |Very High|")
  (check-equal? (cast-message (series-cast (strings "high" "high") '(enum high)) '(enum low))
                "series-cast: 2 of 2 values are not in '(enum low): high")
  (check-equal? (cast-message (series-cast (strings "low" "mid") 'categorical) '(enum low))
                "series-cast: 1 of 2 values is not in '(enum low): mid")
  (check-equal? (cast-message (strings "..." "b") '(enum b))
                "series-cast: 1 of 2 values is not in '(enum b): ...")
  (check-equal? (cast-message (strings "a\u0000b") '(enum b))
                "series-cast: 1 of 1 value is not in '(enum b): \"a\\u0000b\"")
  (check-equal? (cast-message (apply strings (numbered enum-misses-shown)) '(enum a))
                (format "series-cast: ~a of ~a values are not in '(enum a): ~a"
                        enum-misses-shown enum-misses-shown
                        (string-join (numbered enum-misses-shown))))
  (check-equal? (cast-message (apply strings (reverse (numbered (add1 enum-misses-shown))))
                              '(enum a))
                (format "series-cast: ~a of ~a values are not in '(enum a): ~a, and 1 more"
                        (add1 enum-misses-shown) (add1 enum-misses-shown)
                        (string-join (numbered enum-misses-shown))))
  (check-equal? (cast-message (series-new-bool "b" '(#t)) '(enum a))
                "series-cast: cannot convert to '(enum a): cannot cast Boolean to Categorical")

  (define distinct 100000)
  (define many
    (series-new-str "s" (for/list ([i (in-range (* 2 distinct))])
                          (format "k~a" (+ distinct (quotient i 2))))))
  (collect-garbage)
  (define allocated (current-memory-use 'cumulative))
  (check-equal? (cast-message many '(enum a))
                (format "series-cast: ~a of ~a values are not in '(enum a): ~a, and ~a more"
                        (* 2 distinct) (* 2 distinct)
                        (string-join (for/list ([i (in-range enum-misses-shown)])
                                       (format "k~a" (+ distinct i))))
                        (- distinct enum-misses-shown)))
  (check < (- (current-memory-use 'cumulative) allocated) 1000000)

  (define batch2-x (series-new-i32 "x" (list 1 2 polars-null 4)))
  (define batch2-y (series-new-i32 "y" '(10 20 30 40)))

  ;; cast
  (define x64 (series-cast batch2-x 'float64))
  (check-equal? (series-dtype x64) 'float64)
  (check-equal? (series-ref x64 0) 1.0)
  (check-equal? (series-ref x64 2) polars-null)
  (define xs (series-cast batch2-y 'string))
  (check-equal? (series-dtype xs) 'string)
  (check-equal? (series-ref xs 1) "20")
  (for ([dtype '(int8 int16 uint8 uint16 float32)])
    (define casted (series-cast (series-new-i32 "small" '(1 2 3)) dtype))
    (check-equal? (series-dtype casted) dtype)
    (check-equal? (series-ref casted 1) (if (eq? dtype 'float32) 2.0 2)))
  (check-exn #rx"unsupported cast target"
             (lambda () (series-cast batch2-x '(list int32))))
  (for ([(short canonical) (in-hash dtype-short-names)])
    (check-equal? (series-dtype (series-cast batch2-y short)) canonical))

  (define bears (series-new-str "bears" (list "Polar" polars-null "Brown" "Polar")))
  (define bears/cat (series-cast bears 'categorical))
  (check-equal? (series-dtype bears/cat) 'categorical)
  (check-equal? (for/list ([i 4]) (series-ref bears/cat i)) (list 'Polar polars-null 'Brown 'Polar))
  (define bears/enum (series-cast bears '(enum Polar Panda Brown)))
  (check-equal? (series-dtype bears/enum) '(enum Polar Panda Brown))
  (check-equal? (series-ref bears/enum 2) 'Brown)
  (check-equal? (series-dtype (series-cast (series-head bears 0) '(enum))) '(enum))
  (check-equal? (series-ref (series-cast bears/enum 'string) 0) "Polar")
  (check-exn #rx"^series-cast: 1 of 3 values is not in '\\(enum Polar Panda\\): Brown$"
             (lambda () (series-cast bears '(enum Polar Panda))))
  (check-exn #rx"unsupported cast target '\\(enum Polar Polar\\)"
             (lambda () (series-cast bears '(enum Polar Polar))))
  (check-exn #rx"unsupported cast target '\\(enum \"Polar\"\\)"
             (lambda () (series-cast bears '(enum "Polar"))))
  (check-true (enum-dtype? '(enum)))
  (check-false (enum-dtype? '(enum a . b)))
  (define nul-polar (string->symbol "Po\u0000lar"))
  (define nul-bears (series-new-str "bears" (list "Po\u0000lar" polars-null "Brown")))
  (define nul-bears/enum (series-cast nul-bears (list 'enum 'Brown nul-polar)))
  (check-equal? (series-dtype nul-bears/enum) (list 'enum 'Brown nul-polar))
  (define nul-bears/cat (series-cast nul-bears 'categorical))
  (for ([s (in-list (list nul-bears nul-bears/cat nul-bears/enum))])
    (check-equal? (for/list ([i (in-range 3)]) (contracted:series-ref-str s i))
                  (list "Po\u0000lar" #f "Brown")))
  (for ([s (in-list (list nul-bears/cat nul-bears/enum))])
    (check-equal? (for/list ([i (in-range 3)]) (series-ref s i)) (list nul-polar polars-null 'Brown))
    (check-equal? (for/list ([i (in-range 4)]) (series-ref-cat s i))
                  (list "Po\u0000lar" #f "Brown" #f))
    (check-equal? (drops-during series-drop-count (lambda () (series-ref s 0))) 0)
    (check-equal? (drops-during str-block-drop-count (lambda () (series-ref s 0))) 1)
    (check-equal? (drops-during str-block-drop-count (lambda () (series-ref s 1))) 0))
  (check-false (series-ref-cat nul-bears 0))
  (check-false (contracted:series-ref-str (series-new-i64 "i" '(1)) 0))
  (check-exn #rx"^series-ref-str: contract violation"
             (lambda () (contracted:series-ref-str nul-bears 3)))
  (check-equal? (series-strings nul-bears 2 1) '("Brown"))
  (check-equal? (series-strings nul-bears 0 0) '())
  (check-equal? (series-strings nul-bears 0 3) '("Po\u0000lar" "" "Brown"))
  (check-false (series-strings (series-new-i64 "i" '(1)) 0 1))
  (define many-levels
    (cons 'enum (for/list ([i (in-range 10000)]) (string->symbol (format "l\u0000~a" i)))))
  (define many-levels/enum
    (series-cast (series-new-str "l" (list (symbol->string (cadr many-levels)))) many-levels))
  (check-equal? (series-dtype many-levels/enum) many-levels)
  (check-equal? (drops-during series-drop-count (lambda () (series-dtype many-levels/enum))) 1)

  (define stamps (series-new-i64 "t" (list 1616842800000000 polars-null -1)))
  (define brussels (series-cast stamps '(datetime microseconds "Europe/Brussels")))
  (check-equal? (series-dtype brussels) '(datetime microseconds "Europe/Brussels"))
  (check-equal? (series-time-zone brussels) "Europe/Brussels")
  (check-false (series-time-zone stamps))
  (check-false (series-time-zone (series-cast stamps '(datetime microseconds #f))))
  (check-equal? (series-ref brussels 0) (moment 2021 3 27 12 #:tz "Europe/Brussels"))
  (check-equal? (series-ref brussels 1) polars-null)
  (check-equal? (series-ref brussels 2) (moment 1970 1 1 0 59 59 999999000 #:tz "Europe/Brussels"))
  (check-equal? (series-ref (series-cast brussels '(datetime nanoseconds "UTC")) 0)
                (moment 2021 3 27 11 #:tz "UTC"))
  (check-equal? (series-ref (series-cast brussels '(datetime milliseconds #f)) 0)
                (datetime 2021 3 27 11))
  (define (wall-clock m) (list (->datetime/local m) (->utc-offset m) (->tzid m)))
  (define ns-edges
    (series-new-i64 "t" (list (+ (* (->posix (datetime 2262 4 11 23)) 1000000000) 1)
                              (+ (- (sub1 (expt 2 63))) 3600000000000))))
  (check-equal? (wall-clock (series-ref (series-cast ns-edges '(datetime nanoseconds "Asia/Tokyo"))
                                        0))
                (list (datetime 2262 4 12 8 0 0 1) 32400 "Asia/Tokyo"))
  (check-equal? (wall-clock (series-ref (series-cast ns-edges
                                                     '(datetime nanoseconds "America/New_York"))
                                        1))
                (list (datetime 1677 9 20 20 16 41 145224193) -17762 "America/New_York"))
  (with-raw-buffer ([out 8 _int64])
    (check-exn (regexp (string-append "^test: could not copy a series of dtype"
                                      " '\\(datetime microseconds \"Europe/Brussels\"\\)"
                                      " \\(status -1\\)$"))
               (lambda ()
                 (copy-zoned-datetimes 'test brussels '(datetime microseconds "Europe/Brussels")
                                       1 4 out (ptr-add out 4 _int64) #f))))
  (check-equal? (series-dtype (series-cast stamps '(datetime microseconds "+05:00")))
                '(datetime microseconds "Etc/GMT-5"))
  (check-exn #rx"unable to parse time zone: '\\+05:30'"
             (lambda () (series-cast stamps '(datetime microseconds "+05:30"))))
  (check-exn (regexp (string-append "^series-cast: cannot convert to '\\(datetime microseconds"
                                    " \"Mars/Base\"\\): unable to parse time zone: 'Mars/Base'"))
             (lambda () (series-cast stamps '(datetime microseconds "Mars/Base"))))
  (check-exn #rx"^series-cast: contract violation\n  expected: time-zone-name/c\n  given: \"\"\n"
             (lambda () (series-cast stamps '(datetime microseconds ""))))
  (check-exn #rx"^->compat-dtype: unsupported cast target '\\(datetime microseconds \"UTC\"\\)"
             (lambda () (->compat-dtype '(datetime microseconds "UTC"))))
  (check-true (zoned-datetime-dtype? '(datetime nanoseconds "UTC")))
  (for ([v (list '(datetime nanoseconds "") '(datetime #f "UTC") '(datetime nanoseconds #f)
                 '(datetime nanoseconds UTC) '(datetime nanoseconds "UTC" x))])
    (check-false (zoned-datetime-dtype? v)))
  (check-equal? (series-ref (series-dt-convert-time-zone 'test brussels "Asia/Kathmandu") 0)
                (moment 2021 3 27 16 45 #:tz "Asia/Kathmandu"))
  (check-equal? (series-ref (series-dt-replace-time-zone 'test brussels "UTC" 'raise 'raise) 0)
                (moment 2021 3 27 12 #:tz "UTC"))
  (check-equal? (series-ref (series-dt-replace-time-zone 'test brussels #f 'raise 'raise) 0)
                (datetime 2021 3 27 12))
  (check-exn #rx"^test: cannot convert to the time zone \"Mars/Base\": unable to parse"
             (lambda () (series-dt-convert-time-zone 'test brussels "Mars/Base")))
  (check-exn (regexp (string-append "^test: cannot replace the time zone with \"UTC\": invalid"
                                    " ambiguous 'x', expected one of 'earliest', 'latest', 'null'"
                                    " or 'raise'$"))
             (lambda () (series-dt-replace-time-zone 'test brussels "UTC" 'x 'raise)))
  (check-exn (regexp (string-append "^test: cannot replace the time zone with \"UTC\": invalid"
                                    " non-existent 'earliest', expected 'null' or 'raise'$"))
             (lambda () (series-dt-replace-time-zone 'test brussels "UTC" 'raise 'earliest)))
  (check-equal? (respell (string-append "is ambiguous. Please use `ambiguous` to tell how it"
                                        " should be localized. You may be able to use"
                                        " `non_existent='null'` to return `null`"))
                (string-append "is ambiguous. Please use #:ambiguous to tell how it should be"
                               " localized. You may be able to use dt-replace-time-zone's"
                               " #:non-existent 'null to return `null`"))
  (check-equal? (respell "try renaming the columns with `.alias(\"new_name\")` to avoid")
                "try renaming the columns with `(alias expr \"new-name\")` to avoid")
  (check-exn #rx"^series-cast: .*did you mean 'Asia/Baku' instead\\?$"
             (lambda () (series-cast stamps '(datetime microseconds "Mars/Base"))))

  ;; reductions
  (define stats (series-new-f64 "s" '(1.0 2.0 3.0 4.0)))
  (check-= (series-var stats #:ddof 1) (/ 5.0 3.0) 1e-9)
  (check-= (series-var stats #:ddof 0) 1.25 1e-9)
  (check-= (series-std stats #:ddof 0) (sqrt 1.25) 1e-9)
  (check-false (series-std (series-new-str "s" '("a" "b"))))
  (check-false (series-var (series-new-str "s" '("a" "b"))))

  (define reduction-wrong-f64 (series-new-f64 "wrong" '(1.0 2.0)))
  (define reduction-dtype-cases
    (for*/list ([family (in-list
                         (list (list "Int8" series-sum-i8 series-min-i8 series-max-i8
                                     series-mean-i8)
                               (list "Int16" series-sum-i16 series-min-i16 series-max-i16
                                     series-mean-i16)
                               (list "Int32" series-sum-i32 series-min-i32 series-max-i32
                                     series-mean-i32)
                               (list "Int64" series-sum-i64 series-min-i64 series-max-i64
                                     series-mean-i64)
                               (list "UInt8" series-sum-u8 series-min-u8 series-max-u8
                                     series-mean-u8)
                               (list "UInt16" series-sum-u16 series-min-u16 series-max-u16
                                     series-mean-u16)
                               (list "UInt32" series-sum-u32 series-min-u32 series-max-u32
                                     series-mean-u32)
                               (list "UInt64" series-sum-u64 series-min-u64 series-max-u64
                                     series-mean-u64)
                               (list "Float32" series-sum-f32 series-min-f32 series-max-f32
                                     series-mean-f32)
                               (list "Float64" series-sum-f64 series-min-f64 series-max-f64
                                     series-mean-f64)))]
                [reduce (in-list (cdr family))])
      (list reduce (car family))))
  (check-equal? (length reduction-dtype-cases) 40)
  (for ([case (in-list reduction-dtype-cases)])
    (match-define (list reduce dtype) case)
    (define wrong (if (equal? dtype "Float64") (series-new-i32 "wrong" '(1 2)) reduction-wrong-f64))
    (check-exn (regexp (format "^~a: invalid series dtype: expected `~a`, got `[^`]+` .*`wrong`$"
                               (object-name reduce) dtype))
               (lambda () (reduce wrong))
               (format "~a" (object-name reduce))))

  ;; series-series comparisons
  (define cmp-left (series-new-i32 "a" '(1 2 3 4)))
  (define cmp-right (series-new-i32 "b" '(1 0 3 9)))
  (check-equal? (series-dtype (series-eq cmp-left cmp-right)) 'boolean)
  (check-equal? (series-ref (series-eq cmp-left cmp-right) 0) #t)
  (check-equal? (series-ref (series-ne cmp-left cmp-right) 1) #t)
  (check-equal? (series-ref (series-gt cmp-left cmp-right) 1) #t)
  (check-equal? (series-ref (series-ge cmp-left cmp-right) 2) #t)
  (check-equal? (series-ref (series-lt cmp-left cmp-right) 3) #t)
  (check-equal? (series-ref (series-le cmp-left cmp-right) 0) #t)

  ;; element-wise arithmetic
  (define added (series-add batch2-x batch2-y))
  (check-equal? (series-dtype added) 'int32)
  (check-equal? (series-ref added 0) 11)
  (check-equal? (series-ref added 2) polars-null)
  (check-equal? (series-ref (series-sub batch2-y batch2-x) 1) 18)
  (check-equal? (series-ref (series-mul batch2-x batch2-y) 3) 160)
  (define divided (series-div batch2-y batch2-x))
  (check-equal? (series-dtype divided) 'int32)
  (check-equal? (series-ref divided 1) 10)
  (define divided-f64 (series-div (series-cast batch2-y 'float64)
                                  (series-cast batch2-x 'float64)))
  (check-equal? (series-dtype divided-f64) 'float64)
  (check-equal? (series-ref divided-f64 1) 10.0)
  (check-equal? (series-ref (series-mod batch2-y batch2-x) 3) 0)
  (check-exn #rx"^series-add: cannot do arithmetic operation on series of different lengths"
             (lambda ()
               (series-add (series-new-i32 "short" '(1 2))
                           (series-new-i32 "long" '(1 2 3)))))

  ;; scalar arithmetic
  (define add-scalar (series-add-i32 batch2-x 5))
  (check-equal? (series-dtype add-scalar) 'int32)
  (check-equal? (series-ref add-scalar 0) 6)
  (check-equal? (series-ref add-scalar 2) polars-null)
  (check-equal? (series-ref (series-sub-i32 batch2-y 7) 1) 13)
  (check-equal? (series-ref (series-mul-i32 batch2-x 3) 3) 12)
  (check-equal? (series-ref (series-div-i32 batch2-y 10) 1) 2)
  (check-equal? (series-ref (series-mod-i32 batch2-y 7) 3) 5)
  (check-equal? (series-ref (series-add-i64 (series-new-i64 "wide" '(10000000000 2)) 5) 0)
                10000000005)
  (check-equal? (series-ref (series-mul-u32 (series-new-u32 "u" '(2 3 4)) 10) 2)
                40)
  (check-equal? (series-ref (series-sub-u64 (series-new-u64 "u" '(10 20 30)) 7) 1)
                13)
  (check-equal? (series-ref (series-div-f64 (series-new-f64 "f" '(3.0 7.5)) 2.5) 1)
                3.0)
  (check-equal? (series-ref (series-mod-f64 (series-new-f64 "f" '(3.0 7.5)) 2.0) 1)
                1.5)
  (check-exn #rx"^series-add-i32: invalid series dtype: expected `Int32`, got `f64` .*`f`$"
             (lambda () (series-add-i32 (series-new-f64 "f" '(1.0 2.0)) 3)))

  ;; Use a small dataframe so we can read mask results back via dataframe-filter.
  (define cmp-df
    (dataframe-new
     (list (series-new-i32 "x" '(1 2 3 4 5))
           (series-new-f64 "y" '(1.0 2.0 3.0 4.0 5.0))
           (series-new-str "s" '("a" "b" "a" "b" "c")))))

  (define (count-where mask)
    (dataframe-height (dataframe-filter cmp-df mask)))

  ;; i32: each op returns a boolean Series
  (check-equal? (series-dtype (series-lt-i32 (dataframe-column cmp-df "x") 3))
                'boolean)
  (check-equal? (count-where (series-lt-i32 (dataframe-column cmp-df "x") 3)) 2)
  (check-equal? (count-where (series-le-i32 (dataframe-column cmp-df "x") 3)) 3)
  (check-equal? (count-where (series-ge-i32 (dataframe-column cmp-df "x") 3)) 3)
  (check-equal? (count-where (series-eq-i32 (dataframe-column cmp-df "x") 3)) 1)
  (check-equal? (count-where (series-ne-i32 (dataframe-column cmp-df "x") 3)) 4)

  ;; f64
  (check-equal? (count-where (series-gt-f64 (dataframe-column cmp-df "y") 2.5)) 3)
  (check-equal? (count-where (series-eq-f64 (dataframe-column cmp-df "y") 4.0)) 1)

  ;; str
  (check-equal? (count-where (series-eq-str (dataframe-column cmp-df "s") "a")) 2)
  (check-equal? (count-where (series-ne-str (dataframe-column cmp-df "s") "a")) 3)
  (define ab (series-new-str "s" '("a" "b")))
  (for ([case (list (list series-eq-str 'categorical "a" '(#t #f))
                    (list series-ne-str 'categorical "a" '(#f #t))
                    (list series-eq-str '(enum a b) "b" '(#f #t))
                    (list series-eq-str '(enum a b) "z" '(#f #f))
                    (list series-ne-str '(enum a b) "z" '(#t #t))
                    (list series-eq-str 'string polars-null (list polars-null polars-null))
                    (list series-ne-str '(enum a b) polars-null (list polars-null polars-null)))])
    (match-define (list compare dtype v expected) case)
    (check-equal? (~> (series-cast ab dtype) (compare v) series->list) expected (format "~s" case)))

  (define bool-df
    (dataframe-new
     (list (series-new-i32 "x" '(1 2 3 4 5))
           (series-new-str "s" '("a" "b" "a" "b" "c")))))

  ;; Compose two masks: x > 2 AND s == "a"
  (define m1 (series-gt-i32 (dataframe-column bool-df "x") 2))
  (define m2 (series-eq-str (dataframe-column bool-df "s") "a"))
  (check-equal? (dataframe-height (dataframe-filter bool-df (series-and m1 m2)))
                1) ;; only x=3,s="a"
  (check-equal? (dataframe-height (dataframe-filter bool-df (series-or m1 m2)))
                4) ;; x>2 OR s=="a" : x=1,s="a"; x=3,s="a"; x=3,s="a"; x=4; x=5 -> 4 distinct rows
  (check-equal? (dataframe-height (dataframe-filter bool-df (series-not m1)))
                2) ;; x in {1,2}
  (check-equal? (series-dtype (series-and m1 m2)) 'boolean)

  ;; is-null / is-not-null
  (define non-null-mask (series-is-not-null (dataframe-column bool-df "x")))
  (check-equal? (dataframe-height (dataframe-filter bool-df non-null-mask)) 5)
  (define null-mask (series-is-null (dataframe-column bool-df "x")))
  (check-equal? (dataframe-height (dataframe-filter bool-df null-mask)) 0)

  (check-pred DataFrame-ptr? (dataframe-make))
  (check-pred DataFrame-ptr? (dataframe-empty))
  (check-pred void? (dataframe-drop (dataframe-make)))
  (check-pred void? (dataframe-drop (dataframe-empty)))

  (define-values (r c)
    (dataframe-shape (dataframe-make)))
  (check-equal? r 0)
  (check-equal? c 0)

  (define-values (er ec)
    (dataframe-shape (dataframe-empty)))
  (check-equal? er 0)
  (check-equal? ec 0)

  (define example-df
    (dataframe-new
     (list (series-new-str "user" '("alice" "bob" "carol" "dora"))
           (series-new-i32 "score" '(10 25 18 41))
           (series-new-f64 "cost" '(1.2 3.5 2.0 8.4)))))
  (check-pred DataFrame-ptr? example-df)
  (define-values (dr dc) (dataframe-shape example-df))
  (check-equal? dr 4)
  (check-equal? dc 3)
  (check-equal? (dataframe-height example-df) 4)
  (check-equal? (dataframe-width example-df) 3)
  (check-equal? (dataframe-column-name example-df 0) "user")
  (check-equal? (dataframe-column-name example-df 1) "score")
  (check-equal? (dataframe-column-name example-df 2) "cost")

  (define score-col (dataframe-column example-df "score"))
  (check-pred Series-ptr? score-col)
  (check-equal? (series-name score-col) "score")
  (check-equal? (series-dtype score-col) 'int32)
  (check-equal? (series-len score-col) 4)
  (check-equal? (series-sum-i32 score-col) 94)
  (check-exn #rx"^dataframe-column: no column named \"points\"$"
             (lambda () (dataframe-column example-df "points")))

  ;; column-names helper
  (check-equal? (dataframe-column-names example-df)
                '("user" "score" "cost"))

  ;; head / tail / slice
  (check-equal? (dataframe-height (dataframe-head example-df 2)) 2)
  (check-equal? (dataframe-height (dataframe-tail example-df 2)) 2)
  (check-equal? (series-sum-i32
                 (dataframe-column (dataframe-head example-df 2) "score"))
                35) ;; 10 + 25
  (check-equal? (series-sum-i32
                 (dataframe-column (dataframe-tail example-df 2) "score"))
                59) ;; 18 + 41
  (check-equal? (dataframe-height (dataframe-slice example-df 1 2)) 2)
  (check-equal? (series-sum-i32
                 (dataframe-column (dataframe-slice example-df 1 2) "score"))
                43) ;; 25 + 18

  ;; Column ops
  (define just-score (dataframe-select example-df '("score")))
  (check-equal? (dataframe-width just-score) 1)
  (check-equal? (dataframe-column-names just-score) '("score"))
  (check-equal? (dataframe-column-names
                 (dataframe-select example-df (list #"score" (string->path "cost") "user")))
                '("score" "cost" "user"))

  (define no-cost (dataframe-drop-columns example-df '("cost")))
  (check-equal? (dataframe-column-names no-cost) '("user" "score"))

  (define renamed (dataframe-rename example-df "score" "points"))
  (check-equal? (dataframe-column-names renamed) '("user" "points" "cost"))
  (check-equal? (series-sum-i32 (dataframe-column renamed "points")) 94)

  (define with-bonus
    (dataframe-with-column example-df
                           (series-new-i32 "bonus" '(1 2 3 4))))
  (check-equal? (dataframe-column-names with-bonus)
                '("user" "score" "cost" "bonus"))
  (check-equal? (series-sum-i32 (dataframe-column with-bonus "bonus")) 10)

  ;; with-column replaces if name already exists
  (define replaced
    (dataframe-with-column example-df
                           (series-new-i32 "score" '(0 0 0 0))))
  (check-equal? (dataframe-width replaced) 3) ;; not 4
  (check-equal? (series-sum-i32 (dataframe-column replaced "score")) 0)

  (define stacked-cols
    (dataframe-hstack example-df
                      (list (series-new-i32 "rank" '(4 2 3 1))
                            (series-new-str "tier" '("b" "a" "b" "a")))))
  (check-equal? (dataframe-column-names stacked-cols)
                '("user" "score" "cost" "rank" "tier"))
  (check-equal? (series-sum-i32 (dataframe-column stacked-cols "rank")) 10)
  (check-exn #rx"^dataframe-hstack: [^\n]*'score'"
             (lambda ()
               (dataframe-hstack
                example-df
                (list (series-new-i32 "score" '(1 2 3 4))))))
  (check-exn #rx"^dataframe-hstack: [^\n]*'too-short'"
             (lambda ()
               (dataframe-hstack
                example-df
                (list (series-new-i32 "too-short" '(1 2))))))

  ;; --- Example 3: filter / sort / group-by ---
  (define ops-df
    (dataframe-new
     (list (series-new-str "group" '("a" "a" "b" "b" "c"))
           (series-new-i32 "value" '(10 25 7 30 18))
           (series-new-f64 "cost"  '(1.2 2.4 0.5 3.1 1.8)))))

  ;; filter value > 15
  (define mask (series-gt-i32 (dataframe-column ops-df "value") 15))
  (check-equal? (series-dtype mask) 'boolean)
  (define filtered (dataframe-filter ops-df mask))
  (check-equal? (dataframe-height filtered) 3) ;; 25, 30, 18
  (check-equal?
   (series-sum-i32 (dataframe-column filtered "value"))
   73)

  ;; sort by group asc, value desc
  (define sorted
    (dataframe-sort ops-df '("group" "value") #:descending '(#f #t)))
  (check-equal? (dataframe-height sorted) 5)
  ;; First row of each group should be the max value within that group.
  ;; (a, 25), (b, 30), (c, 18) -> sum = 73
  ;; Just spot-check the value column came back sorted.
  (let ([vs (dataframe-column sorted "value")])
    (check-equal? (series-len vs) 5))

  ;; group by group, sum value
  (define grouped
    (dataframe-group-by-sum ops-df #:by '("group") #:agg '("value")))
  (check-equal? (dataframe-height grouped) 3)
  (check-equal? (dataframe-width grouped) 2) ;; group + value
  (check-equal?
   (series-sum-i32 (dataframe-column grouped "value_sum"))
   90) ;; 35 + 37 + 18

  ;; Mean / min / max / count
  (define grouped-mean
    (dataframe-group-by-mean ops-df #:by '("group") #:agg '("value")))
  (check-equal? (dataframe-height grouped-mean) 3)
  ;; means: a=17.5, b=18.5, c=18 — sum = 54
  (check-= (series-sum-f64 (dataframe-column grouped-mean "value_mean"))
           54.0 1e-9)

  (define grouped-min
    (dataframe-group-by-min ops-df #:by '("group") #:agg '("value")))
  ;; mins: a=10, b=7, c=18 — sum = 35
  (check-equal? (series-sum-i32 (dataframe-column grouped-min "value_min")) 35)

  (define grouped-max
    (dataframe-group-by-max ops-df #:by '("group") #:agg '("value")))
  ;; maxes: a=25, b=30, c=18 — sum = 73
  (check-equal? (series-sum-i32 (dataframe-column grouped-max "value_max")) 73)

  (define grouped-count
    (dataframe-group-by-count ops-df #:by '("group") #:agg '("value")))
  ;; counts: a=2, b=2, c=1 — total rows = 5
  (check-equal? (dataframe-height grouped-count) 3)

  ;; --- Dedup + null cleanup ---
  (define dup-df
    (dataframe-new
     (list (series-new-i32 "x" '(1 2 1 3 2 1))
           (series-new-str "y" '("a" "b" "a" "c" "b" "a")))))
  (check-equal? (dataframe-height (dataframe-unique dup-df)) 3)

  (define np-df
    (dataframe-new
     (list (series-new-str "name" '("a" "b" "c"))
           (series-new-i64 "score" (list 10 polars-null 30)))))
  (check-equal? (dataframe-height np-df) 3)
  (check-equal? (dataframe-height (dataframe-drop-nulls np-df)) 2)

  ;; --- Joins + vstack ---
  (define users-df
    (dataframe-new
     (list (series-new-i32 "uid" '(1 2 3 4))
           (series-new-str "name" '("alice" "bob" "carol" "dora")))))
  (define orders-df
    (dataframe-new
     (list (series-new-i32 "uid" '(1 2 2 5))
           (series-new-i32 "amount" '(10 20 30 40)))))

  (define inner (dataframe-join users-df orders-df #:on '("uid") #:how 'inner))
  (check-equal? (dataframe-height inner) 3) ;; uid 1,2,2

  (define left (dataframe-join users-df orders-df #:on '("uid") #:how 'left))
  (check-equal? (dataframe-height left) 5) ;; 1,2,2,3 (null),4 (null)

  (define outer (dataframe-join users-df orders-df #:on '("uid") #:how 'outer))
  (check-equal? (dataframe-height outer) 6) ;; 1,2,2,3,4,5

  (define semi (dataframe-join users-df orders-df #:on '("uid") #:how 'semi))
  (check-equal? (dataframe-height semi) 2) ;; uid 1,2
  (check-equal? (dataframe-column-names semi) '("uid" "name"))

  (define anti (dataframe-join users-df orders-df #:on '("uid") #:how 'anti))
  (check-equal? (dataframe-height anti) 2) ;; uid 3,4
  (check-equal? (dataframe-column-names anti) '("uid" "name"))

  (define observations-df
    (dataframe-new
     (list (series-new-i32 "time" '(1 3 5))
           (series-new-i32 "reading" '(100 300 500)))))
  (define calibration-df
    (dataframe-new
     (list (series-new-i32 "time" '(1 2 4))
           (series-new-i32 "offset" '(10 20 40)))))
  (define asof-backward
    (dataframe-join-asof observations-df calibration-df
                         #:on "time"
                         #:strategy 'backward))
  (check-equal? (dataframe-height asof-backward) 3)
  (check-equal? (series-sum-i32 (dataframe-column asof-backward "offset")) 70)

  (define asof-exact
    (dataframe-join-asof observations-df calibration-df
                         #:on "time"
                         #:strategy 'backward
                         #:tolerance 0))
  (check-equal? (series-sum-i32 (dataframe-column asof-exact "offset")) 10)
  (check-equal? (series-null-count (dataframe-column asof-exact "offset")) 2)

  (define grouped-observations-df
    (dataframe-new
     (list (series-new-str "sensor" '("a" "a" "b" "b"))
           (series-new-i32 "time" '(3 5 3 5))
           (series-new-i32 "reading" '(300 500 30 50)))))
  (define grouped-calibration-df
    (dataframe-new
     (list (series-new-str "sensor" '("a" "a" "b" "b"))
           (series-new-i32 "time" '(1 4 1 4))
           (series-new-i32 "offset" '(10 40 100 400)))))
  (define asof-by
    (dataframe-join-asof grouped-observations-df grouped-calibration-df
                         #:on "time"
                         #:by '("sensor")
                         #:strategy 'backward))
  (check-equal? (series-sum-i32 (dataframe-column asof-by "offset")) 550)
  (define asof-by-tolerance
    (dataframe-join-asof grouped-observations-df grouped-calibration-df
                         #:on "time"
                         #:by '("sensor")
                         #:strategy 'backward
                         #:tolerance 0))
  (check-equal? (series-null-count (dataframe-column asof-by-tolerance "offset")) 4)

  (define crossed
    (dataframe-join (dataframe-head users-df 2) (dataframe-head orders-df 2)
                    #:how 'cross))
  (check-equal? (dataframe-height crossed) 4) ;; 2 * 2
  (for ([->name (list string->bytes/utf-8 string->path)])
    (check-equal? (dataframe-height
                   (dataframe-join users-df orders-df #:on (list (->name "uid")) #:how 'inner))
                  3)
    (check-equal? (series-sum-i32
                   (dataframe-column (dataframe-join-asof grouped-observations-df
                                                          grouped-calibration-df
                                                          #:on (->name "time")
                                                          #:by (list (->name "sensor")))
                                     "offset"))
                  550))

  ;; vstack — append rows from a compatible dataframe
  (define more-users
    (dataframe-new
     (list (series-new-i32 "uid" '(5 6))
           (series-new-str "name" '("eve" "frank")))))
  (check-equal? (dataframe-height (dataframe-vstack users-df more-users)) 6)

  ;; --- Pivot / unpivot ---
  (define sales-df
    (dataframe-new
     (list (series-new-str "store" '("a" "a" "b" "b"))
           (series-new-str "quarter" '("q1" "q2" "q1" "q2"))
           (series-new-i32 "sales" '(10 20 30 40)))))
  (define pivoted-sales
    (dataframe-pivot sales-df
                     #:on '("quarter")
                     #:index '("store")
                     #:values '("sales")
                     #:agg 'sum))
  (check-equal? (dataframe-column-names pivoted-sales) '("store" "q1" "q2"))
  (check-equal? (series-sum-i32 (dataframe-column pivoted-sales "q1")) 40)
  (check-equal? (series-sum-i32 (dataframe-column pivoted-sales "q2")) 60)

  (define unpivoted-sales
    (dataframe-unpivot pivoted-sales
                       #:on '("q1" "q2")
                       #:index '("store")))
  (check-equal? (dataframe-height unpivoted-sales) 4)
  (check-equal? (dataframe-column-names unpivoted-sales)
                '("store" "variable" "value"))
  (check-equal? (series-sum-i32 (dataframe-column unpivoted-sales "value")) 100)

  (define ((sort-blame? rx) e)
    (and (exn:fail:contract:blame? e) (regexp-match? rx (exn-message e))))
  (define sort-src (dataframe-new (list (series-new-i64 "x" (list 3 polars-null 1))
                                        (series-new-i64 "y" '(1 2 3)))))
  (check-exn (sort-blame? #rx"^dataframe-sort: contract violation.*#:descending \\(2\\) does not match the number of sort keys \\(1\\)")
             (lambda () (contracted:dataframe-sort sort-src '("x") #:descending '(#t #f))))
  (check-exn (sort-blame? #rx"^dataframe-sort: contract violation")
             (lambda () (contracted:dataframe-sort sort-src '())))
  (check-exn (sort-blame? #rx"^dataframe-sort: contract violation")
             (lambda () (contracted:dataframe-sort sort-src "x")))
  (check-exn (sort-blame? #rx"^series-sort: contract violation")
             (lambda () (contracted:series-sort (series-new-i64 "x" '(1)) #:nulls-last '(#t))))
  (check-exn #rx"^dataframe-sort: not found: \"nope\" not found$"
             (lambda () (contracted:dataframe-sort sort-src '("nope"))))
  (check-equal? (let ([s (contracted:series-sort (dataframe-column sort-src "x") #:nulls-last #t)])
                  (for/list ([i (in-range (series-len s))]) (series-ref s i)))
                (list 1 3 polars-null))

  (settle!)
  (let ([before (dataframe-drop-count)])
    (dataframe-drop (contracted:dataframe-sort sort-src '("x") #:descending #t #:nulls-last #t
                                               #:maintain-order #t))
    (settle!)
    (check-equal? (- (dataframe-drop-count) before) 1))
  (let ([before (dataframe-drop-count)])
    (for ([_ (in-range 20)])
      (contracted:dataframe-sort sort-src '("x" "y") #:nulls-last '(#t #f)))
    (settle!)
    (check >= (- (dataframe-drop-count) before) 10))

  (define (releases count thunk)
    (define before (count))
    (for ([_ (in-range 20)])
      (thunk))
    (let wait ([tries 0])
      (collect-garbage (if (< tries 4) 'minor 'major))
      (sleep 0.001)
      (when (and (< (- (count) before) 20) (< tries 12))
        (wait (add1 tries))))
    (- (count) before))

  (define (drops-once count drop make)
    (settle!)
    (define before (count))
    (drop (make))
    (settle!)
    (- (count) before))

  (define owned-i32 (series-new-i32 "x" '(3 1 4 1 5)))
  (define owned-i64 (series-new-i64 "w" '(3 1 4 1 5)))
  (define owned-u32 (series-new-u32 "u" '(3 1 4 1 5)))
  (define owned-u64 (series-new-u64 "v" '(3 1 4 1 5)))
  (define owned-f64 (series-new-f64 "f" '(3.0 1.0 4.0 1.0 5.0)))
  (define owned-str (series-new-str "s" '("a" "b" "a" "c" "b")))
  (define owned-bool (series-new-bool "b" '(#t #f #t #t #f)))
  (define owned-enum (series-cast owned-str '(enum a b c)))
  (define owned-zoned (series-cast owned-i64 '(datetime microseconds "Europe/Brussels")))
  (define owned-stamp (make-YMDHMS 2024 1 2 3 4 5))
  (define owned-frame
    (dataframe-new (list (series-new-i32 "x" '(1 2 1))
                         (series-new-str "k" '("p" "q" "p"))
                         (series-new-i32 "v" '(10 20 30)))))
  (define owned-mask (series-new-bool "m" '(#t #f #t)))
  (define owned-extra (series-new-i32 "e" '(7 8 9)))

  (define series-cases
    (list (list 'series-empty series-empty)
          (list 'series-sort (lambda () (series-sort owned-i32 #:descending #t)))
          (list 'dataframe-column (lambda () (dataframe-column owned-frame "x")))
          (list 'series-head (lambda () (series-head owned-i32 2)))
          (list 'series-tail (lambda () (series-tail owned-i32 2)))
          (list 'series-slice (lambda () (series-slice owned-i32 1 2)))
          (list 'series-reverse (lambda () (series-reverse owned-i32)))
          (list 'series-drop-nulls (lambda () (series-drop-nulls owned-i32)))
          (list 'series-unique (lambda () (series-unique owned-i32)))
          (list 'series-is-null (lambda () (series-is-null owned-i32)))
          (list 'series-is-not-null (lambda () (series-is-not-null owned-i32)))
          (list 'series-and (lambda () (series-and owned-bool owned-bool)))
          (list 'series-or (lambda () (series-or owned-bool owned-bool)))
          (list 'series-xor (lambda () (series-xor owned-bool owned-bool)))
          (list 'series-not (lambda () (series-not owned-bool)))
          (list 'series-lt-i32 (lambda () (series-lt-i32 owned-i32 3)))
          (list 'series-le-i32 (lambda () (series-le-i32 owned-i32 3)))
          (list 'series-gt-i32 (lambda () (series-gt-i32 owned-i32 3)))
          (list 'series-ge-i32 (lambda () (series-ge-i32 owned-i32 3)))
          (list 'series-eq-i32 (lambda () (series-eq-i32 owned-i32 3)))
          (list 'series-ne-i32 (lambda () (series-ne-i32 owned-i32 3)))
          (list 'series-lt-f64 (lambda () (series-lt-f64 owned-f64 3.0)))
          (list 'series-le-f64 (lambda () (series-le-f64 owned-f64 3.0)))
          (list 'series-gt-f64 (lambda () (series-gt-f64 owned-f64 3.0)))
          (list 'series-ge-f64 (lambda () (series-ge-f64 owned-f64 3.0)))
          (list 'series-eq-f64 (lambda () (series-eq-f64 owned-f64 3.0)))
          (list 'series-ne-f64 (lambda () (series-ne-f64 owned-f64 3.0)))
          (list 'series-eq-str (lambda () (series-eq-str owned-str "a")))
          (list 'series-ne-str (lambda () (series-ne-str owned-str "a")))
          (list 'series-cast (lambda () (series-cast owned-i32 'float64)))
          (list 'series-cast/categorical (lambda () (series-cast owned-str 'categorical)))
          (list 'series-cast-enum/raw (lambda () (series-cast owned-str '(enum a b c))))
          (list 'series-enum-categories/raw
                (lambda () (series-enum-categories/raw owned-enum)))
          (list 'series-cast-datetime-tz/raw
                (lambda () (series-cast owned-i64 '(datetime microseconds "UTC"))))
          (list 'series-dt-convert-time-zone/raw
                (lambda () (series-dt-convert-time-zone 'test owned-zoned "Asia/Tokyo")))
          (list 'series-dt-replace-time-zone/raw
                (lambda () (series-dt-replace-time-zone 'test owned-zoned #f 'raise 'raise)))
          (list 'series-new-bool (lambda () (series-new-bool "b" '(#t #f))))
          (list 'series-new-bool/opt (lambda () (series-new-bool "b" (list #t polars-null))))
          (list 'series-new-bool/vec (lambda () (series-new-bool/vec "b" (vector #t #f))))
          (list 'series-new-null (lambda () (series-new-null "n" 2)))))

  (define series-op-cases
    (for/list ([op (in-list (list series-eq series-ne series-gt series-ge series-lt series-le
                                  series-add series-sub series-mul series-div series-mod))])
      (list (object-name op) (lambda () (op owned-i32 owned-i32)))))

  (define scalar-op-cases
    (for*/list ([family (in-list
                         (list (list owned-i32 1 series-add-i32 series-sub-i32 series-mul-i32
                                     series-div-i32 series-mod-i32)
                               (list owned-i64 1 series-add-i64 series-sub-i64 series-mul-i64
                                     series-div-i64 series-mod-i64)
                               (list owned-u32 1 series-add-u32 series-sub-u32 series-mul-u32
                                     series-div-u32 series-mod-u32)
                               (list owned-u64 1 series-add-u64 series-sub-u64 series-mul-u64
                                     series-div-u64 series-mod-u64)
                               (list owned-f64 1.0 series-add-f64 series-sub-f64 series-mul-f64
                                     series-div-f64 series-mod-f64)))]
                [op (in-list (cddr family))])
      (list (object-name op) (lambda () (op (car family) (cadr family))))))

  (define constructor-cases
    (for*/list ([ctor (in-list (list (list series-new-i8 series-new-i8/vec 1)
                                     (list series-new-i16 series-new-i16/vec 1)
                                     (list series-new-i32 series-new-i32/vec 1)
                                     (list series-new-i64 series-new-i64/vec 1)
                                     (list series-new-u8 series-new-u8/vec 1)
                                     (list series-new-u16 series-new-u16/vec 1)
                                     (list series-new-u32 series-new-u32/vec 1)
                                     (list series-new-u64 series-new-u64/vec 1)
                                     (list series-new-f32 series-new-f32/vec 1.0)
                                     (list series-new-f64 series-new-f64/vec 1.0)
                                     (list series-new-str series-new-str/vec "a")
                                     (list series-new-ymdhms series-new-ymdhms/vec owned-stamp)))]
                [shape (in-list '(list opt vec))])
      (define-values (from-list from-vector value) (apply values ctor))
      (list (format "~a ~a" (object-name from-list) shape)
            (case shape
              [(list) (lambda () (from-list "c" (list value value)))]
              [(opt) (lambda () (from-list "c" (list value polars-null)))]
              [(vec) (lambda () (from-vector "c" (vector value value)))]))))

  (define dataframe-cases
    (list (list 'dataframe-make dataframe-make)
          (list 'dataframe-empty dataframe-empty)
          (list 'dataframe-head (lambda () (dataframe-head owned-frame 2)))
          (list 'dataframe-tail (lambda () (dataframe-tail owned-frame 2)))
          (list 'dataframe-slice (lambda () (dataframe-slice owned-frame 1 2)))
          (list 'dataframe-sort (lambda () (dataframe-sort owned-frame '("v"))))
          (list 'dataframe-new (lambda () (dataframe-new (list owned-i32 owned-str))))
          (list 'dataframe-select (lambda () (dataframe-select owned-frame '("x"))))
          (list 'dataframe-drop-columns (lambda () (dataframe-drop-columns owned-frame '("x"))))
          (list 'dataframe-rename (lambda () (dataframe-rename owned-frame "x" "y")))
          (list 'dataframe-with-column (lambda () (dataframe-with-column owned-frame owned-extra)))
          (list 'dataframe-hstack (lambda () (dataframe-hstack owned-frame (list owned-extra))))
          (list 'dataframe-filter (lambda () (dataframe-filter owned-frame owned-mask)))
          (list 'dataframe-unique (lambda () (dataframe-unique owned-frame)))
          (list 'dataframe-drop-nulls (lambda () (dataframe-drop-nulls owned-frame)))
          (list 'dataframe-vstack (lambda () (dataframe-vstack owned-frame owned-frame)))
          (list 'dataframe-join (lambda () (dataframe-join owned-frame owned-frame #:on '("x"))))
          (list 'dataframe-join-asof
                (lambda () (dataframe-join-asof owned-frame owned-frame #:on "v")))
          (list 'dataframe-join-asof/raw
                (lambda () (dataframe-join-asof/raw owned-frame owned-frame "v" "v" 1)))
          (list 'dataframe-pivot
                (lambda () (dataframe-pivot owned-frame #:on '("k") #:index '("x")
                                            #:values '("v") #:agg 'sum)))
          (list 'dataframe-unpivot
                (lambda () (dataframe-unpivot owned-frame #:on '("v") #:index '("x"))))
          (list 'dataframe-group-by-sum
                (lambda () (dataframe-group-by-sum owned-frame #:by '("k") #:agg '("v"))))
          (list 'dataframe-group-by-mean
                (lambda () (dataframe-group-by-mean owned-frame #:by '("k") #:agg '("v"))))
          (list 'dataframe-group-by-min
                (lambda () (dataframe-group-by-min owned-frame #:by '("k") #:agg '("v"))))
          (list 'dataframe-group-by-max
                (lambda () (dataframe-group-by-max owned-frame #:by '("k") #:agg '("v"))))
          (list 'dataframe-group-by-count
                (lambda () (dataframe-group-by-count owned-frame #:by '("k") #:agg '("v"))))))

  (settle!)
  (for ([owned (in-list (append series-cases series-op-cases scalar-op-cases constructor-cases))])
    (check >= (releases series-drop-count (cadr owned)) 10 (format "~a" (car owned))))
  (for ([owned (in-list dataframe-cases)])
    (check >= (releases dataframe-drop-count (cadr owned)) 10 (format "~a" (car owned))))

  (check-equal? (drops-once series-drop-count series-drop
                            (lambda () (series-head owned-i32 2)))
                1)
  (check-equal? (drops-once series-drop-count series-drop
                            (lambda () (series-cast owned-i32 'float64)))
                1)
  (check-equal? (drops-once series-drop-count series-drop
                            (lambda () (series-add-i32 owned-i32 1)))
                1)
  (check-equal? (drops-once series-drop-count series-drop
                            (lambda () (series-new-i32 "c" '(1 2))))
                1)
  (check-equal? (drops-once series-drop-count series-drop
                            (lambda () (series-cast owned-str '(enum a b c))))
                1)
  (check-equal? (drops-once series-drop-count series-drop
                            (lambda () (series-cast owned-i64 '(datetime nanoseconds "UTC"))))
                1)
  (check-equal? (drops-once series-drop-count series-drop
                            (lambda () (series-dt-convert-time-zone 'test owned-zoned "UTC")))
                1)
  (check-equal? (drops-once dataframe-drop-count dataframe-drop
                            (lambda () (dataframe-hstack owned-frame (list owned-extra))))
                1)
  (check-equal? (drops-once dataframe-drop-count dataframe-drop
                            (lambda () (dataframe-pivot owned-frame #:on '("k") #:index '("x")
                                                        #:values '("v"))))
                1)

  (check-exn #rx"^series-not: invalid series dtype: expected `Boolean`, got `i32`"
             (lambda () (series-not owned-i32)))
  (check-exn #rx"^series-and: invalid series dtype: expected `Boolean`, got `i32`"
             (lambda () (series-and owned-i32 owned-bool)))
  (check-exn #rx"^series-lt-i32: invalid series dtype: expected `Int32`, got `f64` .*`f`$"
             (lambda () (series-lt-i32 owned-f64 1)))
  (check-exn #rx"^series-eq-str: cannot compare string with numeric type \\(i32\\)$"
             (lambda () (series-eq-str owned-i32 "a")))
  (check-exn #rx"^series-add-i32: invalid series dtype: expected `Int32`, got `f64` .*`f`$"
             (lambda () (series-add-i32 owned-f64 1)))

  (define scalar-op-rows
    '((Int32 f64 1 series-add-i32 series-sub-i32 series-mul-i32 series-div-i32 series-mod-i32
             series-lt-i32 series-le-i32 series-gt-i32 series-ge-i32 series-eq-i32 series-ne-i32)
      (Int64 f64 1 series-add-i64 series-sub-i64 series-mul-i64 series-div-i64 series-mod-i64)
      (UInt32 f64 1 series-add-u32 series-sub-u32 series-mul-u32 series-div-u32 series-mod-u32)
      (UInt64 f64 1 series-add-u64 series-sub-u64 series-mul-u64 series-div-u64 series-mod-u64)
      (Float64 i32 1.0 series-add-f64 series-sub-f64 series-mul-f64 series-div-f64
               series-mod-f64 series-lt-f64 series-le-f64 series-gt-f64 series-ge-f64
               series-eq-f64 series-ne-f64)))
  (define wrong-series
    (hash 'f64 (lambda () (series-new-f64 "wrong" '(1.0 2.0)))
          'i32 (lambda () (series-new-i32 "wrong" '(1 2)))))
  (settle!)
  (define drops-before-wrong-dtypes (series-drop-count))
  (define scalar-op-count
    (for/sum ([row (in-list scalar-op-rows)])
      (match-define (list* dtype wrong v ops) row)
      (with-release ([s ((hash-ref wrong-series wrong)) series-drop])
        (for ([op (in-list ops)])
          (check-exn (regexp (format "^~a: invalid series dtype: expected `~a`, got `~a` .*`wrong`$"
                                     op dtype wrong))
                     (lambda () ((dynamic-require 'polars/private/foreign op) s v))
                     (symbol->string op))))
      (length ops)))
  (check-equal? scalar-op-count 37)
  (check >= (- (series-drop-count) drops-before-wrong-dtypes) (length scalar-op-rows)
         "each wrong-dtype series is released at the end of its row")

  (check-exn #rx"^series-not: " (lambda () (series-not owned-i32)))
  (check-not-false (last-error-message) "series-not leaves its reason in the slot")
  (series-drop (series-add-i32 owned-i32 1))
  (check-false (last-error-message) "series-add-i32 clears the slot on entry")
  (check-equal? (series->list (series-add-f64 owned-f64 1)) '(4.0 2.0 5.0 2.0 6.0))
  (check-equal? (series->list (series-mul-f64 owned-f64 1/2)) '(1.5 0.5 2.0 0.5 2.5))
  (check-equal? (series->list (series-lt-f64 owned-f64 3)) '(#f #t #f #t #f))
  (check-exn #rx"^series-add-f64: contract violation\n  expected: real\\?"
             (lambda () (series-add-f64 owned-f64 'x)))
  (check-exn #rx"^series-eq-f64: contract violation\n  expected: Series-ptr\\?"
             (lambda () (series-eq-f64 'x 1.0)))
  (check-exn #rx"^series-new-i32/vec: contract violation"
             (lambda () (series-new-i32/vec #f (vector 1))))
  (check-exn #rx"^dataframe-new: operation failed$"
             (lambda () (dataframe-new (list owned-i32 (series-head owned-i32 2)))))
  (check-exn #rx"^dataframe-drop-columns: [^\n]*\"nope\""
             (lambda () (dataframe-drop-columns owned-frame '("nope"))))
  (check-exn #rx"^dataframe-vstack: [^\n]*unable to append to a DataFrame of shape"
             (lambda () (dataframe-vstack owned-frame (dataframe-select owned-frame '("x")))))
  (check-exn #rx"^dataframe-filter: operation failed$"
             (lambda () (dataframe-filter owned-frame owned-i32)))
  (check-exn #rx"^dataframe-join-asof: [^\n]*\"nope\""
             (lambda () (dataframe-join-asof owned-frame owned-frame #:on "nope")))

  (define owned-drops
    (hash '_Series-ptr 'series-drop '_Series-ptr/null 'series-drop
          '_DataFrame-ptr 'dataframe-drop '_DataFrame-ptr/null 'dataframe-drop
          '_Expr-ptr 'expr-drop '_Expr-ptr/null 'expr-drop
          '_LazyFrame-ptr 'lazyframe-drop '_LazyFrame-ptr/null 'lazyframe-drop))

  (define (compat-forms v)
    (cond
      [(and (pair? v) (eq? (car v) 'define-compat)) (list v)]
      [(pair? v) (append (compat-forms (car v)) (compat-forms (cdr v)))]
      [else '()]))

  (define (result-type signature)
    (match (memq '-> signature)
      [(list* '-> (list _ ': type) _) type]
      [(list* '-> type _) type]
      [_ #f]))

  (define (releases-result? form)
    (match form
      [(list* 'define-compat _ (list* _ signature) options)
       (define type (result-type signature))
       (define drop (hash-ref owned-drops type #f))
       (cond
         [(eq? type '_pointer) #f]
         [drop (match (memq '#:wrap options)
                 [(list* _ (list* (or 'allocator 'allocator/or-fail) (== drop) _) _) #t]
                 [_ #f])]
         [else #t])]
      [_ #t]))

  (define (compat-bindings sources)
    (for*/list ([file (in-list sources)]
                [form (in-list (compat-forms (read-source file)))])
      form))
  (define bindings (compat-bindings (polars-sources)))
  (define compat 'define-compat)
  (check-true (releases-result?
               `(,compat good (_fun _string -> _DataFrame-ptr/null) #:wrap (allocator dataframe-drop))))
  (check-false (releases-result?
                `(,compat swapped (_fun _string -> _DataFrame-ptr/null)
                          #:wrap (allocator lazyframe-drop))))
  (check-false (releases-result? `(,compat unwrapped (_fun _string -> _LazyFrame-ptr/null))))
  (check > (length bindings) 200)
  (define (shared-signature-result form)
    (match form
      [(list* 'define-compat (or 'dataframe-read-csv/raw 'lazyframe-scan-ndjson/raw)
              (cons _ signature) _)
       (result-type signature)]
      [_ #f]))
  (check-equal? (for*/list ([form (in-list bindings)]
                            [type (in-value (shared-signature-result form))]
                            #:when type)
                  type)
                '(_DataFrame-ptr/null _LazyFrame-ptr/null))
  (check-equal? (for/list ([form (in-list bindings)]
                           #:unless (releases-result? form))
                  (cadr form))
                '())
  (define (discards-reason? form)
    (match* ((memq '#:c-id form) (memq '#:wrap form))
      [((list* _ (? symbol? id) _) (list* _ (list* 'allocator/or-fail _) _))
       (regexp-match? #rx"_v[0-9]+$" (symbol->string id))]
      [(_ _) #f]))
  (check-true (discards-reason? `(,compat p (_fun _str -> _Expr-ptr/null) #:c-id p_v2
                                          #:wrap (allocator/or-fail expr-drop 'p))))
  (check-false (discards-reason? `(,compat p (_fun _str -> _Expr-ptr/null) #:c-id p_v2
                                           #:wrap (allocator expr-drop))))
  (check-equal? (for/list ([form (in-list bindings)] #:when (discards-reason? form)) (cadr form))
                '()
                "a v2 entry point records its reason: read it with call/foreign-error")
  (define (fails-without-reason? form)
    (match form
      [(list 'define-compat _ ... '#:wrap (list 'allocator/or-fail _ ...) _ ...) #t]
      [_ #f]))
  (define (macro-name form)
    (match form
      [(list* (or 'define-syntax-parse-rule 'define-syntax-parser) (or (cons name _) name) _)
       #:when (symbol? name)
       name]
      [_ #f]))
  (define (elements v)
    (match v
      [(cons a d) (cons a (elements d))]
      [_ '()]))
  (define (subforms v)
    (if (pair? v) (cons v (append-map subforms (elements v))) '()))
  (define (or-fail-sites sources)
    (define tops (map read-source sources))
    (define definitions
      (for*/list ([top (in-list tops)] [form (in-list (subforms top))] #:when (macro-name form))
        form))
    (define (generates? body generators)
      (for/or ([form (in-list (subforms body))])
        (or (fails-without-reason? form) (and (memq (car form) generators) #t))))
    (define generators
      (let grow ([names '()])
        (define next
          (for/list ([definition (in-list definitions)]
                     #:when (generates? (cddr definition) names))
            (macro-name definition)))
        (if (= (length next) (length names)) names (grow next))))
    (define (sites v)
      (cond
        [(or (not (pair? v)) (macro-name v)) '()]
        [(fails-without-reason? v) (list (cadr v))]
        [(memq (car v) generators) (list v)]
        [else (append-map sites (elements v))]))
    (append-map sites tops))
  (check-equal? (sort (or-fail-sites (polars-sources #:dirs '("private"))) string<?
                      #:key (lambda (site) (format "~s" site)))
                (call-with-input-file (build-path polars-dir "tests" "allocator-or-fail-sites.rktd")
                  read)
                "a new allocator/or-fail discards any reason the entry point records")
  (with-planted-sources (root ["private/planted.rkt"
                               (format "#lang racket/base\n~s\n~s\n~s\n~s\n~s"
                                       `(define-syntax-parse-rule (gen n:id)
                                          (,compat n (_fun -> _Series-ptr/null)
                                                   #:wrap (allocator/or-fail series-drop 'n)))
                                       '(define-syntax-parse-rule (gen2 n:id) (gen n))
                                       '(gen a)
                                       '(gen2 b)
                                       `(,compat direct (_fun -> _Series-ptr/null)
                                                 #:wrap (allocator/or-fail series-drop 'direct)))])
    (check-equal? (or-fail-sites (polars-sources root #:dirs '("private")))
                  '((gen a) (gen2 b) direct)))
  (with-planted-sources (root ["tests/planted.rkt"
                               (format "#lang racket/base\n~s"
                                       `(,compat planted (_fun -> _DataFrame-ptr)))])
    (check-equal? (for/list ([form (in-list (compat-bindings (polars-sources root)))]
                             #:unless (releases-result? form))
                    (cadr form))
                  '(planted)))

  (define range-series (series-new-i64 "v" '(1 2 3)))
  (define range-frame (dataframe-new (list range-series)))
  (check-equal?
   (refusal-misses
    (list (refusal 'series-std uint8/c 256 (contracted:series-std range-series #:ddof 256))
          (refusal 'series-var uint8/c -1 (contracted:series-var range-series #:ddof -1))
          (refusal 'series-new-null size/c (expt 2 64) (contracted:series-new-null "n" (expt 2 64)))
          (refusal 'series-head size/c -1 (contracted:series-head range-series -1))
          (refusal 'series-tail size/c (expt 2 64) (contracted:series-tail range-series (expt 2 64)))
          (refusal 'series-slice int64/c (expt 2 63)
                   (contracted:series-slice range-series (expt 2 63) 1))
          (refusal 'dataframe-head size/c -1 (contracted:dataframe-head range-frame -1))
          (refusal 'dataframe-tail size/c (expt 2 64)
                   (contracted:dataframe-tail range-frame (expt 2 64)))
          (refusal 'dataframe-slice size/c -1 (contracted:dataframe-slice range-frame 0 -1))
          (refusal 'series-add-i32 int32/c (expt 2 31)
                   (contracted:series-add-i32 range-series (expt 2 31)))
          (refusal 'series-mod-i64 int64/c (expt 2 63)
                   (contracted:series-mod-i64 range-series (expt 2 63)))
          (refusal 'series-sub-u32 uint32/c -1 (contracted:series-sub-u32 range-series -1))
          (refusal 'series-div-u64 uint64/c (expt 2 64)
                   (contracted:series-div-u64 range-series (expt 2 64)))
          (refusal 'series-lt-i32 int32/c (expt 2 31)
                   (contracted:series-lt-i32 range-series (expt 2 31)))))
   '())
  (check-not-exn (lambda () (contracted:series-std range-series #:ddof 255)))

  (define (block-releases thunk)
    (define before (str-block-drop-count))
    (define result (thunk))
    (list result (- (str-block-drop-count) before)))
  (define wide (dataframe-new (for/list ([i (in-range 1000)]) (series-new-i32 (format "c~a" i) '(1)))))
  (check-equal? (block-releases (lambda () (length (dataframe-column-names wide)))) '(1000 1))
  (check-equal? (block-releases (lambda () (dataframe-column-name wide 999))) '("c999" 1))
  (check-equal? (block-releases (lambda () (dataframe-column-name wide 1000))) '(#f 0))
  (check-equal? (block-releases (lambda () (series-name (series-new-i32 "x" '(1))))) '("x" 1))
  (check-equal? (block-releases (lambda () (expr-meta-output-name/raw (col 'float64)))) '(#f 0))
  (check-equal? (block-releases (lambda () (expr-meta-root-names (col 'float64)))) '(() 1))
  (check-equal? (block-releases (lambda () (series-time-zone (series-new-i32 "x" '(1))))) '(#f 0))
  (check-equal? (block-releases (lambda () (dataframe-column-names (dataframe-empty)))) '(() 1))
  (define (read-killed block)
    (kill-thread (current-thread))
    (str-block->string block))
  (define _killed-name (make-ctype _pointer #f (block-reader read-killed)))
  (define-compat series-name/killed
    (_fun _Series-ptr -> _killed-name)
    #:c-id series_name_v2)
  (define (name-in-killed-thread)
    (thread-wait (thread (lambda () (series-name/killed (series-new-i32 "x" '(1)))))))
  (check-equal? (block-releases name-in-killed-thread) (list (void) 1))

  (define c-strings '())
  (define c-string-pointer
    (function-ptr (lambda (p) (set! c-strings (cons (and p (cast p _pointer _string/utf-8)) c-strings)))
                  (_fun _pointer -> _void)))
  (define call-with-c-string (cast c-string-pointer _pointer (_fun _c-string -> _void)))
  (define call-with-c-string/null (cast c-string-pointer _pointer (_fun _c-string/null -> _void)))
  (call-with-c-string "UTC")
  (call-with-c-string/null #f)
  (call-with-c-string/null "東京")
  (check-equal? (reverse c-strings) '("UTC" #f "東京"))
  (for* ([call (list call-with-c-string call-with-c-string/null)]
         [bad (list "UTC\u0000x" "\u0000" #"UTC" 'b)])
    (check-exn #rx"^_c-string: contract violation\n  expected: a string without a NUL"
               (lambda () (call bad))))
  (check-exn #rx"^_c-string: contract violation" (lambda () (call-with-c-string #f)))
  (check-equal? (length c-strings) 3)

  (define nul-constructors
    (list (list series-new-i32 '(1)) (list series-new-i64/vec (vector 1))
          (list series-new-f64 '(1.0)) (list series-new-bool '(#t))
          (list series-new-bool/vec (vector #t)) (list series-new-str '("x"))
          (list series-new-null 1) (list series-new-ymdhms ex0)))
  (for ([n (in-list nul-names)])
    (for ([constructor (in-list nul-constructors)])
      (match-define (list make elements) constructor)
      (check-equal? (series-name (make n elements)) n))
    (check-equal? (drops-during series-drop-count
                                (lambda () (series-drop (series-new-i64 n '(1)))))
                  1)
    (define summed
      (~> (dataframe-new (list (series-new-str n '("x" "y" "x")) (series-new-i32 "a" '(1 2 3))))
          (dataframe-group-by-sum #:by (list n) #:agg '("a"))
          (dataframe-sort (list n))))
    (check-equal? (dataframe-column-names summed) (list n "a_sum"))
    (check-equal? (series-ref (dataframe-column summed "a_sum") 0) 4))
  (for ([row (in-list (nul-expected 'values))] #:when (memq (car row) '(eq ne)))
    (match row
      [(list 'eq xs v expected)
       (check-equal? (~> (series-new-str "s" xs) (series-eq-str v) series->list) expected)]
      [(list 'ne xs v expected)
       (check-equal? (~> (series-new-str "s" xs) (series-ne-str v) series->list) expected)]))
  (define empty-and-nul
    (dataframe-new (list (series-new-i32 "a\u0000b" '(1)) (series-new-i32 "" '(2))
                         (series-new-i32 "a" '(3)))))
  (check-equal? (dataframe-column-names (dataframe-select empty-and-nul '("" "a\u0000b")))
                '("" "a\u0000b"))
  (check-equal? (dataframe-column-names (dataframe-drop-columns empty-and-nul '("a\u0000b" "")))
                '("a")))
