#lang racket/base

;; DataFrame Batch 1: hstack, semi/anti joins, Parquet, JSON Lines.
;;
;; Inside `nix develop`:
;;   racket examples/19-dataframe-batch1.rkt

(require polars)

(define users
  (dataframe-new
   (list (series-new-i32 "uid" '(1 2 3 4))
         (series-new-str "name" '("alice" "bob" "carol" "dora")))))

(define orders
  (dataframe-new
   (list (series-new-i32 "uid" '(1 2 2 5))
         (series-new-i32 "amount" '(10 20 30 40)))))

(define with-region
  (dataframe-hstack users
                    (list (series-new-str "region"
                                          '("east" "west" "west" "east")))))

(displayln "hstack:")
(display-dataframe with-region)
(newline)

(displayln "semi join:")
(display-dataframe (dataframe-join users orders #:on '("uid") #:how 'semi))
(newline)

(displayln "anti join:")
(display-dataframe (dataframe-join users orders #:on '("uid") #:how 'anti))
(newline)

(define parquet-path
  (build-path (find-system-path 'temp-dir) "rkt-polars-batch1.parquet"))
(dataframe-write-parquet with-region parquet-path)
(displayln "parquet roundtrip:")
(display-dataframe (dataframe-read-parquet parquet-path))
(newline)

(define jsonl-path
  (build-path (find-system-path 'temp-dir) "rkt-polars-batch1.jsonl"))
(dataframe-write-json-lines with-region jsonl-path)
(displayln "json lines roundtrip:")
(display-dataframe (dataframe-read-json-lines jsonl-path))
