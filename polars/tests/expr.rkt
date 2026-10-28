#lang racket/base

(module+ test
  (require gregor
           rackunit
           (only-in racket/contract/base contract-name or/c)
           (only-in racket/match match-define)
           (only-in racket/string string-contains? string-prefix?)
           (only-in polars/private/c-integer int32/c int64/c size/c uint32/c uint64/c uint8/c)
           (only-in polars/private/csv lazyframe-scan-csv)
           (only-in polars/private/expr
                    dataframe-filter-expr dataframe-group-by-agg dataframe-lazy
                    dataframe-select-exprs dataframe-with-columns expr-abs expr-add expr-and
                    expr-cast expr-ceil expr-clip expr-count expr-cum-count expr-cum-max
                    expr-cum-min expr-cum-prod expr-cum-sum expr-div expr-drop-nulls expr-eq
                    expr-fill-nan expr-fill-null expr-filter expr-first expr-floor expr-gather
                    expr-ge expr-gt expr-is-between expr-is-duplicated expr-is-finite
                    expr-is-first-distinct expr-is-in expr-is-infinite expr-is-last-distinct
                    expr-is-nan expr-is-null expr-is-unique expr-le expr-log expr-lt expr-max
                    expr-mean expr-mod expr-mul expr-ne expr-neg expr-not expr-or expr-over
                    expr-pow expr-reverse expr-sign expr-sub expr-sum expr-when expr-xor
                    lazyframe-collect lazyframe-filter lazyframe-group-by-agg lazyframe-select
                    lazyframe-unique lazyframe-with-columns null-behavior/c rank-method/c)
           (only-in (submod polars/private/expr internal)
                    call-with-plan collect-plan/who expr-diff expr-forward-fill expr-head
                    expr-rank expr-round expr-shift expr-slice expr-sort expr-sort-by expr-std
                    expr-tail expr-var lazyframe-explain lazyframe-head lazyframe-join
                    lazyframe-slice lazyframe-sort lazyframe-tail rank-methods)
           (only-in polars/private/expr-core
                    Expr-ptr? LazyFrame-ptr? col expr-alias expr-drop-count expr-lit-i32
                    lazyframe-drop lazyframe-drop-count lit lit-integer/c)
           (only-in polars/private/expr-dt
                    expr-dt-date expr-dt-day expr-dt-hour expr-dt-is-leap-year expr-dt-iso-year
                    expr-dt-microsecond expr-dt-millisecond expr-dt-minute expr-dt-month
                    expr-dt-nanosecond expr-dt-ordinal-day expr-dt-quarter expr-dt-second
                    expr-dt-strftime expr-dt-time expr-dt-timestamp expr-dt-truncate
                    expr-dt-week expr-dt-weekday expr-dt-year)
           (only-in polars/private/expr-str
                    expr-str->date expr-str->datetime expr-str->time expr-str-contains
                    expr-str-count-matches expr-str-ends-with expr-str-extract expr-str-find
                    expr-str-find-literal expr-str-head expr-str-len-bytes expr-str-len-chars
                    expr-str-replace expr-str-replace-all expr-str-slice expr-str-starts-with
                    expr-str-strip-chars expr-str-strip-chars-end expr-str-strip-chars-start
                    expr-str-strip-prefix expr-str-strip-suffix expr-str-tail
                    expr-str-to-lowercase expr-str-to-uppercase)
           (only-in polars/tests/test-helpers
                    drops-during drops-once refusal refusal-misses settle!)
           (only-in polars/private/foreign
                    DataFrame-ptr? dataframe-column dataframe-column-name dataframe-column-names
                    dataframe-drop dataframe-drop-count dataframe-height dataframe-new
                    dataframe-width make-YMDHMS polars-null series-dtype series-len
                    series-new-f64 series-new-i32 series-new-i64 series-new-str
                    series-new-ymdhms series-ref series-sum-f64 series-sum-i32)
           (only-in racket/contract exn:fail:contract:blame?)
           (prefix-in contracted: polars/private/expr))

  (define df
    (dataframe-new
     (list (series-new-i32 "x" '(1 2 3 4))
           (series-new-f64 "y" '(0.5 1.5 2.5 3.5)))))

  (define lf (dataframe-lazy df))
  (check-pred LazyFrame-ptr? lf)

  (define (plans-built-for column)
    (define built (box '()))
    (define (extend source)
      (define plan (lazyframe-select source (list (col column))))
      (set-box! built (list source plan))
      plan)
    (values built extend))
  (for* ([row (in-list
               (list (list "collect" "x"
                           (lambda (extend) (dataframe-drop (collect-plan/who 'plans df extend))))
                     (list "failed collect" "nope"
                           (lambda (extend)
                             (check-exn #rx"^plans: .*nope"
                                        (lambda () (collect-plan/who 'plans df extend)))))
                     (list "call-with-plan" "y"
                           (lambda (extend)
                             (call-with-plan df extend
                                             (lambda (plan) (check-pred LazyFrame-ptr? plan)))))))]
         [finish (in-list (list void settle!))])
    (match-define (list label column run) row)
    (define-values (built extend) (plans-built-for column))
    (check-equal? (drops-during lazyframe-drop-count (lambda () (run extend) (finish))) 2 label)
    (check-equal? (length (unbox built)) 2 label)
    (for ([plan (in-list (unbox built))])
      (check-exn #rx"^lazyframe-drop: lazyframe has been dropped"
                 (lambda () (lazyframe-drop plan)))))
  (check-equal? (drops-once lazyframe-drop-count lazyframe-drop (lambda () (dataframe-lazy df))) 1)
  (check-equal? (drops-once lazyframe-drop-count lazyframe-drop
                            (lambda () (lazyframe-select (dataframe-lazy df) (list (col "x")))))
                2)
  (check-pred Expr-ptr? (expr-cast (col "x") (list 'enum (string->symbol "a\u0000b"))))

  (define tmp-scan-csv
    (build-path (find-system-path 'temp-dir) "rkt-polars-lazy-scan.csv"))
  (with-output-to-file tmp-scan-csv #:exists 'replace
    (lambda ()
      (displayln "group,value")
      (displayln "a,10")
      (displayln "a,25")
      (displayln "b,7")
      (displayln "b,30")))
  (define csv-scan (lazyframe-scan-csv tmp-scan-csv))
  (check-pred LazyFrame-ptr? csv-scan)
  (define csv-scan-out
    (lazyframe-collect
     (lazyframe-sort
      (lazyframe-group-by-agg
       (lazyframe-filter csv-scan (expr-gt (col "value") 10))
       '("group")
       (list (expr-alias (expr-sum (expr-cast (col "value") 'int32)) "total")))
      '("group"))))
  (check-equal? (dataframe-height csv-scan-out) 2)
  (check-equal? (series-sum-i32 (dataframe-column csv-scan-out "total")) 55)
  (delete-file tmp-scan-csv)

  (define tmp-scan-csv/options
    (build-path (find-system-path 'temp-dir) "rkt-polars-lazy-scan-options.csv"))
  (with-output-to-file tmp-scan-csv/options #:exists 'replace
    (lambda ()
      (displayln "ignore;999")
      (displayln "group;value")
      (displayln "a;10")
      (displayln "a;25")
      (displayln "b;7")
      (displayln "b;30")))
  (define csv-scan-options
    (lazyframe-scan-csv tmp-scan-csv/options
                        #:has-header #t
                        #:separator #\;
                        #:skip-rows 1
                        #:n-rows 3))
  (define csv-scan-options-out
    (lazyframe-collect
     (lazyframe-filter csv-scan-options (expr-gt (col "value") 10))))
  (check-equal? (dataframe-height csv-scan-options-out) 1)
  (check-equal? (series-ref (dataframe-column csv-scan-options-out "value") 0) 25)
  (delete-file tmp-scan-csv/options)

  (define narrowed-lf (lazyframe-select (lazyframe-filter lf (expr-ge (col "x") 2))
                                        (list (col "x"))))
  (define written-plan (lazyframe-explain narrowed-lf #:optimized #f))
  (check-true (string-prefix? written-plan "SELECT [col(\"x\")]\n  FILTER col(\"x\") >= 2\n"))
  (check-true (string-contains? written-plan "PROJECT */2 COLUMNS"))
  (check-true (string-contains? (lazyframe-explain narrowed-lf) "PROJECT[\"x\"] 1/2 COLUMNS"))
  (check-not-equal? (lazyframe-explain narrowed-lf #:format 'tree #:optimized #f) written-plan)
  (check-regexp-match
   #rx"^lazyframe-explain: failed to explain the query: [^\n]*\"nope\""
   (with-handlers ([exn:fail? exn-message])
     (lazyframe-explain (lazyframe-select lf (list (col "nope"))))))

  ;; with-columns adding a literal column
  (define lf2
    (lazyframe-with-columns lf
                            (list (expr-alias (expr-lit-i32 7) "seven"))))
  (check-pred LazyFrame-ptr? lf2)

  (define collected (lazyframe-collect lf2))
  (check-pred DataFrame-ptr? collected)
  (check-equal? (dataframe-height collected) 4)
  (check-equal? (dataframe-width collected) 3)
  (check-equal? (sort (dataframe-column-names collected) string<?)
                '("seven" "x" "y"))
  (check-equal? (series-sum-i32 (dataframe-column collected "seven")) 28)

  ;; lit dispatch
  (check-pred Expr-ptr? (lit 1))
  (check-pred Expr-ptr? (lit 1.5))
  (check-pred Expr-ptr? (lit "hello"))
  (check-pred Expr-ptr? (lit #t))

  ;; col alias
  (check-pred Expr-ptr? (col "x"))

  ;; --- Expr string namespace ---
  (define str-df
    (dataframe-new
     (list (series-new-str "name" '("Alpha" "beta" "Gamma" "delta"))
           (series-new-i32 "value" '(1 2 3 4)))))

  (check-equal?
   (dataframe-height
    (lazyframe-collect
     (lazyframe-filter (dataframe-lazy str-df)
                       (expr-str-contains (col "name") "a"))))
   4)

  (check-equal?
   (dataframe-height
    (lazyframe-collect
     (lazyframe-filter (dataframe-lazy str-df)
                       (expr-str-starts-with (col "name") "A"))))
   1)

  (check-equal?
   (dataframe-height
    (lazyframe-collect
     (lazyframe-filter (dataframe-lazy str-df)
                       (expr-str-ends-with (col "name") "ta"))))
   2)

  (define str-case
    (lazyframe-collect
     (lazyframe-with-columns
      (dataframe-lazy str-df)
      (list (expr-alias (expr-str-to-lowercase (col "name")) "lower_name")
            (expr-alias (expr-str-to-uppercase (col "name")) "upper_name")))))
  (check-equal? (series-ref (dataframe-column str-case "lower_name") 0) "alpha")
  (check-equal? (series-ref (dataframe-column str-case "upper_name") 1) "BETA")

  (define str-clean-df
    (dataframe-new
     (list (series-new-str "text"
                           '("  alpha  "
                             "--beta--"
                             "id=123"
                             "report.txt"
                             "banana")))))
  (define str-clean
    (lazyframe-collect
     (lazyframe-with-columns
      (dataframe-lazy str-clean-df)
      (list (expr-alias (expr-str-strip-chars (col "text")) "trimmed")
            (expr-alias (expr-str-strip-chars (col "text") "-") "stripped")
            (expr-alias (expr-str-strip-chars-start (col "text") "-") "strip_start")
            (expr-alias (expr-str-strip-chars-end (col "text") "-") "strip_end")
            (expr-alias (expr-str-strip-prefix (col "text") "id=") "no_prefix")
            (expr-alias (expr-str-strip-suffix (col "text") ".txt") "no_suffix")
            (expr-alias (expr-str-replace (col "text") "\\d+" "#") "replace_digits")
            (expr-alias (expr-str-replace-all (col "text") "a" "A" #:literal #t)
                        "replace_all_a")
            (expr-alias (expr-str-extract (col "text") "([0-9]+)") "digits")))))
  (check-equal? (series-ref (dataframe-column str-clean "trimmed") 0) "alpha")
  (check-equal? (series-ref (dataframe-column str-clean "stripped") 1) "beta")
  (check-equal? (series-ref (dataframe-column str-clean "strip_start") 1) "beta--")
  (check-equal? (series-ref (dataframe-column str-clean "strip_end") 1) "--beta")
  (check-equal? (series-ref (dataframe-column str-clean "no_prefix") 2) "123")
  (check-equal? (series-ref (dataframe-column str-clean "no_suffix") 3) "report")
  (check-equal? (series-ref (dataframe-column str-clean "replace_digits") 2) "id=#")
  (check-equal? (series-ref (dataframe-column str-clean "replace_all_a") 4) "bAnAnA")
  (check-equal? (series-ref (dataframe-column str-clean "digits") 2) "123")

  (define str-batch3-df
    (dataframe-new
     (list (series-new-str "text"
                           '("hello"
                             "héllo"
                             "banana"
                             "abc123abc")))))
  (define str-batch3
    (dataframe-with-columns
     str-batch3-df
     (list (expr-alias (expr-str-len-bytes (col "text")) "bytes")
           (expr-alias (expr-str-len-chars (col "text")) "chars")
           (expr-alias (expr-str-slice (col "text") 1 3) "slice")
           (expr-alias (expr-str-slice (col "text") 2 #f) "slice_rest")
           (expr-alias (expr-str-slice (col "text") -2) "slice_last")
           (expr-alias (expr-str-head (col "text") 2) "head")
           (expr-alias (expr-str-tail (col "text") 2) "tail")
           (expr-alias (expr-str-find (col "text") "[0-9]+") "find_digits")
           (expr-alias (expr-str-find-literal (col "text") "na") "find_na")
           (expr-alias (expr-str-count-matches (col "text") "a" #:literal #t)
                       "count_a"))))
  (check-equal? (series-ref (dataframe-column str-batch3 "bytes") 1) 6)
  (check-equal? (series-ref (dataframe-column str-batch3 "chars") 1) 5)
  (check-equal? (series-ref (dataframe-column str-batch3 "slice") 2) "ana")
  (check-equal? (series-ref (dataframe-column str-batch3 "slice_rest") 2) "nana")
  (check-equal? (series-ref (dataframe-column str-batch3 "slice_last") 3) "bc")
  (check-equal? (series-ref (dataframe-column str-batch3 "head") 1) "hé")
  (check-equal? (series-ref (dataframe-column str-batch3 "tail") 2) "na")
  (check-equal? (series-ref (dataframe-column str-batch3 "find_digits") 3) 3)
  (check-equal? (series-ref (dataframe-column str-batch3 "find_na") 2) 2)
  (check-equal? (series-ref (dataframe-column str-batch3 "count_a") 2) 3)

  (define str-temporal-df
    (dataframe-new
     (list (series-new-str "date_s" '("2024-01-02" "not-a-date" "2024-05-09 extra"))
           (series-new-str "dt_s" '("2024-01-02 03:04:05"
                                    "bad"
                                    "2024-05-09 12:30:45"))
           (series-new-str "time_s" '("03:04:05.123456789"
                                      "bad"
                                      "12:30:45")))))
  (define str-temporal
    (dataframe-with-columns
     str-temporal-df
     (list (expr-alias (expr-str->date (col "date_s") #:strict #f)
                       "date_infer")
           (expr-alias (expr-str->date (col "date_s")
                                       #:format "%Y-%m-%d"
                                       #:strict #f
                                       #:exact #f)
                       "date_embedded")
           (expr-alias (expr-str->datetime (col "dt_s")
                                           #:format "%Y-%m-%d %H:%M:%S"
                                           #:unit 'milliseconds
                                           #:strict #f)
                       "parsed_dt")
           (expr-alias (expr-str->time (col "time_s")
                                       #:format "%H:%M:%S%.f"
                                       #:strict #f)
                       "parsed_time"))))
  (check-equal? (series-dtype (dataframe-column str-temporal "date_infer")) 'date)
  (check-equal? (series-ref (dataframe-column str-temporal "date_infer") 0)
                (date 2024 1 2))
  (check-equal? (series-ref (dataframe-column str-temporal "date_infer") 1)
                polars-null)
  (check-equal? (series-ref (dataframe-column str-temporal "date_embedded") 2)
                (date 2024 5 9))
  (check-equal? (series-dtype (dataframe-column str-temporal "parsed_dt"))
                '(datetime milliseconds #f))
  (check-equal? (series-ref (dataframe-column str-temporal "parsed_dt") 0)
                (datetime 2024 1 2 3 4 5))
  (check-equal? (series-ref (dataframe-column str-temporal "parsed_dt") 1)
                polars-null)
  (check-equal? (series-dtype (dataframe-column str-temporal "parsed_time")) 'time)
  (check-equal? (series-ref (dataframe-column str-temporal "parsed_time") 0)
                (iso8601->time "03:04:05.123456789"))

  ;; --- Expr datetime namespace ---
  (define dt-df
    (dataframe-new
     (list (series-new-ymdhms
            "ts"
            (list (make-YMDHMS 2024 1 2 3 4 5)
                  (make-YMDHMS 2025 12 31 23 59 58)
                  (make-YMDHMS 2026 5 9 12 30 45))))))

  (define dt-parts
    (lazyframe-collect
     (lazyframe-with-columns
      (dataframe-lazy dt-df)
      (list (expr-alias (expr-dt-year (col "ts")) "year")
            (expr-alias (expr-cast (expr-dt-month (col "ts")) 'int32) "month")
            (expr-alias (expr-cast (expr-dt-day (col "ts")) 'int32) "day")
            (expr-alias (expr-cast (expr-dt-hour (col "ts")) 'int32) "hour")
            (expr-alias (expr-cast (expr-dt-minute (col "ts")) 'int32) "minute")
            (expr-alias (expr-cast (expr-dt-second (col "ts")) 'int32) "second")))))

  (check-equal? (series-ref (dataframe-column dt-parts "year") 0) 2024)
  (check-equal? (series-ref (dataframe-column dt-parts "month") 1) 12)
  (check-equal? (series-ref (dataframe-column dt-parts "day") 2) 9)
  (check-equal? (series-ref (dataframe-column dt-parts "hour") 0) 3)
  (check-equal? (series-ref (dataframe-column dt-parts "minute") 1) 59)
  (check-equal? (series-ref (dataframe-column dt-parts "second") 2) 45)

  (define dt-batch2
    (dataframe-with-columns
     dt-df
     (list (expr-alias (expr-dt-iso-year (col "ts")) "iso_year")
           (expr-alias (expr-cast (expr-dt-quarter (col "ts")) 'int32) "quarter")
           (expr-alias (expr-cast (expr-dt-week (col "ts")) 'int32) "week")
           (expr-alias (expr-cast (expr-dt-weekday (col "ts")) 'int32) "weekday")
           (expr-alias (expr-cast (expr-dt-ordinal-day (col "ts")) 'int32) "ordinal")
           (expr-alias (expr-dt-is-leap-year (col "ts")) "leap")
           (expr-alias (expr-dt-date (col "ts")) "date")
           (expr-alias (expr-dt-time (col "ts")) "time")
           (expr-alias (expr-dt-strftime (col "ts") "%Y-%m-%d") "fmt"))))
  (check-equal? (series-ref (dataframe-column dt-batch2 "iso_year") 0) 2024)
  (check-equal? (series-ref (dataframe-column dt-batch2 "quarter") 0) 1)
  (check-equal? (series-ref (dataframe-column dt-batch2 "week") 0) 1)
  (check-equal? (series-ref (dataframe-column dt-batch2 "weekday") 0) 2)
  (check-equal? (series-ref (dataframe-column dt-batch2 "ordinal") 0) 2)
  (check-equal? (series-ref (dataframe-column dt-batch2 "leap") 0) #t)
  (check-equal? (series-ref (dataframe-column dt-batch2 "date") 0) (date 2024 1 2))
  (check-equal? (series-ref (dataframe-column dt-batch2 "time") 0)
                (iso8601->time "03:04:05"))
  (check-equal? (series-ref (dataframe-column dt-batch2 "fmt") 0) "2024-01-02")

  (define dt-subsec-df
    (dataframe-new
     (list (series-new-i64 "t" '(1704164645123)))))
  (define dt-subsec
    (dataframe-with-columns
     dt-subsec-df
     (list (expr-alias (expr-cast (col "t") '(datetime milliseconds)) "ts"))))
  (define dt-subsec-out
    (dataframe-with-columns
     dt-subsec
     (list (expr-alias (expr-dt-millisecond (col "ts")) "ms")
           (expr-alias (expr-dt-microsecond (col "ts")) "us")
           (expr-alias (expr-dt-nanosecond (col "ts")) "ns")
           (expr-alias (expr-dt-timestamp (col "ts") #:unit 'milliseconds) "epoch_ms")
           (expr-alias (expr-dt-timestamp (col "ts") #:unit 'microseconds) "epoch_us")
           (expr-alias (expr-dt-truncate (col "ts") "1h") "hour_bucket"))))
  (check-equal? (series-ref (dataframe-column dt-subsec-out "ms") 0) 123)
  (check-equal? (series-ref (dataframe-column dt-subsec-out "us") 0) 123000)
  (check-equal? (series-ref (dataframe-column dt-subsec-out "ns") 0) 123000000)
  (check-equal? (series-ref (dataframe-column dt-subsec-out "epoch_ms") 0) 1704164645123)
  (check-equal? (series-ref (dataframe-column dt-subsec-out "epoch_us") 0) 1704164645123000)
  (check-equal? (series-ref (dataframe-column dt-subsec-out "hour_bucket") 0)
                (datetime 2024 1 2 3 0 0))

  ;; --- Phase A2 tests: Expr ops via with-columns ---

  (define (collect-with df . exprs)
    (lazyframe-collect
     (lazyframe-with-columns (dataframe-lazy df) exprs)))

  ;; arithmetic: x * 2 -> double_x
  (define df-double
    (collect-with df (expr-alias (expr-mul (col "x") 2) "double_x")))
  (check-equal? (series-sum-i32 (dataframe-column df-double "double_x"))
                20) ;; 2+4+6+8

  ;; arithmetic with auto-lifted f64: y + 1.0
  (define df-yp1
    (collect-with df (expr-alias (expr-add (col "y") 1.0) "y1")))
  (check-= (series-sum-f64 (dataframe-column df-yp1 "y1"))
           12.0  ;; 1.5+2.5+3.5+4.5
           1e-9)

  ;; comparison produces a boolean column
  (define df-mask
    (collect-with df (expr-alias (expr-gt (col "x") 2) "big")))
  (check-equal? (series-dtype (dataframe-column df-mask "big")) 'boolean)

  ;; boolean ops: (x > 1) AND (x < 4)  -> {2, 3}
  (define df-and
    (collect-with df
                  (expr-alias (expr-and (expr-gt (col "x") 1)
                                        (expr-lt (col "x") 4))
                              "in_range")))
  (check-equal? (series-dtype (dataframe-column df-and "in_range")) 'boolean)

  ;; unary not / is_null
  (define df-unops
    (collect-with df
                  (expr-alias (expr-not (expr-eq (col "x") 1)) "not_one")
                  (expr-alias (expr-is-null (col "x")) "x_null")))
  (check-equal? (series-dtype (dataframe-column df-unops "not_one")) 'boolean)
  (check-equal? (series-dtype (dataframe-column df-unops "x_null")) 'boolean)
  (define negated-x
    (dataframe-select-exprs (dataframe-new (list (series-new-i64 "x" '(1 -2 3))))
                            (list (expr-neg (col "x")))))
  (check-equal? (dataframe-column-names negated-x) '("x"))
  (check-equal? (for/list ([i 3]) (series-ref (dataframe-column negated-x "x") i)) '(-1 2 -3))

  ;; --- Phase A3 tests ---

  ;; dataframe-filter-expr: x > 2 -> 2 rows (3, 4)
  (define filtered (dataframe-filter-expr df (expr-gt (col "x") 2)))
  (check-equal? (dataframe-height filtered) 2)
  (check-equal? (series-sum-i32 (dataframe-column filtered "x")) 7)

  ;; dataframe-select-exprs: keep x, add x*10 aliased
  (define projected
    (dataframe-select-exprs df
                            (list (col "x")
                                  (expr-alias (expr-mul (col "x") 10) "x10"))))
  (check-equal? (dataframe-width projected) 2)
  (check-equal? (series-sum-i32 (dataframe-column projected "x10")) 100)

  ;; --- Phase A4 tests: aggregations + lazy group-by ---

  ;; Top-level aggregation: select(col("x").sum()) -> single row of 10
  (define agg-only
    (dataframe-select-exprs df
                            (list (expr-alias (expr-sum (col "x")) "sum_x")
                                  (expr-alias (expr-mean (col "y")) "mean_y"))))
  (check-equal? (dataframe-height agg-only) 1)
  (check-equal? (series-sum-i32 (dataframe-column agg-only "sum_x")) 10)
  (check-= (series-sum-f64 (dataframe-column agg-only "mean_y")) 2.0 1e-9)

  ;; Group-by + agg: groups of x by parity of (x mod 2).
  (define df-grp
    (dataframe-new
     (list (series-new-str "g" '("a" "a" "b" "b" "b"))
           (series-new-i32 "v" '(10 20 1 2 3)))))

  (define grouped
    (dataframe-group-by-agg
     df-grp
     '("g")
     (list (expr-alias (expr-sum (col "v")) "sum_v")
           (expr-alias (expr-count (col "v")) "n"))))
  (check-equal? (dataframe-height grouped) 2)
  ;; sum across groups must equal sum across input regardless of order
  (check-equal? (series-sum-i32 (dataframe-column grouped "sum_v")) 36)

  ;; key list also accepts already-built Expr-ptrs
  (define grouped/expr-key
    (dataframe-group-by-agg
     df-grp
     (list (col "g"))
     (list (expr-alias (expr-max (col "v")) "max_v"))))
  (check-equal? (dataframe-height grouped/expr-key) 2)

  ;; --- Phase A6 tests: lazy sort / unique / drop-nulls ---

  ;; lazyframe-sort: descending=#t on a single column
  (define sorted-desc
    (lazyframe-collect
     (lazyframe-sort (dataframe-lazy df) '("x") #:descending #t)))
  (check-equal? (dataframe-height sorted-desc) 4)
  (check-equal? (series-sum-i32 (dataframe-column sorted-desc "x")) 10)

  ;; per-column descending list
  (define df-multi
    (dataframe-new
     (list (series-new-str "g" '("a" "a" "b" "b"))
           (series-new-i32 "v" '(2 1 4 3)))))
  (define sorted-multi
    (lazyframe-collect
     (lazyframe-sort (dataframe-lazy df-multi) '("g" "v")
                     #:descending '(#f #t))))
  (check-equal? (dataframe-height sorted-multi) 4)

  ;; lazyframe-unique: dedup whole rows
  (define df-dup
    (dataframe-new
     (list (series-new-i32 "k" '(1 1 2 2 3))
           (series-new-i32 "v" '(10 10 20 20 30)))))
  (define deduped
    (lazyframe-collect (lazyframe-unique (dataframe-lazy df-dup))))
  (check-equal? (dataframe-height deduped) 3)

  ;; fluent pipeline: filter → group-by-agg → sort
  (define df-sales
    (dataframe-new
     (list (series-new-str "g" '("a" "a" "b" "b" "c" "c"))
           (series-new-i32 "v" '(10 25 7 30 18 4)))))
  (define top-by-sum
    (lazyframe-collect
     (lazyframe-sort
      (lazyframe-group-by-agg
       (lazyframe-filter (dataframe-lazy df-sales)
                         (expr-gt (col "v") 5))
       '("g")
       (list (expr-alias (expr-sum (col "v")) "sum_v")))
      '("sum_v") #:descending #t)))
  (check-equal? (dataframe-height top-by-sum) 3)
  ;; after filter (drop v=4), per-group sums are a:35, b:37, c:18
  (check-equal? (series-sum-i32 (dataframe-column top-by-sum "sum_v")) 90)

  ;; --- Phase A5 tests: window (over) + per-Expr sort ---

  ;; sum_v_per_g = sum(v).over("g") — same length as input, repeats the
  ;; per-group sum on each row.
  (define df-window
    (dataframe-with-columns
     df-grp
     (list (expr-alias (expr-over (expr-sum (col "v")) '("g"))
                       "sum_v_per_g"))))
  (check-equal? (dataframe-height df-window) 5)
  ;; group "a": v=10+20=30 (2 rows); group "b": v=1+2+3=6 (3 rows)
  ;; total of sum_v_per_g column = 30*2 + 6*3 = 78
  (check-equal? (series-sum-i32 (dataframe-column df-window "sum_v_per_g")) 78)

  ;; expr-over also accepts pre-built Expr keys
  (define df-window/expr-key
    (dataframe-with-columns
     df-grp
     (list (expr-alias (expr-over (expr-max (col "v")) (list (col "g")))
                       "max_v_per_g"))))
  (check-equal? (dataframe-height df-window/expr-key) 5)

  ;; expr-sort inside an aggregation: per group, first(sort(v, desc)) is
  ;; the per-group max.
  (define grouped-sort
    (dataframe-group-by-agg
     df-grp
     '("g")
     (list (expr-alias (expr-first (expr-sort (col "v") #:descending #t))
                       "max_v"))))
  (check-equal? (dataframe-height grouped-sort) 2)
  ;; max(v) per group: a -> 20, b -> 3, sum = 23
  (check-equal? (series-sum-i32 (dataframe-column grouped-sort "max_v")) 23)

  ;; --- Phase A7 tests: lazy head / tail / slice ---

  (define df-rows
    (dataframe-new
     (list (series-new-i32 "x" '(1 2 3 4 5 6)))))

  (define head3
    (lazyframe-collect (lazyframe-head (dataframe-lazy df-rows) 3)))
  (check-equal? (dataframe-height head3) 3)
  (check-equal? (series-sum-i32 (dataframe-column head3 "x")) 6) ;; 1+2+3

  (define tail2
    (lazyframe-collect (lazyframe-tail (dataframe-lazy df-rows) 2)))
  (check-equal? (dataframe-height tail2) 2)
  (check-equal? (series-sum-i32 (dataframe-column tail2 "x")) 11) ;; 5+6

  (define mid
    (lazyframe-collect (lazyframe-slice (dataframe-lazy df-rows) 2 3)))
  (check-equal? (dataframe-height mid) 3)
  (define (lazy-height cut) (dataframe-height (lazyframe-collect (cut (dataframe-lazy df-rows)))))
  (for* ([n (list (expt 2 32) (add1 (expt 2 32)) (expt 2 63) (sub1 (expt 2 64)))]
         [row (list (list 'head (lambda (lf) (lazyframe-head lf n)) 6)
                    (list 'tail (lambda (lf) (lazyframe-tail lf n)) 6)
                    (list 'slice (lambda (lf) (lazyframe-slice lf 1 n)) 5))])
    (match-define (list name cut height) row)
    (check-equal? (lazy-height cut) height (format "~a ~a" name n)))
  (for ([row (list (list (- (expt 2 33)) (+ (expt 2 33) 2) 6)
                   (list (- (expt 2 33)) (- (expt 2 33) 3) 3)
                   (list (- (expt 2 63)) (+ (expt 2 63) 2) 6)
                   (list (- (expt 2 63)) (- (expt 2 63) 4) 2)
                   (list (- (expt 2 63)) (sub1 (expt 2 64)) 6)
                   (list 2 (sub1 (expt 2 64)) 4))])
    (match-define (list offset length height) row)
    (check-equal? (lazy-height (lambda (lf) (lazyframe-slice lf offset length))) height
                  (format "slice ~a ~a" offset length))
    (check-equal? (lazy-height
                   (lambda (lf)
                     (lazyframe-select lf (list (contracted:expr-slice (col "x") offset length)))))
                  height
                  (format "expr-slice ~a ~a" offset length)))
  (check-equal? (series-sum-i32 (dataframe-column mid "x")) 12) ;; 3+4+5

  ;; pipeline: filter then take first two — no intermediate collect.
  (define top-two-after-filter
    (lazyframe-collect
     (lazyframe-head
      (lazyframe-sort
       (lazyframe-filter (dataframe-lazy df-rows) (expr-gt (col "x") 1))
       '("x") #:descending #t)
      2)))
  (check-equal? (dataframe-height top-two-after-filter) 2)
  ;; sorted desc {6,5,4,3,2}, head 2 -> {6,5}
  (check-equal? (series-sum-i32 (dataframe-column top-two-after-filter "x")) 11)

  ;; --- Phase A8 tests: lazy join ---

  (define users
    (dataframe-new
     (list (series-new-i32 "uid"  '(1 2 3 4))
           (series-new-str "name" '("a" "b" "c" "d")))))
  (define orders
    (dataframe-new
     (list (series-new-i32 "uid"    '(1 1 2 5))
           (series-new-i32 "amount" '(10 20 30 40)))))

  ;; inner join on shared key
  (define joined-inner
    (lazyframe-collect
     (lazyframe-join (dataframe-lazy users) (dataframe-lazy orders)
                     #:on '("uid") #:how 'inner)))
  ;; uids 1,1,2 match -> 3 rows; amounts 10+20+30=60
  (check-equal? (dataframe-height joined-inner) 3)
  (check-equal? (series-sum-i32 (dataframe-column joined-inner "amount")) 60)

  ;; left join keeps unmatched users (uid=3,4)
  (define joined-left
    (lazyframe-collect
     (lazyframe-join (dataframe-lazy users) (dataframe-lazy orders)
                     #:on '("uid") #:how 'left)))
  (check-equal? (dataframe-height joined-left) 5) ;; 1,1,2,3,4

  ;; #:left-on / #:right-on with differently named keys
  (define orders-r
    (dataframe-new
     (list (series-new-i32 "buyer"  '(1 1 2 5))
           (series-new-i32 "amount" '(10 20 30 40)))))
  (define joined-named
    (lazyframe-collect
     (lazyframe-join (dataframe-lazy users) (dataframe-lazy orders-r)
                     #:left-on '("uid") #:right-on '("buyer") #:how 'inner)))
  (check-equal? (dataframe-height joined-named) 3)
  (check-equal? (series-sum-i32 (dataframe-column joined-named "amount")) 60)

  ;; cross join: 4 users x 4 orders = 16
  (define joined-cross
    (lazyframe-collect
     (lazyframe-join (dataframe-lazy users) (dataframe-lazy orders)
                     #:how 'cross)))
  (check-equal? (dataframe-height joined-cross) 16)

  ;; pipeline: lazy join → group_by_agg, no intermediate collect
  (define per-user
    (lazyframe-collect
     (lazyframe-group-by-agg
      (lazyframe-join (dataframe-lazy users) (dataframe-lazy orders)
                      #:on '("uid") #:how 'inner)
      '("uid")
      (list (expr-alias (expr-sum (col "amount")) "total")))))
  (check-equal? (dataframe-height per-user) 2)
  ;; total across groups = 60
  (check-equal? (series-sum-i32 (dataframe-column per-user "total")) 60)

  ;; --- Phase A9 tests: expr cast ---

  (define df-cast
    (dataframe-new
     (list (series-new-i32 "x" '(1 2 3 4)))))

  ;; i32 -> f64
  (define cast-f64
    (dataframe-with-columns
     df-cast
     (list (expr-alias (expr-cast (col "x") 'float64) "xf"))))
  (check-equal? (series-dtype (dataframe-column cast-f64 "xf")) 'float64)
  (check-= (series-sum-f64 (dataframe-column cast-f64 "xf")) 10.0 1e-9)

  ;; i32 -> i64
  (define cast-i64
    (dataframe-with-columns
     df-cast
     (list (expr-alias (expr-cast (col "x") 'int64) "xl"))))
  (check-equal? (series-dtype (dataframe-column cast-i64 "xl")) 'int64)

  ;; i32 -> string
  (define cast-str
    (dataframe-with-columns
     df-cast
     (list (expr-alias (expr-cast (col "x") 'string) "xs"))))
  (check-equal? (series-dtype (dataframe-column cast-str "xs")) 'string)

  ;; i32 -> boolean (nonzero -> #t)
  (define cast-bool
    (dataframe-with-columns
     df-cast
     (list (expr-alias (expr-cast (col "x") 'boolean) "xb"))))
  (check-equal? (series-dtype (dataframe-column cast-bool "xb")) 'boolean)

  ;; cast inside a pipeline: literal i32 -> f64, then divide
  (define df-div
    (dataframe-with-columns
     df-cast
     (list (expr-alias (expr-div (expr-cast (col "x") 'float64)
                                 (expr-cast (lit 2) 'float64))
                       "half"))))
  (check-equal? (series-dtype (dataframe-column df-div "half")) 'float64)
  (check-= (series-sum-f64 (dataframe-column df-div "half"))
           5.0 ;; (1+2+3+4)/2
           1e-9)

  ;; datetime cast — bare symbol defaults to microseconds
  (define df-ts
    (dataframe-new
     (list (series-new-i64 "t" '(0 1000 2000 3000)))))
  (define cast-dt
    (dataframe-with-columns
     df-ts
     (list (expr-alias (expr-cast (col "t") 'datetime) "ts"))))
  (define dt-tag (series-dtype (dataframe-column cast-dt "ts")))
  (check-equal? (car dt-tag) 'datetime)
  (check-equal? (cadr dt-tag) 'microseconds)

  ;; datetime cast with explicit time unit
  (define cast-dt-ns
    (dataframe-with-columns
     df-ts
     (list (expr-alias (expr-cast (col "t") '(datetime nanoseconds)) "ts"))))
  (check-equal? (cadr (series-dtype (dataframe-column cast-dt-ns "ts")))
                'nanoseconds)

  ;; unsupported target raises (not panics)
  (check-exn exn:fail? (lambda () (expr-cast (col "x") 'no-such-dtype)))

  ;; --- Phase A10 tests: expr-std / expr-var with #:ddof ---

  (define df-stats
    (dataframe-new
     (list (series-new-i32 "g" '(1 1 1 1))
           (series-new-f64 "v" '(2.0 4.0 4.0 6.0)))))

  ;; sample std (ddof=1, default): mean=4, deviations {-2,0,0,2},
  ;; variance = (4+0+0+4)/(4-1) = 8/3, std = sqrt(8/3) ~= 1.6329932
  (define stats-default
    (dataframe-select-exprs
     df-stats
     (list (expr-alias (expr-std (col "v")) "s")
           (expr-alias (expr-var (col "v")) "v"))))
  (check-equal? (dataframe-height stats-default) 1)
  (check-= (series-sum-f64 (dataframe-column stats-default "s"))
           1.6329931618554518 1e-9)
  (check-= (series-sum-f64 (dataframe-column stats-default "v"))
           (/ 8.0 3.0) 1e-9)

  ;; population std/var (ddof=0): variance = 8/4 = 2, std = sqrt(2)
  (define stats-pop
    (dataframe-select-exprs
     df-stats
     (list (expr-alias (expr-std (col "v") #:ddof 0) "s")
           (expr-alias (expr-var (col "v") #:ddof 0) "v"))))
  (check-= (series-sum-f64 (dataframe-column stats-pop "s"))
           1.4142135623730951 1e-9)
  (check-= (series-sum-f64 (dataframe-column stats-pop "v"))
           2.0 1e-9)

  ;; std inside a group_by_agg pipeline
  (define df-grp-stats
    (dataframe-new
     (list (series-new-str "g" '("a" "a" "a" "b" "b" "b"))
           (series-new-f64 "v" '(1.0 2.0 3.0 10.0 20.0 30.0)))))
  (define grp-std
    (dataframe-group-by-agg
     df-grp-stats
     '("g")
     (list (expr-alias (expr-std (col "v")) "s"))))
  (check-equal? (dataframe-height grp-std) 2)
  ;; per-group sample std: a -> 1.0, b -> 10.0; total = 11.0
  (check-= (series-sum-f64 (dataframe-column grp-std "s")) 11.0 1e-9)

  ;; --- when / then / otherwise ---
  (define df-when
    (dataframe-new (list (series-new-i32 "x" '(-3 0 4 12 7)))))

  ;; single clause, string values
  (define when-sign
    (dataframe-with-columns
     df-when
     (list (expr-alias (expr-when (list (list (expr-gt (col "x") 0) "pos"))
                                  #:otherwise "non-pos")
                       "sign"))))
  (check-equal? (for/list ([i (in-range 5)])
                  (series-ref (dataframe-column when-sign "sign") i))
                '("non-pos" "non-pos" "pos" "pos" "pos"))

  ;; chained clauses, numeric values (auto-lifted scalars)
  (define when-bucket
    (dataframe-with-columns
     df-when
     (list (expr-alias
            (expr-when (list (list (expr-lt (col "x") 0) 0)
                             (list (expr-eq (col "x") 0) 1)
                             (list (expr-lt (col "x") 10) 2))
                       #:otherwise 3)
            "bucket"))))
  (check-equal? (for/list ([i (in-range 5)])
                  (series-ref (dataframe-column when-bucket "bucket") i))
                '(0 1 2 3 2))

  (check-exn exn:fail? (lambda () (expr-when '() #:otherwise 0)))
  (check-exn exn:fail?
             (lambda () (expr-when (list (list (col "x"))) #:otherwise 0)))

  ;; --- null / NaN handling ---
  (define df-nn
    (dataframe-new
     (list (series-new-f64 "x" (list 1.0 polars-null 3.0 polars-null 5.0))
           (series-new-f64 "y" (list 1.0 +nan.0 3.0 +inf.0 -1.0)))))
  (define nn
    (dataframe-with-columns
     df-nn
     (list (expr-alias (expr-fill-null (col "x") 0.0) "xf")
           (expr-alias (expr-forward-fill (col "x")) "xff")
           (expr-alias (expr-fill-nan (col "y") -99.0) "ynn")
           (expr-alias (expr-is-nan (col "y")) "yn")
           (expr-alias (expr-is-finite (col "y")) "yfin")
           (expr-alias (expr-is-infinite (col "y")) "yinf"))))
  (define (col->list df name)
    (for/list ([i (in-range 5)]) (series-ref (dataframe-column df name) i)))
  (check-equal? (col->list nn "xf") '(1.0 0.0 3.0 0.0 5.0))
  (check-equal? (col->list nn "xff") '(1.0 1.0 3.0 3.0 5.0))
  (check-equal? (col->list nn "ynn") (list 1.0 -99.0 3.0 +inf.0 -1.0))
  (check-equal? (col->list nn "yn") '(#f #t #f #f #f))
  (check-equal? (col->list nn "yfin") '(#t #f #t #f #t))
  (check-equal? (col->list nn "yinf") '(#f #f #f #t #f))

  ;; drop_nulls collapses the column length
  (define dn-x
    (dataframe-select-exprs df-nn
                            (list (expr-alias (expr-drop-nulls (col "x")) "x"))))
  (check-equal? (series-len (dataframe-column dn-x "x")) 3)
  (check-= (series-sum-f64 (dataframe-column dn-x "x")) 9.0 1e-9)

  ;; --- element-wise math ---
  (define df-m
    (dataframe-new (list (series-new-f64 "x" '(-2.4 -1.0 0.0 1.6 4.0)))))
  (define m
    (dataframe-with-columns
     df-m
     (list (expr-alias (expr-abs (col "x")) "abs")
           (expr-alias (expr-sign (col "x")) "sign")
           (expr-alias (expr-round (col "x") #:decimals 0) "r0")
           (expr-alias (expr-floor (col "x")) "fl")
           (expr-alias (expr-ceil (col "x")) "ce")
           (expr-alias (expr-clip (col "x") #:lower -1.0 #:upper 2.0) "cl")
           (expr-alias (expr-clip (col "x") #:lower 0.0) "cmin")
           (expr-alias (expr-pow (expr-abs (col "x")) 2) "sq")
           (expr-alias (expr-log (expr-abs (col "x")) #:base 2) "log2"))))
  (check-equal? (col->list m "abs") '(2.4 1.0 0.0 1.6 4.0))
  (check-equal? (col->list m "sign") '(-1.0 -1.0 0.0 1.0 1.0))
  (check-equal? (col->list m "r0") '(-2.0 -1.0 0.0 2.0 4.0))
  (check-equal? (col->list m "fl") '(-3.0 -1.0 0.0 1.0 4.0))
  (check-equal? (col->list m "ce") '(-2.0 -1.0 0.0 2.0 4.0))
  (check-equal? (col->list m "cl") '(-1.0 -1.0 0.0 1.6 2.0))
  (check-equal? (col->list m "cmin") '(0.0 0.0 0.0 1.6 4.0))
  (check-= (series-ref (dataframe-column m "sq") 4) 16.0 1e-9)
  (check-= (series-ref (dataframe-column m "log2") 4) 2.0 1e-9)

  ;; --- membership / distinct predicates ---
  (define df-p
    (dataframe-new (list (series-new-i64 "x" '(1 2 2 3 5 5 8)))))
  (define p
    (dataframe-with-columns
     df-p
     (list (expr-alias (expr-is-in (col "x") '(2 3 8)) "in")
           (expr-alias (expr-is-between (col "x") 2 5) "btw")
           (expr-alias (expr-is-between (col "x") 2 5 #:closed 'left) "btwl")
           (expr-alias (expr-is-unique (col "x")) "u")
           (expr-alias (expr-is-duplicated (col "x")) "d")
           (expr-alias (expr-is-first-distinct (col "x")) "f")
           (expr-alias (expr-is-last-distinct (col "x")) "l"))))
  (define (col7 name)
    (for/list ([i (in-range 7)]) (series-ref (dataframe-column p name) i)))
  (check-equal? (col7 "in")   '(#f #t #t #t #f #f #t))
  (check-equal? (col7 "btw")  '(#f #t #t #t #t #t #f))
  (check-equal? (col7 "btwl") '(#f #t #t #t #f #f #f))
  (check-equal? (col7 "u")    '(#t #f #f #t #f #f #t))
  (check-equal? (col7 "d")    '(#f #t #t #f #t #t #f))
  (check-equal? (col7 "f")    '(#t #t #f #t #t #f #t))
  (check-equal? (col7 "l")    '(#t #f #t #t #f #t #t))
  (define none-in
    (dataframe-select-exprs df-p (list (expr-alias (expr-is-in (col "x") '()) "in"))))
  (check-equal? (for/list ([i (in-range 7)]) (series-ref (dataframe-column none-in "in") i))
                '(#f #f #f #f #f #f #f))
  (check-exn exn:fail? (lambda () (expr-is-between (col "x") 2 5 #:closed 'wat)))
  (check-exn #rx"^expr-is-in: contract violation;\n the list mixes integers and floats"
             (lambda () (expr-is-in (col "x") (list 1 2.5))))

  ;; --- cumulative + shift / diff ---
  (define df-c (dataframe-new (list (series-new-i64 "x" '(1 2 3 4 5)))))
  (define cdf
    (dataframe-with-columns
     df-c
     (list (expr-alias (expr-cum-sum (col "x")) "cs")
           (expr-alias (expr-cum-sum (col "x") #:reverse #t) "csr")
           (expr-alias (expr-cum-prod (col "x")) "cp")
           (expr-alias (expr-cum-min (col "x")) "cmin")
           (expr-alias (expr-cum-max (col "x")) "cmax")
           (expr-alias (expr-cum-count (col "x")) "cc")
           (expr-alias (expr-shift (col "x") #:n 1) "s1")
           (expr-alias (expr-shift (col "x") #:n 1 #:fill-value 0) "s1f")
           (expr-alias (expr-diff (col "x") #:n 1) "d1"))))
  (define (c5 name)
    (for/list ([i (in-range 5)]) (series-ref (dataframe-column cdf name) i)))
  (check-equal? (c5 "cs")   '(1 3 6 10 15))
  (check-equal? (c5 "csr")  '(15 14 12 9 5))
  (check-equal? (c5 "cp")   '(1 2 6 24 120))
  (check-equal? (c5 "cmin") '(1 1 1 1 1))
  (check-equal? (c5 "cmax") '(1 2 3 4 5))
  (check-equal? (series-ref (dataframe-column cdf "cc") 4) 5)
  (check-equal? (c5 "s1")   (list polars-null 1 2 3 4))
  (check-equal? (c5 "s1f")  '(0 1 2 3 4))
  (check-equal? (c5 "d1")   (list polars-null 1 1 1 1))
  (check-exn #rx"^expr-diff: contract violation"
             (lambda () (contracted:expr-diff (col "x") #:null-behavior 'wat)))
  (check-exn #rx"^expr-shift: contract violation"
             (lambda () (contracted:expr-shift (col "x") #:n 1.5)))

  ;; --- sorting / selection helpers ---
  (define df-s
    (dataframe-new (list (series-new-i64 "x" '(30 10 50 20 40))
                         (series-new-str "g" '("b" "a" "b" "a" "b")))))
  (define (take5 df name)
    (for/list ([i (in-range 5)]) (series-ref (dataframe-column df name) i)))
  ;; rank + reverse keep length, so they work inside with_columns
  (define s-wc
    (dataframe-with-columns
     df-s
     (list (expr-alias (expr-rank (col "x") #:method 'dense) "rk")
           (expr-alias (expr-reverse (col "x")) "xr"))))
  (check-equal? (take5 s-wc "rk") '(3 1 5 2 4))
  (check-equal? (take5 s-wc "xr") '(40 20 50 10 30))
  ;; sort_by (string keys lifted via ->key-expr)
  (define s-sorted
    (dataframe-select-exprs
     df-s
     (list (expr-alias (expr-sort-by (col "x") #:by "x") "xs")
           (expr-alias (expr-sort-by (col "g") #:by "x") "gx"))))
  (check-equal? (take5 s-sorted "xs") '(10 20 30 40 50))
  (check-equal? (take5 s-sorted "gx") '("a" "a" "b" "b" "b"))
  (define s-sd
    (dataframe-select-exprs
     df-s (list (expr-alias (expr-sort-by (col "x") #:by "x" #:descending #t) "xs"))))
  (check-equal? (take5 s-sd "xs") '(50 40 30 20 10))
  ;; head / tail / slice (all length 2 here, so fine in one select)
  (define s-w
    (dataframe-select-exprs
     df-s
     (list (expr-alias (expr-head (col "x") #:n 2) "h")
           (expr-alias (expr-tail (col "x") #:n 2) "t")
           (expr-alias (expr-slice (col "x") 1 2) "sl"))))
  (define (take2 name)
    (for/list ([i (in-range 2)]) (series-ref (dataframe-column s-w name) i)))
  (check-equal? (take2 "h") '(30 10))
  (check-equal? (take2 "t") '(20 40))
  (check-equal? (take2 "sl") '(10 50))
  (for ([n (list (expt 2 63) (sub1 (expt 2 64)))])
    (define whole
      (dataframe-select-exprs df-s (list (expr-alias (expr-head (col "x") #:n n) "h")
                                         (expr-alias (expr-tail (col "x") #:n n) "t"))))
    (check-equal? (take5 whole "h") '(30 10 50 20 40) (format "~a" n))
    (check-equal? (take5 whole "t") '(30 10 50 20 40) (format "~a" n)))
  ;; filter + gather
  (define s-f
    (dataframe-select-exprs
     df-s (list (expr-alias (expr-filter (col "x") (expr-gt (col "x") 25)) "b"))))
  (check-equal? (series-len (dataframe-column s-f "b")) 3)
  (check-equal? (for/list ([i (in-range 3)]) (series-ref (dataframe-column s-f "b") i))
                '(30 50 40))
  (define s-g
    (dataframe-select-exprs
     df-s (list (expr-alias (expr-gather (col "x") '(0 2 4)) "g"))))
  (check-equal? (for/list ([i (in-range 3)]) (series-ref (dataframe-column s-g "g") i))
                '(30 50 40))
  (check-exn exn:fail? (lambda () (expr-sort-by (col "x") #:by '())))

  (define reclaim-src (dataframe-new (list (series-new-i64 "x" '(1 2 3 4 5)))))
  (settle!)
  (let* ([wanted 20]
         [before (dataframe-drop-count)])
    (for ([_ (in-range wanted)])
      (lazyframe-collect (dataframe-lazy reclaim-src)))
    ;; finalizers run on their own thread, so assert a lenient fraction
    (settle!)
    (check >= (- (dataframe-drop-count) before) (quotient wanted 2)))

  (check-exn #rx"^lazyframe-collect: not found: unable to find column \"nope\"[^\n]*$"
             (lambda ()
               (lazyframe-collect
                (lazyframe-select (dataframe-lazy reclaim-src) (list (col "nope"))))))

  (define gone (build-path (find-system-path 'temp-dir) "rkt-polars-no-such-scan.csv"))
  (when (file-exists? gone)
    (delete-file gone))
  (define deferred (lazyframe-scan-csv gone))
  (check-pred LazyFrame-ptr? deferred)
  (check-exn #rx"^lazyframe-collect: [^\n]+$"
             (lambda () (lazyframe-collect deferred)))

  (define bad-glob (lazyframe-scan-csv "/tmp/[.csv"))
  (check-pred LazyFrame-ptr? bad-glob)
  (check-exn #rx"^lazyframe-collect: .*glob"
             (lambda () (lazyframe-collect bad-glob)))
  (for ([op (list expr-add expr-sub expr-mul expr-div expr-mod expr-gt expr-lt expr-ge expr-le
                  expr-eq expr-ne expr-and expr-or expr-xor)])
    (check-exn (regexp (format "^~a: contract violation\n  expected: ~a\n" (object-name op)
                               (regexp-quote (format "~s" (contract-name lit-integer/c)))))
               (lambda () (op (col "x") (expt 2 64))))
    (check-exn (regexp (format "^~a: contract violation\n[^\n]*\n  given: #\\\\a$" (object-name op)))
               (lambda () (op #\a (col "x")))))

  (define ((sort-blame? rx) e)
    (and (exn:fail:contract:blame? e) (regexp-match? rx (exn-message e))))
  (define sort-lf (dataframe-lazy (dataframe-new (list (series-new-i64 "g" '(2 1))
                                                       (series-new-i64 "h" '(1 2))))))
  (check-exn (sort-blame? #rx"^expr-sort-by: contract violation")
             (lambda () (contracted:expr-sort-by (col "g") #:by '("g" "h") #:nulls-last '(#t))))
  (check-exn (sort-blame? #rx"^expr-sort-by: contract violation")
             (lambda () (contracted:expr-sort-by (col "g") #:by '())))
  (check-exn (sort-blame? #rx"^expr-sort: contract violation")
             (lambda () (contracted:expr-sort (col "g") #:nulls-last 'yes)))
  (check-exn (sort-blame? #rx"^lazyframe-sort: contract violation")
             (lambda () (contracted:lazyframe-sort sort-lf '())))
  (check-exn (sort-blame? #rx"^dataframe-sort-exprs: contract violation")
             (lambda () (contracted:dataframe-sort-exprs
                         (lazyframe-collect sort-lf) '("g") #:descending '(#t #t))))
  (check-equal? (series-ref (dataframe-column (contracted:dataframe-sort-exprs
                                               (lazyframe-collect sort-lf) '("g")
                                               #:descending #t #:nulls-last #t)
                                              "g")
                            0)
                2)

  (define sort-g (col "g"))
  (define sort-h (col "h"))
  (settle!)
  (define sort-drops-before (expr-drop-count))
  (for ([_ (in-range 100)])
    (contracted:expr-sort sort-g #:nulls-last #t)
    (contracted:expr-sort-by sort-g #:by sort-h #:nulls-last #t #:maintain-order #t))
  (settle!)
  (check >= (- (expr-drop-count) sort-drops-before) 150)

  (define range-lf (dataframe-lazy (dataframe-new (list (series-new-i64 "v" '(1 2 3))))))
  (define v (col "v"))
  (check-equal?
   (refusal-misses
    (list (refusal 'expr-std uint8/c 256 (contracted:expr-std v #:ddof 256))
          (refusal 'expr-std uint8/c -1 (contracted:expr-std v #:ddof -1))
          (refusal 'expr-var uint8/c 256 (contracted:expr-var v #:ddof 256))
          (refusal 'expr-round uint32/c (expt 2 32) (contracted:expr-round v #:decimals (expt 2 32)))
          (refusal 'expr-round uint32/c -1 (contracted:expr-round v #:decimals -1))
          (refusal 'expr-forward-fill (or/c #f uint32/c) (expt 2 32)
                   (contracted:expr-forward-fill v #:limit (expt 2 32)))
          (refusal 'expr-backward-fill (or/c #f uint32/c) -1
                   (contracted:expr-backward-fill v #:limit -1))
          (refusal 'expr-rank (or/c #f uint64/c) (expt 2 64)
                   (contracted:expr-rank v #:seed (expt 2 64)))
          (refusal 'expr-rank rank-method/c 'first (contracted:expr-rank v #:method 'first))
          (refusal 'expr-rank boolean? 1 (contracted:expr-rank v #:descending 1))
          (refusal 'expr-head (or/c #f size/c) (expt 2 64) (contracted:expr-head v #:n (expt 2 64)))
          (refusal 'expr-tail (or/c #f size/c) -1 (contracted:expr-tail v #:n -1))
          (refusal 'expr-shift int64/c (expt 2 63) (contracted:expr-shift v #:n (expt 2 63)))
          (refusal 'expr-diff int64/c (expt 2 63) (contracted:expr-diff v #:n (expt 2 63)))
          (refusal 'expr-diff null-behavior/c 'keep (contracted:expr-diff v #:null-behavior 'keep))
          (refusal 'expr-slice size/c (expt 2 64) (contracted:expr-slice v 0 (expt 2 64)))
          (refusal 'expr-slice size/c -1 (contracted:expr-slice v 0 -1))
          (refusal 'expr-slice int64/c (expt 2 63) (contracted:expr-slice v (expt 2 63) 1))
          (refusal 'expr-slice size/c 1.5 (contracted:expr-slice v 0 1.5))
          (refusal 'expr-str-extract size/c (expt 2 64)
                   (contracted:expr-str-extract v "(a)" #:group-index (expt 2 64)))
          (refusal 'expr-lit-i32 int32/c (expt 2 31) (contracted:expr-lit-i32 (expt 2 31)))
          (refusal 'expr-lit-i64 int64/c (expt 2 63) (contracted:expr-lit-i64 (expt 2 63)))
          (refusal 'lazyframe-head size/c (expt 2 64)
                   (contracted:lazyframe-head range-lf (expt 2 64)))
          (refusal 'lazyframe-tail size/c -1 (contracted:lazyframe-tail range-lf -1))
          (refusal 'lazyframe-slice int64/c (expt 2 63)
                   (contracted:lazyframe-slice range-lf (expt 2 63) 1))))
   '())
  (define rank-input (dataframe-new (list (series-new-i64 "v" '(3 1 3)))))
  (check-equal? (for/list ([method (in-list rank-methods)])
                  (define ranks
                    (dataframe-column
                     (dataframe-select-exprs
                      rank-input (list (contracted:expr-rank v #:method method #:descending #t)))
                     "v"))
                  (for/list ([i (in-range 3)]) (series-ref ranks i)))
                '((1.5 3.0 1.5) (1 3 1) (2 3 2) (1 2 1) (1 3 2)))
  (define widest
    (dataframe-select-exprs
     (dataframe-new (list (series-new-f64 "v" '(1.0 2.0))))
     (list (expr-alias (contracted:expr-std (col "v") #:ddof 255) "s"))))
  (check-equal? (dataframe-height widest) 1)
  (define population
    (dataframe-select-exprs
     (dataframe-new (list (series-new-f64 "v" '(2.0 4.0 4.0 6.0))))
     (list (expr-alias (contracted:expr-std (col "v") #:ddof 0) "s"))))
  (check-= (series-ref (dataframe-column population "s") 0) (sqrt 2) 1e-12))
