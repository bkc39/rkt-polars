#lang racket/base

(require racket/runtime-path
         (only-in racket/format ~a)
         (only-in racket/list filter-not)
         (only-in racket/string string-join)
         (only-in polars read-csv))

(provide data-file
         first-line
         keyword-call
         keyword-gap
         load-frame
         (struct-out loaded)
         median-ms
         polars-export
         reader-options)

(define-runtime-path data-dir "data")

(define (data-file source extension)
  (path->string
   (build-path data-dir
               (format "nycflights~a.~a" (if (eq? source 'nona) "-nona" "") extension))))

(define (reader-options source #:tab? tab?)
  (append (if tab? (list (cons '#:separator #\tab)) '())
          (if (eq? source 'original) (list (cons '#:null-values "NA")) '())))

(define (keyword-gap who proc keywords)
  (define-values (_required accepted) (procedure-keywords proc))
  (define missing
    (if accepted (filter-not (lambda (k) (memq k accepted)) keywords) '()))
  (and (pair? missing)
       (format "~a has no ~a" who (string-join (map ~a missing) ", "))))

(define (keyword-call proc options . positional)
  (define sorted (sort options keyword<? #:key car))
  (keyword-apply proc (map car sorted) (map cdr sorted) positional))

(define (polars-export name)
  (dynamic-require 'polars name (lambda () #f)))

(define (first-line e)
  (define line (car (regexp-match #rx"^[^\n]*" (exn-message e))))
  (if (> (string-length line) 160) (string-append (substring line 0 157) "...") line))

(struct loaded (frame source reason))

(define (try-read reader)
  (with-handlers ([exn:fail? (lambda (e) (cons #f (first-line e)))])
    (cons (reader) #f)))

(define (load-frame)
  (define options (reader-options 'original #:tab? #t))
  (define original
    (cond
      [(keyword-gap 'read-csv read-csv (map car options)) => (lambda (gap) (cons #f gap))]
      [else (try-read (lambda () (keyword-call read-csv options (data-file 'original "tsv"))))]))
  (define copy
    (if (car original) original (try-read (lambda () (read-csv (data-file 'nona "csv"))))))
  (cond
    [(car original) (loaded (car original) 'original #f)]
    [(car copy) (loaded (car copy) 'nona (cdr original))]
    [else (loaded #f 'nona (format "~a; the NA-stripped copy: ~a" (cdr original) (cdr copy)))]))

(define (median-ms thunk #:runs [runs 5])
  (thunk)
  (define times
    (for/list ([_ (in-range runs)])
      (collect-garbage 'major)
      (define start (current-inexact-monotonic-milliseconds))
      (thunk)
      (- (current-inexact-monotonic-milliseconds) start)))
  (list-ref (sort times <) (quotient runs 2)))
