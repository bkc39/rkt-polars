#lang racket/base

(require (only-in racket/contract/base and/c flat-named-contract not/c unsupplied-arg?)
         (only-in racket/list check-duplicates)
         (only-in polars/private/c-integer
                  int64/c positive-size/c size-max size/c uint32/c))

(provide c-string/c column-index/c column-name/c distinct-names? distinct? given positive-size/c
         row-index/c size-max size/c)

(define row-index/c uint32/c)

(define column-index/c int64/c)

(define nul-free? (and/c string? (not/c #rx"\0")))

(define c-string/c (flat-named-contract 'c-string/c nul-free?))

(define column-name/c (flat-named-contract 'column-name/c nul-free?))

(define (distinct? vs)
  (not (check-duplicates vs)))

(define (distinct-names? pairs)
  (distinct? (map car pairs)))

(define (given v default)
  (if (unsupplied-arg? v) default v))
