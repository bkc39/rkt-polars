#lang racket/base

;; DataFrame Batch 1: hstack, semi/anti joins, Parquet, JSON Lines — all
;; prefix-free.
;;
;; Inside `nix develop`:
;;   racket examples/19-dataframe-batch1.rkt

(require racket/file              ; make-temporary-file
         polars)

(define users
  (dataframe (list (series '(1 2 3 4) #:name "uid" #:dtype 'i32)
                   (series '("alice" "bob" "carol" "dora") #:name "name"))))

(define orders
  (dataframe (list (series '(1 2 2 5)   #:name "uid" #:dtype 'i32)
                   (series '(10 20 30 40) #:name "amount" #:dtype 'i32))))

(define with-region
  (~> users (hstack (series '("east" "west" "west" "east") #:name "region"))))

(displayln "hstack:")
(displayln with-region)
(newline)

(displayln "semi join:")
(displayln (~> users (join orders #:on '("uid") #:how 'semi)))
(newline)

(displayln "anti join:")
(displayln (~> users (join orders #:on '("uid") #:how 'anti)))
(newline)

;; make-temporary-file creates a uniquely-named file (the ~a is filled in) and
;; returns its path; delete it when we're done.
(define parquet-path (make-temporary-file "rkt-polars-batch1-~a.parquet"))
(write-parquet with-region parquet-path)
(displayln "parquet roundtrip:")
(displayln (read-parquet parquet-path))
(delete-file parquet-path)
(newline)

(define jsonl-path (make-temporary-file "rkt-polars-batch1-~a.jsonl"))
(write-ndjson with-region jsonl-path)
(displayln "json lines roundtrip:")
(displayln (read-ndjson jsonl-path))
(delete-file jsonl-path)
