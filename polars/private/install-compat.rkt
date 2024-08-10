#lang racket/base

(provide pre-installer)

(define COMPAT-SRC-DIR "compat")

(define (pre-installer collections-top-path this-collection-path user-specific?)
  (printf "top: ~a~nthis: ~a~nspecific? ~a~n"
          collections-top-path
          this-collection-path
          user-specific?)
  (exit 1))
