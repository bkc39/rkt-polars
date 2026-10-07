#lang racket/base

;; rkt-polars user guide — IO: Parquet
;; Mirrors https://docs.pola.rs/user-guide/io/parquet/ and parquet.py; the
;; dtypes, pushdown and options sections extend the upstream page.
;;
;; Inside `nix develop`:
;;   racket user-guide/io/parquet.rkt

(require racket/file
         racket/runtime-path
         polars)

(define-runtime-path data-dir "../../polars/scribblings/data")
(define (data name) (build-path data-dir name))
(define dir (make-temporary-directory "polars-guide-~a"))
(define (scratch name) (build-path dir name))

;; --- read --------------------------------------------------------------------
(define flights (read-parquet (data "flights.parquet")))
(displayln (shape flights))
(displayln (~> flights (select "carrier" "dep_delay" "time_hour") (head 3)))

;; --- write -------------------------------------------------------------------
(define path (scratch "path.parquet"))
(define df
  (dataframe (list (series '(1 2 3) #:name "foo")
                   (series (list polars-null "bak" "baz") #:name "bar"))))
(write-parquet df path)
(displayln (read-parquet path))

;; --- scan --------------------------------------------------------------------
(displayln (collect (scan-parquet path)))

;; --- dtypes ------------------------------------------------------------------
(define produce (read-parquet (data "produce.parquet")))
(displayln produce)
(write-csv produce (scratch "produce.csv"))
(displayln (read-csv (scratch "produce.csv")))
(write-parquet produce (scratch "produce.parquet"))
(displayln (read-parquet (scratch "produce.parquet")))

(define stamps (select flights "time_hour"))
(write-csv stamps (scratch "stamps.csv"))
(displayln (dtype (ref (read-csv (scratch "stamps.csv")) "time_hour")))
(write-parquet stamps (scratch "stamps.parquet"))
(displayln (dtype (ref (read-parquet (scratch "stamps.parquet")) "time_hour")))

;; --- projection and predicate pushdown ---------------------------------------
(define late
  (~> (scan-parquet (data "flights.parquet"))
      (filter (> (col "dep_delay") 20))
      (select "carrier" "dep_delay")))
(displayln (explain late #:optimized #f))
(displayln (explain late))
(displayln (collect late))

;; --- options -----------------------------------------------------------------
(displayln (read-parquet (data "flights.parquet")
                         #:columns '("row" "carrier" "dep_delay") #:n-rows 3
                         #:row-index-name "row"))
(write-parquet flights (scratch "flights.parquet")
               #:compression 'gzip #:compression-level 9 #:statistics 'full
               #:row-group-size 50)
(displayln (shape (read-parquet (scratch "flights.parquet"))))

(delete-directory/files dir)

;; API gaps: no schema, extra_columns or metadata (#197).
