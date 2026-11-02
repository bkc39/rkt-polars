#lang racket/base

(module+ test
  (require rackunit
           (only-in file/sha1 bytes->hex-string)
           (only-in racket/file
                    delete-directory/files file->bytes make-directory* make-temporary-directory)
           (only-in racket/port port->bytes with-output-to-string)
           (only-in polars/private/install-compat pre-installer)
           (only-in polars/private/resource with-release)
           (only-in polars/tests/test-helpers scratch-file))

  (define (remove-install-root root)
    (define native (build-path root "collection" "native-libs"))
    (when (directory-exists? native)
      (file-or-directory-permissions native #o755))
    (delete-directory/files root))

  (define (call-with-install-dirs proc)
    (with-release ([root (make-temporary-directory) remove-install-root])
      (define lib (build-path root "src" "lib"))
      (define collection (build-path root "collection"))
      (make-directory* lib)
      (make-directory* collection)
      (proc lib collection (build-path collection "native-libs"))))

  (define (install! lib collection)
    (parameterize ([current-environment-variables
                    (environment-variables-copy (current-environment-variables))])
      (putenv "RKT_POLARS_COMPAT_LIB_PATH" (path->string (simplify-path (build-path lib 'up))))
      (pre-installer #f collection #f)))

  (define (staged dir)
    (for/list ([f (in-list (directory-list dir))]
               #:when (regexp-match? #rx"^\\.libcompat\\." (path->string f)))
      f))

  (define (fails-to? probe)
    (with-handlers ([exn:fail:filesystem? (lambda (_) #t)])
      (probe)
      #f))

  (test-case "an identical library is left alone"
    (call-with-install-dirs
     (lambda (lib collection native)
       (scratch-file lib "libcompat.so" "same bytes")
       (make-directory* native)
       (define target (scratch-file native "libcompat.so" "same bytes"))
       (file-or-directory-modify-seconds target 1000000000)
       (call-with-input-file* target
         (lambda (_)
           (define before (file-or-directory-identity target))
           (install! lib collection)
           (check-equal? (file-or-directory-identity target) before)
           (check-equal? (file-or-directory-modify-seconds target) 1000000000))))))

  (test-case "a differing library is renamed in, and a holder keeps the old one"
    (call-with-install-dirs
     (lambda (lib collection native)
       (scratch-file lib "libcompat.so" "new bytes, longer")
       (make-directory* native)
       (define target (scratch-file native "libcompat.so" "old bytes"))
       (call-with-input-file* target
         (lambda (old)
           (define before (file-or-directory-identity target))
           (install! lib collection)
           (check-equal? (file->bytes target) #"new bytes, longer")
           (check-not-equal? (file-or-directory-identity target) before)
           (check-equal? (port->bytes old) #"old bytes")
           (check-equal? (staged native) '()))))))

  (test-case "a failed copy leaves the target and no staging file"
    (call-with-install-dirs
     (lambda (lib collection native)
       (make-directory* (build-path lib "libcompat.so"))
       (make-directory* native)
       (define target (scratch-file native "libcompat.so" "old bytes"))
       (call-with-input-file* target
         (lambda (_)
           (define before (file-or-directory-identity target))
           (check-exn exn:fail? (lambda () (install! lib collection)))
           (check-equal? (file-or-directory-identity target) before)
           (check-equal? (file->bytes target) #"old bytes")
           (check-equal? (staged native) '()))))))

  (test-case "a written library is at mode 0755 whatever the source's"
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
       (check-equal? (file-or-directory-permissions target 'bits) #o755))))

  (test-case "each library is compared on its own"
    (call-with-install-dirs
     (lambda (lib collection native)
       (scratch-file lib "libcompat.so" "same bytes")
       (scratch-file lib "libcompat.dylib" "new dylib")
       (make-directory* native)
       (define so (scratch-file native "libcompat.so" "same bytes"))
       (define dylib (scratch-file native "libcompat.dylib" "old dylib"))
       (call-with-input-file* so
         (lambda (_)
           (call-with-input-file* dylib
             (lambda (_)
               (define so-before (file-or-directory-identity so))
               (define dylib-before (file-or-directory-identity dylib))
               (install! lib collection)
               (check-equal? (file-or-directory-identity so) so-before)
               (check-not-equal? (file-or-directory-identity dylib) dylib-before)
               (check-equal? (file->bytes dylib) #"new dylib"))))))))

  (test-case "a directory target is refused and kept"
    (call-with-install-dirs
     (lambda (lib collection native)
       (scratch-file lib "libcompat.so" "new bytes")
       (define target (build-path native "libcompat.so"))
       (make-directory* target)
       (scratch-file target "inside" "kept")
       (check-exn exn:fail? (lambda () (install! lib collection)))
       (check-true (directory-exists? target))
       (check-equal? (file->bytes (build-path target "inside")) #"kept")
       (check-equal? (staged native) '()))))

  (test-case "a read-only destination is refused before anything is staged"
    (call-with-install-dirs
     (lambda (lib collection native)
       (scratch-file lib "libcompat.so" "new bytes")
       (make-directory* native)
       (define target (scratch-file native "libcompat.so" "old bytes"))
       (file-or-directory-permissions native #o555)
       (when (fails-to? (lambda () (delete-file (scratch-file native "probe" ""))))
         (check-exn exn:fail:filesystem? (lambda () (install! lib collection)))
         (check-equal? (file->bytes target) #"old bytes")
         (check-equal? (staged native) '())))))

  (test-case "an unreadable target of the same size is replaced"
    (call-with-install-dirs
     (lambda (lib collection native)
       (scratch-file lib "libcompat.so" "same bytes")
       (make-directory* native)
       (define target (scratch-file native "libcompat.so" "same bytes"))
       (file-or-directory-permissions target #o000)
       (when (fails-to? (lambda () (call-with-input-file* target void)))
         (install! lib collection)
         (check-equal? (file->bytes target) #"same bytes")
         (check-equal? (file-or-directory-permissions target 'bits) #o755)
         (check-equal? (staged native) '())))))

  (test-case "a missing destination is created"
    (call-with-install-dirs
     (lambda (lib collection native)
       (scratch-file lib "libcompat.so" "fresh")
       (install! lib collection)
       (check-equal? (file->bytes (build-path native "libcompat.so")) #"fresh"))))

  (define (candidate-dir collection)
    (build-path collection "native-libs" "candidates"
                (if (eq? (system-type 'os) 'macosx) "darwin" "linux")))

  (define (install-candidate! collection #:force? [force? #f])
    (parameterize ([current-environment-variables
                    (environment-variables-copy (current-environment-variables))])
      (environment-variables-set! (current-environment-variables)
                                  #"RKT_POLARS_COMPAT_LIB_PATH" #f)
      (environment-variables-set! (current-environment-variables)
                                  #"RKT_POLARS_FORCE_CANDIDATE" (and force? #"1"))
      (with-output-to-string (lambda () (pre-installer #f collection #f)))))

  (define (sha256-hex bs)
    (bytes->hex-string (sha256-bytes bs)))

  (define (call-with-dev-library marked-bytes proc)
    (call-with-install-dirs
     (lambda (lib collection native)
       (make-directory* (candidate-dir collection))
       (scratch-file (candidate-dir collection) "libcompat.so" "candidate bytes")
       (define target (scratch-file native "libcompat.so" "dev bytes"))
       (define marker (build-path native ".libcompat.so.dev"))
       (when marked-bytes
         (scratch-file native ".libcompat.so.dev" (format "~a\n" (sha256-hex marked-bytes))))
       (proc collection target marker))))

  (test-case "a dev-marked library is kept, in one line naming it"
    (call-with-dev-library
     #"dev bytes"
     (lambda (collection target marker)
       (define before (file-or-directory-identity target))
       (define out (install-candidate! collection))
       (check-equal? (file->bytes target) #"dev bytes")
       (check-equal? (file-or-directory-identity target) before)
       (check-true (file-exists? marker))
       (check-equal? out
                     (format (string-append "pre-installer: keeping the dev-built ~a; "
                                            "RKT_POLARS_FORCE_CANDIDATE=1 installs the "
                                            "committed candidate\n")
                             (path->string target))))))

  (test-case "a stale marker is ignored and removed with the candidate's install"
    (call-with-dev-library
     #"other bytes"
     (lambda (collection target marker)
       (check-equal? (install-candidate! collection) "")
       (check-equal? (file->bytes target) #"candidate bytes")
       (check-false (file-exists? marker)))))

  (test-case "RKT_POLARS_FORCE_CANDIDATE=1 installs the candidate over a dev-marked library"
    (call-with-dev-library
     #"dev bytes"
     (lambda (collection target marker)
       (check-equal? (install-candidate! collection #:force? #t) "")
       (check-equal? (file->bytes target) #"candidate bytes")
       (check-false (file-exists? marker)))))

  (test-case "without a marker the candidate replaces the library"
    (call-with-dev-library
     #f
     (lambda (collection target marker)
       (check-equal? (install-candidate! collection) "")
       (check-equal? (file->bytes target) #"candidate bytes")
       (define before (file-or-directory-identity target))
       (check-equal? (install-candidate! collection) "")
       (check-equal? (file-or-directory-identity target) before)))))
