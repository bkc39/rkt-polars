#lang racket/base

(module+ test
  (require rackunit
           (only-in file/sha1 bytes->hex-string)
           (only-in racket/dict in-dict)
           (only-in racket/file
                    delete-directory/files file->bytes make-directory* make-temporary-directory)
           (only-in racket/port port->bytes with-output-to-string)
           (only-in polars/private/install-compat pre-installer)
           syntax/parse/define
           (for-syntax racket/base)
           (only-in polars/private/native-location
                    current-native-platform library-file native-packages)
           (only-in polars/private/resource with-release)
           (only-in polars/tests/test-helpers
                    contains-all? make-native-package! message-of module-text scratch-file
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

  (define (sha256-hex bs)
    (bytes->hex-string (sha256-bytes bs)))

  (define (marker-for bs)
    (format "~a\n" (sha256-hex bs)))

  (define (call-with-package-install proc #:staged [staged #f] #:marker [marker #f])
    (with-native-collections collects
      (define collection (build-path collects "fake-polars"))
      (define native (build-path collection "native-libs"))
      (make-directory* native)
      (scratch-file collection "info.rkt"
                    (module-text #:lang "info" '(define native-version "0.3")))
      (when staged
        (scratch-file native library-file staged))
      (when marker
        (scratch-file native (format ".~a.dev" library-file) marker))
      (proc collects collection native)))

  (define-syntax-parser with-package-install
    [(_ (collects:id collection:id native:id)
        (~alt (~optional (~seq #:staged staged:expr))
              (~optional (~seq #:marker marker:expr)))
        ...
        body:expr ...+)
     (syntax/loc this-syntax
       (call-with-package-install (lambda (collects collection native) body ...)
                                  (~? (~@ #:staged staged))
                                  (~? (~@ #:marker marker))))])

  (define (pre-install collection)
    (with-environment-variable #"RKT_POLARS_COMPAT_LIB_PATH" #f
      (with-output-to-string (lambda () (pre-installer #f collection #f)))))

  (define (pre-install-error collection)
    (message-of (lambda () (pre-install collection))))

  (define (pre-install-outputs collection)
    (define err (open-output-string))
    (define out (parameterize ([current-error-port err]) (pre-install collection)))
    (values out (get-output-string err)))

  (define (pre-install-warning collection)
    (define-values (_ err) (pre-install-outputs collection))
    err)

  (define (tampered-package! collects)
    (define root (make-native-package! collects))
    (scratch-file (build-path root "native-libs") library-file "tampered bytes")
    root)

  (define (staged-bytes native)
    (define library (build-path native library-file))
    (and (file-exists? library) (file->bytes library)))

  (test-case "the native package is checked and nothing is staged"
    (with-package-install (collects collection native)
      (make-native-package! collects)
      (define-values (out err) (pre-install-outputs collection))
      (check-equal? (list out err) '("" ""))
      (check-false (staged-bytes native))))

  (test-case "a native package whose library its manifest does not list fails the install"
    (with-package-install (collects collection native)
      (tampered-package! collects)
      (check-true (contains-all? (pre-install-error collection)
                                 (list "pre-installer: "
                                       (format "~a in the package polars-x86_64-linux has sha256"
                                               library-file))))))

  (test-case "a native package holding no library fails the install, naming the remedy"
    (with-package-install (collects collection native)
      (make-native-package! collects #:library #f)
      (check-true (contains-all? (pre-install-error collection)
                                 '("pre-installer: "
                                   "the package polars-x86_64-linux holds no libcompat"
                                   "`raco pkg remove --force polars-x86_64-linux`")))
      (check-false (staged-bytes native))))

  (test-case "a native package of another version fails the install"
    (with-package-install (collects collection native)
      (make-native-package! collects #:version "0.2")
      (check-true (contains-all? (pre-install-error collection)
                                 '("the package polars-x86_64-linux is version 0.2"
                                   "`raco pkg update polars polars-x86_64-linux`")))))

  (test-case "a native package whose info.rkt does not read fails the install, naming the remedy"
    (with-package-install (collects collection native)
      (make-native-package! collects #:info-text "#lang info\n(define version \"0.3\"")
      (check-true (contains-all? (pre-install-error collection)
                                 '("pre-installer: "
                                   "the package polars-x86_64-linux is installed but would not load"
                                   "`raco pkg remove --force polars-x86_64-linux`")))))

  (test-case "a staged copy without a dev marker does not skip the package's check"
    (with-package-install (collects collection native) #:staged "dev bytes"
      (tampered-package! collects)
      (check-true (contains-all? (pre-install-error collection) '("has sha256")))))

  (test-case "a dev-built staged copy is kept over the package, unchecked"
    (with-package-install (collects collection native)
      #:staged "dev bytes"
      #:marker (marker-for #"dev bytes")
      (tampered-package! collects)
      (define marker (build-path native (format ".~a.dev" library-file)))
      (check-equal? (pre-install collection)
                    (format "pre-installer: keeping the dev-built ~a over the package ~a\n"
                            (build-path native library-file)
                            "polars-x86_64-linux"))
      (check-equal? (staged-bytes native) #"dev bytes")
      (check-true (file-exists? marker))))

  (test-case "a marker not in the format, 64 lowercase hex digits and a newline, is stale"
    (define hex (sha256-hex #"dev bytes"))
    (for ([contents (list hex
                          (string-upcase (marker-for #"dev bytes"))
                          (format "~a\r\n" hex)
                          (format "~a\n\n" hex)
                          (format " ~a\n" hex)
                          (marker-for #"other bytes"))])
      (with-package-install (collects collection native) #:staged "dev bytes" #:marker contents
        (tampered-package! collects)
        (check-true (contains-all? (pre-install-error collection) '("has sha256")) contents))))

  (test-case "an unreadable marker is stale"
    (with-package-install (collects collection native)
      #:staged "dev bytes"
      #:marker (marker-for #"dev bytes")
      (tampered-package! collects)
      (define marker (build-path native (format ".~a.dev" library-file)))
      (file-or-directory-permissions marker #o000)
      (when (fails-to? (lambda () (call-with-input-file* marker void)))
        (check-true (contains-all? (pre-install-error collection) '("has sha256"))))))

  (test-case "a directory named like the marker is stale and left alone"
    (with-package-install (collects collection native) #:staged "dev bytes"
      (tampered-package! collects)
      (define marker (build-path native (format ".~a.dev" library-file)))
      (make-directory* marker)
      (scratch-file marker "inside" "kept")
      (check-true (contains-all? (pre-install-error collection) '("has sha256")))
      (check-equal? (file->bytes (build-path marker "inside")) #"kept")))

  (test-case "without a package, a staged copy, dev-built or not, is left alone in silence"
    (for ([marker (in-list (list #f (marker-for #"dev bytes")))])
      (with-package-install (collects collection native) #:staged "dev bytes" #:marker marker
        (define target (build-path native library-file))
        (define before (file-or-directory-identity target))
        (define-values (out err) (pre-install-outputs collection))
        (check-equal? (list out err) '("" "") (format "marker: ~a" marker))
        (check-equal? (file-or-directory-identity target) before)
        (check-equal? (staged-bytes native) #"dev bytes"))))

  (test-case "RKT_POLARS_COMPAT_LIB_PATH skips the package's check"
    (with-package-install (collects collection native)
      (tampered-package! collects)
      (define lib (build-path collects "override" "lib"))
      (make-directory* lib)
      (scratch-file lib library-file "override bytes")
      (with-environment-variable #"RKT_POLARS_COMPAT_LIB_PATH"
                                 (path->bytes (build-path collects "override"))
        (pre-installer #f collection #f))
      (check-equal? (staged-bytes native) #"override bytes")))

  (test-case "an empty RKT_POLARS_COMPAT_LIB_PATH is unset, so the package is checked"
    (with-package-install (collects collection native)
      (tampered-package! collects)
      (check-true
       (contains-all? (message-of (lambda ()
                                    (with-environment-variable #"RKT_POLARS_COMPAT_LIB_PATH" #""
                                      (pre-installer #f collection #f))))
                      '("has sha256")))))

  (test-case "with no library anywhere the install warns, naming the package to install"
    (with-native-collections collects
      (define collection (build-path collects "fake-polars"))
      (make-directory* collection)
      (check-true (contains-all? (pre-install-warning collection)
                                 '("pre-installer: libcompat is not installed"
                                   "`raco pkg install polars-x86_64-linux`")))))

  (test-case "another platform's library in native-libs is not this platform's"
    (with-package-install (collects collection native)
      (define stray (if (equal? library-file "libcompat.so") "libcompat.dylib" "libcompat.so"))
      (scratch-file native stray "stray bytes")
      (check-true (contains-all? (pre-install-warning collection)
                                 '("pre-installer: libcompat is not installed"
                                   "`raco pkg install polars-x86_64-linux`")))))

  (test-case "each supported platform without its package is told which one to install"
    (for ([(platform package) (in-dict native-packages)])
      (with-package-install (collects collection native)
        (parameterize ([current-native-platform platform])
          (define-values (out err) (pre-install-outputs collection))
          (check-equal? out "" platform)
          (check-true (contains-all? err
                                     (list (format "the package ~a is missing" package)
                                           (format "`raco pkg install ~a`" package)))
                      platform))
        (check-false (staged-bytes native) platform))))

  (test-case "another platform does not fail the install and is told which platforms polars supports"
    (for ([platform (in-list '("riscv64-linux" "x86_64-macosx" "x86_64-freebsd"))])
      (with-package-install (collects collection native)
        (parameterize ([current-native-platform platform])
          (check-true
           (contains-all? (pre-install-warning collection)
                          (list "pre-installer: libcompat is not installed: polars ships it for "
                                (format "x86_64-linux, aarch64-linux and aarch64-macosx, not ~a"
                                        platform)))
           platform))
        (check-false (staged-bytes native) platform)))))
