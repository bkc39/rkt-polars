#lang racket/base

(module+ test
  (require rackunit
           (only-in file/sha1 bytes->hex-string)
           (only-in racket/file
                    delete-directory/files file->bytes make-directory* make-temporary-directory)
           (only-in racket/port port->bytes with-output-to-string)
           (only-in polars/private/install-compat pre-installer)
           (only-in polars/private/native-location library-file)
           (only-in polars/private/resource with-release)
           (only-in polars/tests/test-helpers
                    contains-all? make-native-package! message-of scratch-file
                    with-environment-variable with-native-collections))

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
      (with-native-collections _
        (pre-installer #f collection #f))))

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
      (with-native-collections _
        (with-output-to-string (lambda () (pre-installer #f collection #f))))))

  (define (sha256-hex bs)
    (bytes->hex-string (sha256-bytes bs)))

  (define (marker-for bs)
    (format "~a\n" (sha256-hex bs)))

  (define (call-with-dev-library marker-contents proc #:library [library "dev bytes"])
    (call-with-install-dirs
     (lambda (lib collection native)
       (make-directory* (candidate-dir collection))
       (scratch-file (candidate-dir collection) "libcompat.so" "candidate bytes")
       (make-directory* native)
       (define target (build-path native "libcompat.so"))
       (when library
         (scratch-file native "libcompat.so" library))
       (define marker (build-path native ".libcompat.so.dev"))
       (when marker-contents
         (scratch-file native ".libcompat.so.dev" marker-contents))
       (proc collection target marker))))

  (test-case "a dev-marked library is kept, in one line naming it"
    (call-with-dev-library
     (marker-for #"dev bytes")
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
     (marker-for #"other bytes")
     (lambda (collection target marker)
       (check-equal? (install-candidate! collection) "")
       (check-equal? (file->bytes target) #"candidate bytes")
       (check-false (file-exists? marker)))))

  (test-case "RKT_POLARS_FORCE_CANDIDATE=1 installs the candidate over a dev-marked library"
    (call-with-dev-library
     (marker-for #"dev bytes")
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
       (check-equal? (file-or-directory-identity target) before))))

  (test-case "a marker not in the format, 64 lowercase hex digits and a newline, is stale"
    (define hex (sha256-hex #"dev bytes"))
    (for ([contents (list hex
                          (string-upcase (marker-for #"dev bytes"))
                          (format "~a\r\n" hex)
                          (format "~a\n\n" hex)
                          (format " ~a\n" hex))])
      (call-with-dev-library
       contents
       (lambda (collection target marker)
         (check-equal? (install-candidate! collection) "" contents)
         (check-equal? (file->bytes target) #"candidate bytes" contents)
         (check-false (file-exists? marker) contents)))))

  (test-case "an unreadable marker is ignored and the candidate installed"
    (call-with-dev-library
     (marker-for #"dev bytes")
     (lambda (collection target marker)
       (file-or-directory-permissions marker #o000)
       (when (fails-to? (lambda () (call-with-input-file* marker void)))
         (check-equal? (install-candidate! collection) "")
         (check-equal? (file->bytes target) #"candidate bytes")))))

  (test-case "a marker without its library is removed and the candidate installed"
    (call-with-dev-library
     (marker-for #"dev bytes")
     #:library #f
     (lambda (collection target marker)
       (check-equal? (install-candidate! collection) "")
       (check-equal? (file->bytes target) #"candidate bytes")
       (check-false (file-exists? marker)))))

  (test-case "a stale marker a read-only directory keeps does not fail the install"
    (call-with-dev-library
     (marker-for #"other bytes")
     #:library "candidate bytes"
     (lambda (collection target marker)
       (define native (build-path collection "native-libs"))
       (file-or-directory-permissions native #o555)
       (when (fails-to? (lambda () (delete-file (scratch-file native "probe" ""))))
         (check-equal? (install-candidate! collection) "")
         (check-equal? (file->bytes target) #"candidate bytes")
         (check-true (file-exists? marker))))))

  (test-case "a directory named like the marker is left alone"
    (call-with-dev-library
     #f
     (lambda (collection target marker)
       (make-directory* marker)
       (scratch-file marker "inside" "kept")
       (check-equal? (install-candidate! collection) "")
       (check-equal? (file->bytes target) #"candidate bytes")
       (check-equal? (file->bytes (build-path marker "inside")) #"kept"))))

  (define (call-with-package-install proc #:library [library "dev bytes"] #:marked? [marked? #f])
    (with-native-collections collects
      (define collection (build-path collects "fake-polars"))
      (define native (build-path collection "native-libs"))
      (make-directory* (candidate-dir collection))
      (scratch-file (candidate-dir collection) "libcompat.so" "candidate bytes")
      (scratch-file collection "info.rkt" "#lang info\n(define native-version \"0.3\")\n")
      (when library
        (scratch-file native library-file library))
      (when marked?
        (scratch-file native (format ".~a.dev" library-file) (marker-for (string->bytes/utf-8 library))))
      (proc collects collection native)))

  (define (pre-install collection)
    (with-environment-variable #"RKT_POLARS_COMPAT_LIB_PATH" #f
      (with-environment-variable #"RKT_POLARS_FORCE_CANDIDATE" #f
        (with-output-to-string (lambda () (pre-installer #f collection #f))))))

  (define (tamper! root)
    (scratch-file (build-path root "native-libs") library-file "tampered bytes"))

  (test-case "the native package is checked and no candidate is staged over it"
    (call-with-package-install
     #:library #f
     (lambda (collects collection native)
       (make-native-package! collects)
       (check-equal? (pre-install collection) "")
       (check-false (file-exists? (build-path native library-file))))))

  (test-case "a native package whose library its manifest does not list fails the install"
    (call-with-package-install
     #:library #f
     (lambda (collects collection native)
       (tamper! (make-native-package! collects))
       (check-true (contains-all? (message-of (lambda () (pre-install collection)))
                                  (list "pre-installer: "
                                        (format "~a in the package polars-x86_64-linux has sha256"
                                                library-file)))))))

  (test-case "a native package of another version fails the install"
    (call-with-package-install
     #:library #f
     (lambda (collects collection native)
       (make-native-package! collects #:version "0.2")
       (check-true (contains-all? (message-of (lambda () (pre-install collection)))
                                  '("the package polars-x86_64-linux is version 0.2"
                                    "`raco pkg update polars polars-x86_64-linux`"))))))

  (test-case "a staged copy without a dev marker does not skip the package's check"
    (call-with-package-install
     (lambda (collects collection native)
       (tamper! (make-native-package! collects))
       (check-true (contains-all? (message-of (lambda () (pre-install collection)))
                                  '("has sha256"))))))

  (test-case "a dev-built staged copy is kept over the package, unchecked"
    (call-with-package-install
     #:marked? #t
     (lambda (collects collection native)
       (tamper! (make-native-package! collects))
       (check-equal? (pre-install collection)
                     (format "pre-installer: keeping the dev-built ~a over the package ~a\n"
                             (build-path native library-file)
                             "polars-x86_64-linux")))))

  (test-case "RKT_POLARS_COMPAT_LIB_PATH skips the package's check"
    (call-with-package-install
     #:library #f
     (lambda (collects collection native)
       (tamper! (make-native-package! collects))
       (define lib (build-path collects "override" "lib"))
       (make-directory* lib)
       (scratch-file lib library-file "override bytes")
       (with-environment-variable #"RKT_POLARS_COMPAT_LIB_PATH"
                                  (path->bytes (build-path collects "override"))
         (pre-installer #f collection #f))
       (check-equal? (file->bytes (build-path native library-file)) #"override bytes"))))

  (test-case "an empty RKT_POLARS_COMPAT_LIB_PATH is unset, so the package is checked"
    (call-with-package-install
     #:library #f
     (lambda (collects collection native)
       (tamper! (make-native-package! collects))
       (check-true
        (contains-all? (message-of (lambda ()
                                     (with-environment-variable #"RKT_POLARS_COMPAT_LIB_PATH" #""
                                       (pre-installer #f collection #f))))
                       '("has sha256"))))))

  (test-case "with no library anywhere the install warns, naming the package to install"
    (with-native-collections collects
      (define collection (build-path collects "fake-polars"))
      (make-directory* collection)
      (define err (open-output-string))
      (parameterize ([current-error-port err])
        (pre-install collection))
      (check-true (contains-all? (get-output-string err)
                                 '("pre-installer: libcompat is not installed"
                                   "`raco pkg install polars-x86_64-linux`"))))))
