#lang racket/base

(module+ test
  (require rackunit
           (for-syntax racket/base)
           (only-in racket/file
                    delete-directory/files file->bytes make-directory* make-temporary-directory)
           (only-in racket/port port->bytes)
           (only-in racket/runtime-path define-runtime-path)
           (only-in polars/tests/test-helpers scratch-file))

  (define-runtime-path install-compat "../private/install-compat.rkt")
  (define pre-installer (dynamic-require install-compat 'pre-installer))

  (define (call-with-install-dirs proc)
    (define root (make-temporary-directory))
    (dynamic-wind
     void
     (lambda ()
       (define lib (build-path root "src" "lib"))
       (define collection (build-path root "collection"))
       (make-directory* lib)
       (make-directory* collection)
       (proc lib collection (build-path collection "native-libs")))
     (lambda ()
       (define native (build-path root "collection" "native-libs"))
       (when (directory-exists? native)
         (file-or-directory-permissions native #o755))
       (delete-directory/files root))))

  (define (install! lib collection)
    (parameterize ([current-environment-variables
                    (environment-variables-copy (current-environment-variables))])
      (putenv "RKT_POLARS_COMPAT_LIB_PATH" (path->string (simplify-path (build-path lib 'up))))
      (pre-installer #f collection #f)))

  (define (staged dir)
    (for/list ([f (in-list (directory-list dir))]
               #:when (regexp-match? #rx"^\\.libcompat\\." (path->string f)))
      f))

  (define (call-holding path proc)
    (define in (open-input-file path))
    (dynamic-wind void (lambda () (proc in)) (lambda () (close-input-port in))))

  (call-with-install-dirs
   (lambda (lib collection native)
     (scratch-file lib "libcompat.so" "same bytes")
     (make-directory* native)
     (define target (scratch-file native "libcompat.so" "same bytes"))
     (file-or-directory-modify-seconds target 1000000000)
     (call-holding target
                   (lambda (_)
                     (define before (file-or-directory-identity target))
                     (install! lib collection)
                     (check-equal? (file-or-directory-identity target) before)
                     (check-equal? (file-or-directory-modify-seconds target) 1000000000)))))

  (call-with-install-dirs
   (lambda (lib collection native)
     (scratch-file lib "libcompat.so" "new bytes, longer")
     (make-directory* native)
     (define target (scratch-file native "libcompat.so" "old bytes"))
     (call-holding target
                   (lambda (old)
                     (define before (file-or-directory-identity target))
                     (install! lib collection)
                     (check-equal? (file->bytes target) #"new bytes, longer")
                     (check-not-equal? (file-or-directory-identity target) before)
                     (check-equal? (port->bytes old) #"old bytes")
                     (check-equal? (staged native) '())))))

  (call-with-install-dirs
   (lambda (lib collection native)
     (make-directory* (build-path lib "libcompat.so"))
     (make-directory* native)
     (define target (scratch-file native "libcompat.so" "old bytes"))
     (call-holding target
                   (lambda (_)
                     (define before (file-or-directory-identity target))
                     (check-exn exn:fail? (lambda () (install! lib collection)))
                     (check-equal? (file-or-directory-identity target) before)
                     (check-equal? (file->bytes target) #"old bytes")
                     (check-equal? (staged native) '())))))

  (call-with-install-dirs
   (lambda (lib collection native)
     (define source (scratch-file lib "libcompat.so" "first"))
     (file-or-directory-permissions source #o555)
     (define target (build-path native "libcompat.so"))
     (install! lib collection)
     (check-equal? (file-or-directory-permissions target 'bits) #o755)
     (scratch-file lib "libcompat.so" "second")
     (file-or-directory-permissions source #o555)
     (install! lib collection)
     (check-equal? (file->bytes target) #"second")
     (check-equal? (file-or-directory-permissions target 'bits) #o755)))

  (call-with-install-dirs
   (lambda (lib collection native)
     (scratch-file lib "libcompat.so" "same bytes")
     (scratch-file lib "libcompat.dylib" "new dylib")
     (make-directory* native)
     (define so (scratch-file native "libcompat.so" "same bytes"))
     (define dylib (scratch-file native "libcompat.dylib" "old dylib"))
     (call-holding so
                   (lambda (_)
                     (call-holding dylib
                                   (lambda (_)
                                     (define so-before (file-or-directory-identity so))
                                     (define dylib-before (file-or-directory-identity dylib))
                                     (install! lib collection)
                                     (check-equal? (file-or-directory-identity so) so-before)
                                     (check-not-equal? (file-or-directory-identity dylib) dylib-before)
                                     (check-equal? (file->bytes dylib) #"new dylib")))))))

  (call-with-install-dirs
   (lambda (lib collection native)
     (scratch-file lib "libcompat.so" "new bytes")
     (define target (build-path native "libcompat.so"))
     (make-directory* target)
     (scratch-file target "inside" "kept")
     (check-exn exn:fail? (lambda () (install! lib collection)))
     (check-true (directory-exists? target))
     (check-equal? (file->bytes (build-path target "inside")) #"kept")
     (check-equal? (staged native) '())))

  (call-with-install-dirs
   (lambda (lib collection native)
     (scratch-file lib "libcompat.so" "new bytes")
     (make-directory* native)
     (define target (scratch-file native "libcompat.so" "old bytes"))
     (file-or-directory-permissions native #o555)
     (define writable?
       (with-handlers ([exn:fail:filesystem? (lambda (_) #f)])
         (delete-file (scratch-file native "probe" ""))
         #t))
     (unless writable?
       (check-exn exn:fail:filesystem? (lambda () (install! lib collection)))
       (check-equal? (file->bytes target) #"old bytes")
       (check-equal? (staged native) '()))))

  (call-with-install-dirs
   (lambda (lib collection native)
     (scratch-file lib "libcompat.so" "fresh")
     (install! lib collection)
     (check-equal? (file->bytes (build-path native "libcompat.so")) #"fresh"))))
