#lang racket/base

(module+ test
  (require rackunit
           (only-in gregor ->datetime/local ->tzid ->utc-offset date datetime)
           (only-in racket/sequence sequence->list)
           (only-in polars/private/bulk in-dataframe-rows in-series series->list series->vector)
           (only-in polars/private/foreign
                    dataframe-new polars-null polars-null? series-cast series-drop-count
                    series-new-i32 series-new-i64 series-new-str series-new-str/vec series-ref)
           (only-in polars/tests/gc-pressure call-with-collections))

  (define (gappy-ints n)
    (for/list ([i (in-range n)])
      (if (memv (modulo i 7) '(0 3)) polars-null (- (* i 1000) 7))))
  (define (gappy-strs n)
    (for/list ([i (in-range n)])
      (if (memv (modulo i 5) '(1 4)) polars-null (make-string (modulo i 4) #\y))))

  (for* ([chunk-rows '(1 2 3 7)]
         [n (list 0 (sub1 chunk-rows) chunk-rows (add1 chunk-rows) (* 2 chunk-rows)
                  (add1 (* 2 chunk-rows)))]
         [s (let ([strs (series-new-str "x" (gappy-strs n))])
              (list (series-new-i64 "x" (gappy-ints n))
                    strs
                    (series-cast strs 'categorical)
                    (series-cast strs '(enum yyy || yy y))))])
    (define refs (for/list ([i (in-range n)]) (series-ref s i)))
    (check-equal? (sequence->list (in-series s #:chunk-rows chunk-rows)) refs)
    (check-equal? (series->list s) refs))

  (define many-strings
    (for/list ([i (in-range 300000)])
      (case (modulo i 5)
        [(0) polars-null]
        [(1) ""]
        [(2) (format "ünïcödé ~a 東京 😀" i)]
        [(3) (string #\a #\nul #\b)]
        [else (number->string i)])))
  (for ([build (list series-new-str
                     (lambda (name strings) (series-new-str/vec name (list->vector strings))))])
    (define-values (many-series collections)
      (call-with-collections (lambda () (build "many" many-strings))))
    (check > collections 1)
    (check-equal? (series->list many-series) many-strings))

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
  (check >= (released-by (lambda () (series->list carriers))) 20)

  (define past-chrono-date (series-cast (series-new-i32 "d" '(2000000000)) 'date))
  (check-equal? (series-ref past-chrono-date 0) (date 5477784 1 6))
  (check-equal? (series->list past-chrono-date) (list (date 5477784 1 6)))
  (define past-chrono-zoned
    (series-cast (series-new-i64 "k" '(9000000000000000000)) '(datetime microseconds "Europe/Brussels")))
  (check-exn #rx"^series->list: cannot read a datetime in \"Europe/Brussels\": polars panicked: "
             (lambda () (series->list past-chrono-zoned)))
  (check-exn #rx"^series-ref: cannot read a datetime in \"Europe/Brussels\": polars panicked: "
             (lambda () (series-ref past-chrono-zoned 0))))
