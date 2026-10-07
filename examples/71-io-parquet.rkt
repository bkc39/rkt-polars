#lang racket/base

;; Parquet's reading and writing options, and pushdown into a scan.
;;
;; write-parquet picks a codec and its level, the statistics it writes and the
;; size of its row groups; read-parquet picks columns by name or position,
;; caps the rows and numbers them; scan-parquet reads only what its plan
;; needs, which explain shows.
;;
;; Inside `nix develop`:
;;   racket examples/71-io-parquet.rkt

(require racket/file
         racket/runtime-path
         polars)

(define-runtime-path flights-parquet "../polars/scribblings/data/flights.parquet")

(define dir (make-temporary-directory "rkt-polars-parquet-~a"))
(define (in-dir name) (build-path dir name))

(define flights (read-parquet flights-parquet))
(printf "flights: ~a\n" (shape flights))

(for ([codec '(uncompressed snappy lz4 gzip brotli zstd)])
  (define path (in-dir (format "flights-~a.parquet" codec)))
  (write-parquet flights path #:compression codec)
  (printf "~a: ~a bytes, reads back ~a\n" codec (file-size path) (shape (read-parquet path))))

(define (size-with . options)
  (define path (in-dir "sized.parquet"))
  (keyword-apply write-parquet (map car options) (map cdr options) (list flights path))
  (file-size path))
(printf "zstd level 1 / 22: ~a / ~a bytes\n"
        (size-with '(#:compression-level . 1))
        (size-with '(#:compression-level . 22)))
(printf "statistics #t / #f: ~a / ~a bytes\n"
        (size-with)
        (size-with '(#:statistics . #f)))
(printf "row groups of 10 rows: ~a bytes\n" (size-with '(#:row-group-size . 10)))

(displayln (read-parquet flights-parquet
                         #:columns '("row" "carrier" "time_hour")
                         #:n-rows 3
                         #:row-index-name "row"
                         #:row-index-offset 1))

(define late
  (~> (scan-parquet flights-parquet)
      (filter (> (col "dep_delay") 20))
      (select "carrier" "dep_delay")))
(displayln (explain late))
(displayln (collect late))

(write-parquet (select flights "carrier" "flight") (in-dir "part-1.parquet"))
(write-parquet (select flights "carrier") (in-dir "part-2.parquet"))
(define parts (in-dir "part-*.parquet"))
(displayln (with-handlers ([exn:fail? exn-message]) (read-parquet parts)))
(displayln (~> (read-parquet parts #:missing-columns 'insert) (ref "flight") null-count))

(delete-directory/files dir)
