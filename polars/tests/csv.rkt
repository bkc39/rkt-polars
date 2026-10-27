#lang racket/base

(module+ test
  (require rackunit
           racket/file
           (prefix-in contracted: polars/private/csv)
           (submod polars/private/csv internal)
           (only-in polars/private/foreign
                    dataframe-column dataframe-column-names dataframe-drop dataframe-drop-count
                    dataframe-height dataframe-new dataframe-shape last-error-message
                    series-dtype series-new-f64 series-new-i32 series-new-str series-sum-f64)
           (only-in polars/tests/test-helpers
                    apply-keywords contract-violation-of drops-once message-of scratch-file
                    settle!))

  (define scratch (make-temporary-directory "rkt-polars-csv-~a"))

  (define cities
    (dataframe-new
     (list (series-new-str "city" '("Boston" "New York" "Chicago"))
           (series-new-f64 "population_millions" '(0.65 8.8 2.7))
           (series-new-i32 "founded" '(1630 1624 1837)))))
  (define cities-csv (build-path scratch "cities.csv"))
  (dataframe-write-csv cities cities-csv)
  (define cities-back (dataframe-read-csv cities-csv))
  (check-equal? (call-with-values (lambda () (dataframe-shape cities-back)) list) '(3 3))
  (check-equal? (dataframe-column-names cities-back) '("city" "population_millions" "founded"))
  (check-equal? (series-dtype (dataframe-column cities-back "founded")) 'int64)
  (check-equal? (series-dtype (dataframe-column cities-back "population_millions")) 'float64)
  (check-= (series-sum-f64 (dataframe-column cities-back "population_millions")) 12.15 1e-9)

  (define semicolons (build-path scratch "cities-semicolons.csv"))
  (dataframe-write-csv cities semicolons #:separator #\; #:include-header #f
                       #:float-precision 1 #:line-terminator "\r\n")
  (check-equal? (file->string semicolons)
                "Boston;0.7;1630\r\nNew York;8.8;1624\r\nChicago;2.7;1837\r\n")
  (check-equal? (dataframe-column-names
                 (dataframe-read-csv semicolons #:separator #\; #:has-header #f
                                     #:new-columns '("city" "population" "founded")))
                '("city" "population" "founded"))
  (check-false (last-error-message))
  (define unwritable (build-path "/" "rkt-polars-no-such-directory-45" "out.csv"))
  (check-exn #rx"^dataframe-write-csv: failed to write csv to .*: cannot create file: "
             (lambda () (dataframe-write-csv cities unwritable)))
  (for ([kv '((#:quote-style . sometimes) (#:line-terminator . "\r\u0000X")
               (#:null-value . "N\u0000A") (#:date-format . "%Y\u0000")
               (#:time-format . "\u0000") (#:datetime-format . "%F\u0000%T")
               (#:float-precision . 65536))])
    (check-exn (contract-violation-of 'dataframe-write-csv)
               (lambda () (apply-keywords contracted:dataframe-write-csv (list kv)
                                          cities semicolons))
               (format "~s" kv)))
  (check-equal? (object-name dataframe-write-csv) 'dataframe-write-csv)
  (check-exn #rx"^dataframe-read-csv: failed to read csv from [^:]*cities.csv: not found: unable to find column \"gate\""
             (lambda () (dataframe-read-csv cities-csv #:columns '("city" "gate"))))

  (define missing-csv (build-path scratch "no-such-file.csv"))
  (define missing-message (message-of (lambda () (dataframe-read-csv missing-csv))))
  (check-regexp-match
   #rx"^dataframe-read-csv: failed to read csv from .*: cannot open file: [Nn]o such file"
   missing-message)
  (check-equal? (length (regexp-match* #rx"no-such-file" missing-message)) 1)
  (check-regexp-match
   #rx"^lazyframe-scan-csv: failed to scan .*: cannot open file: [Nn]o such file"
   (message-of (lambda () (lazyframe-scan-csv missing-csv #:schema-overrides '(("x" . i64))))))

  (define na-csv (scratch-file scratch "na.csv" "x\n1\nNA\n3\n"))
  (make-directory (build-path scratch "parts"))
  (for ([name '("a" "b")] [text '("x\n1\nNA\n" "x\nNA\n4\n")])
    (scratch-file scratch (format "parts/~a.csv" name) text))
  (define parts (build-path scratch "parts" "*.csv"))
  (check-exn #rx"cannot open file" (lambda () (dataframe-read-csv missing-csv)))
  (check-equal? (dataframe-height (dataframe-read-csv na-csv #:null-values "NA")) 3)
  (check-false (last-error-message))
  (check-exn #rx"cannot open file" (lambda () (dataframe-read-csv missing-csv)))
  (check-equal? (dataframe-height (dataframe-read-csv parts #:null-values "NA")) 4)
  (check-false (last-error-message))
  (check-exn #rx"cannot open file" (lambda () (dataframe-read-csv missing-csv)))
  (check-equal? (dataframe-height (dataframe-read-csv na-csv #:null-values '(("x" . "NA")))) 3)
  (check-false (last-error-message))

  (for ([read (list (lambda () (dataframe-read-csv cities-csv))
                    (lambda () (dataframe-read-csv na-csv #:null-values "NA"))
                    (lambda () (dataframe-read-csv parts #:null-values "NA"))
                    (lambda () (dataframe-read-csv cities-csv #:columns '(0) #:row-index-name "i"))
                    (lambda () (dataframe-read-csv cities-csv #:new-columns '("x"))))])
    (check-equal? (drops-once dataframe-drop-count dataframe-drop read) 1))

  (let* ([wanted 20]
         [before (dataframe-drop-count)])
    (for ([_ (in-range wanted)])
      (dataframe-read-csv cities-csv))
    ;; finalizers run on their own thread, so assert a lenient fraction
    (settle!)
    (check >= (- (dataframe-drop-count) before) (quotient wanted 2)))

  (delete-directory/files scratch))
