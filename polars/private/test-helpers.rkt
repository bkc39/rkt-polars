#lang racket/base

;; Test helpers with no polars dependency, so a module below generic/core
;; (csv.rkt, parquet.rkt) can use them without a module cycle.

(require (only-in racket/contract exn:fail:contract:blame?)
         (only-in racket/file display-to-file)
         (only-in racket/path path-has-extension?))

(provide apply-keywords contract-violation-of message-of scratch-file staging-files)

(define (scratch-file dir name text)
  (define path (build-path dir name))
  (display-to-file text path #:exists 'replace)
  path)

(define ((contract-violation-of who) e)
  (and (exn:fail:contract:blame? e)
       (regexp-match? (regexp (format "^~a: contract violation" (regexp-quote (symbol->string who))))
                      (exn-message e))))

(define (message-of thunk)
  (with-handlers ([exn:fail? exn-message]) (thunk) #f))

(define (apply-keywords proc kvs . args)
  (define sorted (sort kvs keyword<? #:key car))
  (keyword-apply proc (map car sorted) (map cdr sorted) args))

(define (staging-files dir)
  (filter (lambda (name) (path-has-extension? name #".partial")) (directory-list dir)))
