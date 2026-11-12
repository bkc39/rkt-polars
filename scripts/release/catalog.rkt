#lang racket/base

(require (only-in file/sha1 sha1)
         (only-in json read-json)
         (only-in racket/match match)
         (only-in racket/pretty pretty-write)
         (only-in setup/getinfo get-info/full))

(define (info-ref dir key)
  (define info
    (or (get-info/full dir) (raise-user-error 'catalog "~a has no info.rkt" dir)))
  (info key (lambda () (raise-user-error 'catalog "~a/info.rkt has no ~a" dir key))))

(define (entry name dir zip source)
  (hash 'name name
        'source source
        'checksum (call-with-input-file zip sha1)
        'version (info-ref dir 'version)
        'dependencies (info-ref dir 'deps)
        'description (info-ref dir 'pkg-desc)
        'author ""
        'tags '()
        'modules '()))

(define (manifest-field manifest key)
  (define value (hash-ref (call-with-input-file manifest read-json) key #f))
  (unless (string? value)
    (raise-user-error 'catalog "~a names no ~a" manifest key))
  value)

(module+ main
  (match (current-command-line-arguments)
    [(vector "entry" name dir zip source) (pretty-write (entry name dir zip source))]
    [(vector "manifest" manifest key) (displayln (manifest-field manifest (string->symbol key)))]
    [_
     (raise-user-error
      'catalog
      "usage: catalog.rkt entry NAME INFO-DIR ZIP SOURCE | manifest MANIFEST.json KEY")]))
