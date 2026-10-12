#lang racket/base

(require (only-in racket/contract/base -> ->* contract-out or/c)
         (only-in polars/private/expr lazyframe-scan-parquet)
         (only-in polars/private/foreign dataframe-read-parquet dataframe-write-parquet)
         (only-in polars/private/generic/core
                  dataframe? define-wrapped lazyframe? wrap-dataframe wrap-lazyframe))

(provide (contract-out
          [read-parquet (-> path-string? dataframe?)]
          [scan-parquet (->* (path-string?)
                             (#:n-rows (or/c #f exact-nonnegative-integer?))
                             lazyframe?)]
          [write-parquet (-> dataframe? path-string? void?)]))

(define-wrapped read-parquet wrap-dataframe dataframe-read-parquet)
(define-wrapped scan-parquet wrap-lazyframe lazyframe-scan-parquet)
(define write-parquet dataframe-write-parquet)

(module+ test
  (require rackunit
           racket/file
           racket/runtime-path
           (only-in racket/list second)
           (only-in threading ~>)
           (only-in polars/private/bulk series->list)
           (only-in polars/private/generic/core column-names dataframe height ref series)
           (only-in polars/private/generic/printing series->string)
           (only-in polars/private/generic/csv read-csv)
           (only-in polars/private/generic/reshape collect)
           polars/private/generic/test-fixtures)

  (define-runtime-path data-dir "../../scribblings/data")
  (define scratch (make-temporary-directory "rkt-polars-parquet-~a"))
  (define (one-column value)
    (dataframe (list (series (list value) #:name "x"))))

  (for ([name '("b" "c" "a")] [value '(2 3 1)])
    (write-parquet (one-column value) (build-path scratch (format "~a.parquet" name))))
  (define parquet-pattern (build-path scratch "*.parquet"))
  (check-equal? (column (read-parquet parquet-pattern) "x") '(1 2 3))
  (check-equal? (~> parquet-pattern scan-parquet collect (column "x")) '(1 2 3))

  (define nothing (build-path scratch "*.none"))
  (check-pred lazyframe? (scan-parquet nothing))
  (for ([thunk (list (lambda () (read-parquet nothing))
                     (lambda () (collect (scan-parquet nothing))))])
    (check-exn #rx": no files match the pattern$" thunk))

  (define bracketed-dir (build-path scratch "proj[1]"))
  (for ([dir (list bracketed-dir (build-path scratch "proj1"))] [value '(7 1)])
    (make-directory* dir)
    (write-parquet (one-column value) (build-path dir "data.parquet")))
  (parameterize ([current-directory bracketed-dir])
    (check-equal? (column (read-parquet "data.parquet") "x") '(7))
    (check-equal? (~> "data.parquet" scan-parquet collect (column "x")) '(7))
    (make-directory* "hive/year=2013")
    (write-parquet (one-column 7) "hive/year=2013/p.parquet")
    (check-equal? (~> "hive" read-parquet (column "x")) '(7)))

  (for ([year '(2013 2014)])
    (define dir (build-path scratch "hive" (format "year=~a" year)))
    (make-directory* dir)
    (write-parquet (one-column year) (build-path dir "p.parquet")))
  (define hive (build-path scratch "hive"))
  (check-equal? (column-names (read-parquet (build-path hive "year=2013" "p.parquet"))) '("x"))
  (check-equal? (column-names (read-parquet (build-path hive "*" "p.parquet"))) '("x"))
  (check-equal? (~> (build-path hive "*" "p.parquet") scan-parquet collect column-names) '("x"))
  (check-equal? (column-names (read-parquet hive)) '("x" "year"))

  (define frame-parquet (build-path scratch "frame.parquet"))
  (write-parquet frame frame-parquet)
  (check-true (frame=? (read-parquet frame-parquet) frame))
  (check-equal? (height (collect (scan-parquet frame-parquet #:n-rows 2))) 2)
  (define from-csv (read-csv (build-path data-dir "parts" "part-1.csv")))
  (define from-csv-parquet (build-path scratch "from-csv.parquet"))
  (write-parquet from-csv from-csv-parquet)
  (check-true (frame=? (read-parquet from-csv-parquet) from-csv))

  (define produce (read-parquet (build-path data-dir "produce.parquet")))
  (check-equal? (map second (dtypes-of produce))
                '(categorical (enum low mid high) (decimal 10 2)))
  (check-equal? (column produce "item") '(apple pear apple fig))
  (check-equal? (series->list (ref produce "grade")) (list 'high 'low polars-null 'mid))
  (check-equal? (column produce "price") (list 5/4 4/5 polars-null 12))
  (check-regexp-match #rx"\\[decimal\\[10,2\\]\\]\n\\[\n\t1.25\n\t0.80\n\tnull\n\t12.00\n\\]"
                      (series->string (ref produce "price")))
  (define produce-copy (build-path scratch "produce.parquet"))
  (write-parquet produce produce-copy)
  (check-true (frame=? (read-parquet produce-copy) produce))

  (delete-directory/files scratch))
