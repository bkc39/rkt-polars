#lang racket/base

(require (only-in racket/contract/base flat-named-contract unsupplied-arg?)
         (only-in racket/list check-duplicates)
         (only-in polars/private/c-integer
                  int64/c positive-size/c size-max size/c uint32/c))

(provide column-index/c column-name/c distinct-names? distinct? given positive-size/c row-index/c
         size-max size/c)

(define row-index/c uint32/c)

(define column-index/c int64/c)

(define column-name/c (flat-named-contract 'column-name/c (procedure-rename string? 'column-name?)))

(define (distinct? vs)
  (not (check-duplicates vs)))

(define (distinct-names? pairs)
  (distinct? (map car pairs)))

(define (given v default)
  (if (unsupplied-arg? v) default v))
