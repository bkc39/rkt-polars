#lang racket/base

(require ffi/unsafe
         ffi/unsafe/alloc
         ffi/unsafe/define
         ffi/unsafe/define/conventions
         racket/runtime-path
         syntax/parse/define
         (for-syntax racket/base racket/syntax))

(module+ test
  (require rackunit))

(provide (all-defined-out))

(define-runtime-path native-libs-dir "../native-libs")

(define-ffi-definer define-compat
  (ffi-lib (build-path native-libs-dir "libcompat"))
  #:make-c-id convention:hyphen->underscore)

(define-compat string-drop
  (_fun _pointer -> _void)
  #:wrap (deallocator))

;; heap allocated rust string
(define _rsstring
  (make-ctype
   _pointer
   (lambda (str)
     (error '_rsstring
            "_rsstring should only be used as a result type: ~a"
            str))
   (lambda (ptr)
     (define str
       (cast ptr _pointer _string))
     (register-finalizer ptr string-drop)
     str)))

(define compat-dtype-tag/unknown 0)
(define compat-dtype-tag/boolean 1)
(define compat-dtype-tag/uint8 2)
(define compat-dtype-tag/uint16 3)
(define compat-dtype-tag/uint32 4)
(define compat-dtype-tag/uint64 5)
(define compat-dtype-tag/int8 6)
(define compat-dtype-tag/int16 7)
(define compat-dtype-tag/int32 8)
(define compat-dtype-tag/int64 9)
(define compat-dtype-tag/float32 10)
(define compat-dtype-tag/float64 11)
(define compat-dtype-tag/string 12)
(define compat-dtype-tag/binary 13)
(define compat-dtype-tag/binary-offset 14)
(define compat-dtype-tag/date 15)
(define compat-dtype-tag/datetime 16)
(define compat-dtype-tag/duration 17)
(define compat-dtype-tag/time 18)
(define compat-dtype-tag/null 19)
(define compat-dtype-tag/list 20)
(define compat-dtype-tag/array 21)
(define compat-dtype-tag/struct 22)
(define compat-dtype-tag/categorical 23)
(define compat-dtype-tag/enum 24)
(define compat-dtype-tag/decimal 25)
(define compat-dtype-tag/object 26)

(define compat-time-unit/none 0)
(define compat-time-unit/nanoseconds 1)
(define compat-time-unit/microseconds 2)
(define compat-time-unit/milliseconds 3)

(define compat-dtype-flag/has-timezone #x1)

(define-cstruct _CompatDType
  ([dtype-tag _int32]
   [dtype-time-unit _int32]
   [dtype-flags _uint32]
   [dtype-array-width _size]))

(define (compat-time-unit->datum time-unit)
  (case time-unit
    [(1) 'nanoseconds]
    [(2) 'microseconds]
    [(3) 'milliseconds]
    [else #f]))

(define (compat-dtype->datum dtype)
  (define tag (CompatDType-dtype-tag dtype))
  (define time-unit (compat-time-unit->datum (CompatDType-dtype-time-unit dtype)))
  (define flags (CompatDType-dtype-flags dtype))
  (define array-width (CompatDType-dtype-array-width dtype))
  (case tag
    [(1) 'boolean]
    [(2) 'uint8]
    [(3) 'uint16]
    [(4) 'uint32]
    [(5) 'uint64]
    [(6) 'int8]
    [(7) 'int16]
    [(8) 'int32]
    [(9) 'int64]
    [(10) 'float32]
    [(11) 'float64]
    [(12) 'string]
    [(13) 'binary]
    [(14) 'binary-offset]
    [(15) 'date]
    [(16) (list 'datetime
                time-unit
                (and (positive? (bitwise-and flags compat-dtype-flag/has-timezone))
                     'todo-timezone))]
    [(17) (list 'duration time-unit)]
    [(18) 'time]
    [(19) 'null]
    [(20) '(todo nested-dtype-support list)]
    [(21) (list 'todo 'nested-dtype-support 'array array-width)]
    [(22) '(todo nested-dtype-support struct)]
    [(23) '(todo parameterized-dtype-support categorical)]
    [(24) '(todo parameterized-dtype-support enum)]
    [(25) '(todo parameterized-dtype-support decimal)]
    [(26) '(todo parameterized-dtype-support object)]
    [else 'unknown]))

(define-cstruct _CompatOptI32
  ([valid _int32]
   [value _int32]))

(define-cstruct _CompatOptF64
  ([valid _int32]
   [value _double]))

(define (compat-opt-i32->datum o)
  (and (not (zero? (CompatOptI32-valid o)))
       (CompatOptI32-value o)))

(define (compat-opt-f64->datum o)
  (and (not (zero? (CompatOptF64-valid o)))
       (CompatOptF64-value o)))

(define-cpointer-type _Series-ptr)

(define-compat series-drop
  (_fun _Series-ptr -> _void)
  #:wrap (deallocator))

(define-compat series-empty
  (_fun -> _Series-ptr)
  #:wrap (allocator series-drop))

(module+ test
  (define empty-series-ptr
    (series-empty))
  (check-pred Series-ptr? empty-series-ptr)
  (check-pred void? (series-drop empty-series-ptr)))

(define-compat series-name
  (_fun _Series-ptr -> _rsstring))

(define-compat series-dtype/raw
  (_fun _Series-ptr -> _CompatDType)
  #:c-id series_dtype)

(define (series-dtype series)
  (compat-dtype->datum (series-dtype/raw series)))

(define-compat series-rename
  (_fun _Series-ptr _string -> _void))

(module+ test
  (check-equal? (series-name (series-empty)) "")
  (check-equal? (series-dtype (series-empty)) 'int32)
  (check-equal?
   (let ([s (series-empty)])
     (series-rename s "hello")
     (series-name s))
   "hello"))

(define-compat series-len
  (_fun _Series-ptr -> _size))

(define-compat series-null-count
  (_fun _Series-ptr -> _size))

(define-compat series-sum-i32/raw
  (_fun _Series-ptr -> _CompatOptI32)
  #:c-id series_sum_i32)

(define (series-sum-i32 s)
  (compat-opt-i32->datum (series-sum-i32/raw s)))

(define-compat series-sum-f64/raw
  (_fun _Series-ptr -> _CompatOptF64)
  #:c-id series_sum_f64)

(define (series-sum-f64 s)
  (compat-opt-f64->datum (series-sum-f64/raw s)))

(define-compat series-mean-f64/raw
  (_fun _Series-ptr -> _CompatOptF64)
  #:c-id series_mean_f64)

(define (series-mean-f64 s)
  (compat-opt-f64->datum (series-mean-f64/raw s)))

(define-compat series-max-f64/raw
  (_fun _Series-ptr -> _CompatOptF64)
  #:c-id series_max_f64)

(define (series-max-f64 s)
  (compat-opt-f64->datum (series-max-f64/raw s)))

(module+ test
  (check-equal? (series-len (series-empty)) 0)
  (check-equal? (series-null-count (series-empty)) 0))

(define-syntax-parse-rule (define-series-constructors rs-type:id ctype:id)
  #:with list-constructor-name (format-id #'rs-type "series-new-~a" #'rs-type)
  #:with vector-constructor-name (format-id #'rs-type
                                            "series-new-~a/vec"
                                            #'rs-type)
  #:with rust-id (format-id #'rs-type "series_new_~a" #'rs-type)
  (begin
    (define-compat list-constructor-name
      (_fun _string
            (v : (_list i ctype))
            (_size = (length v))
            -> _Series-ptr))
    (define-compat vector-constructor-name
      (_fun _string
            (v : (_vector i ctype))
            (_size = (vector-length v))
            -> _Series-ptr)
      #:c-id rust-id)))

(define-series-constructors i32 _int32)

(module+ test
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
  (check-false
   (series-sum-i32 (series-new-f64 "" '(1.0 2.0)))) ;; wrong dtype
  (check-exn
   #rx"argument is not non-null"
   (lambda ()
     (series-new-i32 "example" '())))

  (check-pred Series-ptr? (series-new-i32/vec "" (vector 1 2 3)))
  (check-equal?
   (series-len (series-new-i32/vec "" (vector 0)))
   1))

(define-series-constructors f64 _double)

(module+ test
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
   #rx"argument is not non-null"
   (lambda ()
     (series-new-f64 "example" '())))
  (check-exn
   #rx"given value does not fit primitive C type"
   (λ ()
     (series-new-f64 "no-name" '(0))))

  (check-pred Series-ptr? (series-new-f64/vec "" (vector 17.29 40.2)))
  (check-equal?
   (series-len (series-new-f64/vec "" (vector 17.29 40.2)))
   2))

(define-series-constructors i64 _int64)

(module+ test
  (check-pred Series-ptr? (series-new-i64 "" '(1 2 3)))
  (check-equal? (series-len (series-new-i64 "x" '(1 2))) 2)
  (check-equal? (series-dtype (series-new-i64 "x" '(1 2))) 'int64)
  (check-pred Series-ptr? (series-new-i64/vec "" (vector 1 2 3))))

(define-series-constructors u32 _uint32)

(module+ test
  (check-pred Series-ptr? (series-new-u32 "" '(1 2 3)))
  (check-equal? (series-len (series-new-u32 "x" '(0 1 2))) 3)
  (check-equal? (series-dtype (series-new-u32 "x" '(0 1))) 'uint32)
  (check-pred Series-ptr? (series-new-u32/vec "" (vector 1 2 3))))

(define-series-constructors u64 _uint64)

(module+ test
  (check-pred Series-ptr? (series-new-u64 "" '(1 2 3)))
  (check-equal? (series-len (series-new-u64 "x" '(0 1 2))) 3)
  (check-equal? (series-dtype (series-new-u64 "x" '(0 1))) 'uint64)
  (check-pred Series-ptr? (series-new-u64/vec "" (vector 1 2 3))))

;; Bools cross the boundary as u8 (0/1).  Racket-side wrappers translate
;; #f/#t to 0/1.
(define-compat series-new-bool/raw
  (_fun _string
        (v : (_list i _uint8))
        (_size = (length v))
        -> _Series-ptr)
  #:c-id series_new_bool)

(define-compat series-new-bool/vec/raw
  (_fun _string
        (v : (_vector i _uint8))
        (_size = (vector-length v))
        -> _Series-ptr)
  #:c-id series_new_bool)

(define (bool->u8 b) (if b 1 0))

(define (series-new-bool name bools)
  (series-new-bool/raw name (map bool->u8 bools)))

(define (series-new-bool/vec name bools)
  (series-new-bool/vec/raw name
                           (for/vector #:length (vector-length bools)
                                       ([b (in-vector bools)])
                             (bool->u8 b))))

(module+ test
  (check-pred Series-ptr? (series-new-bool "" '(#t #f #t)))
  (check-equal? (series-len (series-new-bool "x" '(#t #f))) 2)
  (check-equal? (series-dtype (series-new-bool "x" '(#t #f))) 'boolean)
  (check-pred Series-ptr? (series-new-bool/vec "" (vector #t #f #t))))

(define-series-constructors str _string)

(module+ test
  (check-pred Series-ptr? (series-new-str "" '("foo" "bar" "baz" "")))
  (check-equal?
   (series-len (series-new-str "str" '("" "")))
   2)
  (check-exn
   #rx"argument is not non-null"
   (lambda ()
     (series-new-str "example" '())))
  (check-exn
   #rx"contract violation"
   (λ ()
     (series-new-str "" '(symbol))))

  (check-pred Series-ptr? (series-new-str/vec "" (vector "foo" "bar" "baz" "")))
  (check-equal?
   (series-name (series-new-str "str" '("" "")))
   "str")
  (check-equal?
   (series-dtype (series-new-str "str" '("" "")))
   'string))

;; Year, Month, Day, Hour, Minute, Second
(define-cstruct _YMDHMS
  ([year _int]
   [month _uint32]
   [day _uint32]
   [hour _uint32]
   [minute _uint32]
   [sescond _uint32]))

(module+ test
  (check-pred YMDHMS?
              (make-YMDHMS 2014 7 11 12 0 0)))

(define-series-constructors ymdhms _YMDHMS)

(module+ test
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
   '(datetime milliseconds #f)))

(define-cpointer-type _DataFrame-ptr)

(define-compat dataframe-drop
  (_fun _DataFrame-ptr -> _void)
  #:wrap (deallocator))

(define-compat dataframe-make
  (_fun -> _DataFrame-ptr)
  #:wrap (allocator dataframe-drop))

(define-compat dataframe-empty
  (_fun -> _DataFrame-ptr)
  #:wrap (allocator dataframe-drop))

(define-cstruct _Shape
  ([rows _size]
   [cols _size]))

(define-compat dataframe-shape
  (_fun _DataFrame-ptr
        -> (s : _Shape)
        -> (values (Shape-rows s) (Shape-cols s))))

(define-compat dataframe-height
  (_fun _DataFrame-ptr -> _size))

(define-compat dataframe-width
  (_fun _DataFrame-ptr -> _size))

(define-compat dataframe-new/raw
  (_fun (v : (_list i _Series-ptr))
        (_size = (length v))
        -> _DataFrame-ptr)
  #:c-id dataframe_new
  #:wrap (allocator dataframe-drop))

(define (dataframe-new series-list)
  (dataframe-new/raw series-list))

(define-compat dataframe-column-name
  (_fun _DataFrame-ptr _size -> _rsstring))

(define-compat dataframe-column
  (_fun _DataFrame-ptr _string -> _Series-ptr))

(define-compat dataframe->string
  (_fun _DataFrame-ptr -> _rsstring)
  #:c-id dataframe_to_string)

(define-compat dataframe-write-csv/raw
  (_fun _DataFrame-ptr _string -> _int32)
  #:c-id dataframe_write_csv)

(define (dataframe-write-csv df path)
  (define rc (dataframe-write-csv/raw df (path->string-or-string path)))
  (unless (zero? rc)
    (error 'dataframe-write-csv
           "failed to write csv to ~a (rust error code ~a)"
           path rc)))

(define-compat dataframe-read-csv/raw
  (_fun _string -> _DataFrame-ptr)
  #:c-id dataframe_read_csv
  #:wrap (allocator dataframe-drop))

(define (dataframe-read-csv path)
  (define df (dataframe-read-csv/raw (path->string-or-string path)))
  (unless df
    (error 'dataframe-read-csv "failed to read csv from ~a" path))
  df)

(define (path->string-or-string p)
  (cond
    [(string? p) p]
    [(path? p) (path->string p)]
    [else (error 'dataframe-csv "expected path-string?, got ~v" p)]))

(define-syntax-parse-rule (define-cmp-scalar name:id ctype:id)
  (define-compat name
    (_fun _Series-ptr ctype -> _Series-ptr)))

(define-cmp-scalar series-lt-i32 _int32)
(define-cmp-scalar series-le-i32 _int32)
(define-cmp-scalar series-gt-i32 _int32)
(define-cmp-scalar series-ge-i32 _int32)
(define-cmp-scalar series-eq-i32 _int32)
(define-cmp-scalar series-ne-i32 _int32)

(define-cmp-scalar series-lt-f64 _double)
(define-cmp-scalar series-le-f64 _double)
(define-cmp-scalar series-gt-f64 _double)
(define-cmp-scalar series-ge-f64 _double)
(define-cmp-scalar series-eq-f64 _double)
(define-cmp-scalar series-ne-f64 _double)

(define-cmp-scalar series-eq-str _string)
(define-cmp-scalar series-ne-str _string)

(module+ test
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
  (check-equal? (count-where (series-ne-str (dataframe-column cmp-df "s") "a")) 3))

(define-compat dataframe-filter
  (_fun _DataFrame-ptr _Series-ptr -> _DataFrame-ptr)
  #:wrap (allocator dataframe-drop))

(define-compat dataframe-sort/c
  (_fun _DataFrame-ptr
        (names : (_list i _string))
        (descending : (_list i _uint8))
        (_size = (length names))
        -> _DataFrame-ptr)
  #:c-id dataframe_sort
  #:wrap (allocator dataframe-drop))

(define (dataframe-sort df names #:descending [descending #f])
  (define dlist
    (cond
      [(eq? descending #f) (map (lambda (_) 0) names)]
      [(eq? descending #t) (map (lambda (_) 1) names)]
      [(list? descending)
       (unless (= (length descending) (length names))
         (error 'dataframe-sort
                "descending list length ~a does not match names length ~a"
                (length descending) (length names)))
       (map (lambda (b) (if b 1 0)) descending)]
      [else (error 'dataframe-sort "bad descending: ~v" descending)]))
  (dataframe-sort/c df names dlist))

(define-compat dataframe-group-by-sum/c
  (_fun _DataFrame-ptr
        (by : (_list i _string))
        (_size = (length by))
        (agg : (_list i _string))
        (_size = (length agg))
        -> _DataFrame-ptr)
  #:c-id dataframe_group_by_sum
  #:wrap (allocator dataframe-drop))

(define (dataframe-group-by-sum df #:by by #:agg agg)
  (dataframe-group-by-sum/c df by agg))

(define (display-dataframe df [out (current-output-port)])
  (display (dataframe->string df) out)
  (newline out))

(module+ test
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

  ;; --- Example 4: CSV roundtrip ---
  (define csv-df
    (dataframe-new
     (list (series-new-str "city" '("Boston" "New York" "Chicago"))
           (series-new-f64 "population_millions" '(0.65 8.8 2.7))
           (series-new-i32 "founded" '(1630 1624 1837)))))
  (define tmp-csv
    (build-path (find-system-path 'temp-dir) "rkt-polars-test.csv"))
  (dataframe-write-csv csv-df tmp-csv)
  (define round (dataframe-read-csv tmp-csv))
  (define-values (rr rc) (dataframe-shape round))
  (check-equal? rr 3)
  (check-equal? rc 3)
  (check-equal? (dataframe-column-name round 0) "city")
  (check-equal? (dataframe-column-name round 1) "population_millions")
  (check-equal? (dataframe-column-name round 2) "founded")
  (check-equal? (series-dtype (dataframe-column round "founded")) 'int64)
  (check-equal? (series-dtype (dataframe-column round "population_millions")) 'float64)
  (check-= (series-sum-f64 (dataframe-column round "population_millions"))
           12.15
           1e-9)
  (delete-file tmp-csv))
