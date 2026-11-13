#lang racket/base

(require (only-in racket/match match))

(define (add-entry! catalog name zip)
  (define checksum (call-with-input-file (string-append zip ".CHECKSUM") read-line))
  (with-output-to-file (build-path catalog "pkg" name)
    #:exists 'replace
    (lambda ()
      (write (hash 'name name
                   'source (string-append "file://" zip)
                   'checksum checksum
                   'author ""
                   'description ""
                   'tags '()
                   'dependencies '()
                   'modules '())))))

(module+ main
  (match (current-command-line-arguments)
    [(vector catalog name zip) (add-entry! catalog name zip)]
    [_ (eprintf "usage: racket scripts/add-catalog-entry.rkt CATALOG-DIR NAME ZIP\n")
       (exit 1)]))
