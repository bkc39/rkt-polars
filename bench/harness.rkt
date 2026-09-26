#lang racket/base

(require racket/runtime-path
         (only-in racket/format ~a)
         (only-in racket/list filter-not)
         (only-in racket/match match* match-define)
         (only-in racket/string string-join)
         (only-in polars collect len read-csv ref scan-csv ~>))

(provide data-file
         ensure-data
         first-line
         load-frame
         (struct-out loaded)
         median-ms
         polars-export
         read-frame
         require-keywords
         scan-frame
         series-values)

(define-runtime-path data-dir "data")

(define (data-file source extension)
  (~> (format "nycflights~a.~a" (if (eq? source 'nona) "-nona" "") extension)
      (build-path data-dir _)
      path->string))

(define (ensure-data)
  (for* ([source (in-list '(original nona))]
         [extension (in-list '("tsv" "csv"))])
    (define file (data-file source extension))
    (unless (file-exists? file)
      (raise-user-error 'bench "~a is missing; `nix run .#bench` fetches and derives the data" file))))

(define (require-keywords who proc keywords)
  (define-values (_required accepted) (procedure-keywords proc))
  (define missing
    (if accepted (filter-not (lambda (k) (memq k accepted)) keywords) '()))
  (unless (null? missing)
    (error (format "~a has no ~a" who (string-join (map ~a missing) ", ")))))

(define (polars-export name [missing (lambda () (error (format "polars has no ~a" name)))])
  (dynamic-require 'polars name missing))

(define (reader-keywords source tab?)
  (append (if tab? '(#:separator) '())
          (if (eq? source 'original) '(#:null-values) '())))

(define (read-frame source extension)
  (define path (data-file source extension))
  (define tab? (equal? extension "tsv"))
  (require-keywords 'read-csv read-csv (reader-keywords source tab?))
  (match* (source tab?)
    [('original #t) (read-csv path #:separator #\tab #:null-values "NA")]
    [('original #f) (read-csv path #:null-values "NA")]
    [('nona #t) (read-csv path #:separator #\tab)]
    [('nona #f) (read-csv path)]))

(define (scan-frame source)
  (define path (data-file source "tsv"))
  (require-keywords 'scan-csv scan-csv (reader-keywords source #t))
  (collect (if (eq? source 'original)
               (scan-csv path #:separator #\tab #:null-values "NA")
               (scan-csv path #:separator #\tab))))

(struct loaded (frame source reason))

(define (load-frame)
  (with-handlers ([exn:fail? (lambda (e) (load-copy (first-line e)))])
    (loaded (read-frame 'original "tsv") 'original #f)))

(define (load-copy reason)
  (with-handlers ([exn:fail?
                   (lambda (e)
                     (loaded #f 'nona (format "~a; the NA-stripped copy: ~a" reason (first-line e))))])
    (loaded (read-frame 'nona "csv") 'nona reason)))

(define (first-line e)
  (match-define (list line) (regexp-match #rx"^[^\n]*" (exn-message e)))
  (~a line #:max-width 160 #:limit-marker "..."))

(define (series-values s)
  (for/list ([i (in-range (len s))]) (ref s i)))

(define (median-ms thunk #:runs [runs 5])
  (thunk)
  (define times
    (for/list ([_ (in-range runs)])
      (collect-garbage 'major)
      (define start (current-inexact-monotonic-milliseconds))
      (thunk)
      (- (current-inexact-monotonic-milliseconds) start)))
  (list-ref (sort times <) (quotient runs 2)))
