#lang racket/base

(require (only-in file/sha1 sha1)
         (only-in json read-json)
         (only-in racket/match match)
         (only-in racket/pretty pretty-write)
         (only-in pkg/lib installed-pkg-names)
         (only-in setup/getinfo get-info/full))

(provide info-ref
         read-manifest)

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

(define (local-entry rktd source)
  (define shipped (call-with-input-file rktd read))
  (unless (and (hash? shipped) (hash-has-key? shipped 'source))
    (raise-user-error 'catalog "~a is not a catalog entry" rktd))
  (hash-set shipped 'source source))

(define (missing-deps dir)
  (define installed
    (append (installed-pkg-names #:scope 'installation) (installed-pkg-names #:scope 'user)))
  (for*/list ([dep (in-list (info-ref dir 'deps))]
              #:unless (and (pair? dep) (memq '#:platform dep))
              [name (in-value (if (pair? dep) (car dep) dep))]
              #:unless (member name installed))
    name))

(define (read-manifest manifest)
  (call-with-input-file manifest read-json))

(define (manifest-field manifest key)
  (define value (hash-ref (read-manifest manifest) key #f))
  (unless (string? value)
    (raise-user-error 'catalog "~a names no ~a" manifest key))
  value)

(module+ main
  (match (current-command-line-arguments)
    [(vector "entry" name dir zip source) (pretty-write (entry name dir zip source))]
    [(vector "local-entry" rktd source) (pretty-write (local-entry rktd source))]
    [(vector "manifest" manifest keys ..1)
     (for ([key (in-list keys)])
       (displayln (manifest-field manifest (string->symbol key))))]
    [(vector "info" dir keys ..1)
     (for ([key (in-list keys)])
       (displayln (info-ref dir (string->symbol key))))]
    [(vector "missing-deps" dir) (for-each displayln (missing-deps dir))]
    [_
     (raise-user-error
      'catalog
      (string-append "usage: catalog.rkt entry NAME INFO-DIR ZIP SOURCE"
                     " | local-entry ENTRY.rktd SOURCE"
                     " | manifest MANIFEST.json KEY..."
                     " | info INFO-DIR KEY..."
                     " | missing-deps INFO-DIR"))]))
