#lang racket/base

(module+ test
  (require rackunit
           (only-in racket/file display-to-file make-directory*)
           (only-in racket/list remove-duplicates)
           (only-in racket/match ==)
           (only-in setup/getinfo get-info/full)
           (only-in polars/private/native-location
                    current-native-platform dev-marker library-file locate-native-library
                    manifest-problem missing-export-message native-library-problem native-location
                    native-location-dir native-location-kind native-packages
                    required-native-version sha256-hex unloadable-message)
           (only-in polars/tests/test-helpers
                    contains-all? make-native-package! module-text polars-dir scratch-file
                    with-environment-variable with-native-collections))

  (define (staged-library! collects [contents "staged bytes"])
    (define staged (build-path collects "staged"))
    (make-directory* staged)
    (scratch-file staged library-file contents)
    staged)

  (define (mark-dev! staged)
    (define library (build-path staged library-file))
    (display-to-file (format "~a\n" (sha256-hex library)) (dev-marker library)))

  (define (locate staged)
    (with-environment-variable #"RKT_POLARS_COMPAT_LIB_PATH" #f
      (locate-native-library staged)))

  (define (libs root)
    (simplify-path (build-path root "native-libs")))

  (test-case "RKT_POLARS_COMPAT_LIB_PATH outranks a staged copy and the package"
    (with-native-collections collects
      (define staged (staged-library! collects))
      (make-native-package! collects)
      (with-environment-variable #"RKT_POLARS_COMPAT_LIB_PATH"
                                 (path->bytes (build-path collects "override"))
        (check-match (locate-native-library staged)
                     (native-location 'override
                                      (== (simplify-path (build-path collects "override" "lib")))
                                      _ _ _)))))

  (test-case "an empty RKT_POLARS_COMPAT_LIB_PATH is unset"
    (with-native-collections collects
      (define staged (staged-library! collects))
      (with-environment-variable #"RKT_POLARS_COMPAT_LIB_PATH" #""
        (check-equal? (native-location-kind (locate-native-library staged)) 'staged))))

  (test-case "a staged copy is loaded when no native package is installed"
    (with-native-collections collects
      (define staged (staged-library! collects))
      (check-match (locate staged) (native-location 'staged (== (simplify-path staged)) _ _ _))))

  (test-case "the native package outranks a staged copy without a dev marker"
    (with-native-collections collects
      (define staged (staged-library! collects))
      (define root (make-native-package! collects))
      (check-match (locate staged) (native-location 'package (== (libs root)) _ _ _))))

  (test-case "a dev-built staged copy outranks the native package"
    (with-native-collections collects
      (define staged (staged-library! collects))
      (mark-dev! staged)
      (make-native-package! collects)
      (check-equal? (native-location-kind (locate staged)) 'staged)))

  (test-case "a stale dev marker does not keep the staged copy over the package"
    (with-native-collections collects
      (define staged (staged-library! collects))
      (mark-dev! staged)
      (scratch-file staged library-file "rebuilt bytes")
      (make-native-package! collects)
      (check-equal? (native-location-kind (locate staged)) 'package)))

  (test-case "a native package that holds no library does not shadow a staged copy"
    (with-native-collections collects
      (define staged (staged-library! collects))
      (make-native-package! collects #:library #f #:manifest? #f)
      (check-equal? (native-location-kind (locate staged)) 'staged)))

  (test-case "with nothing staged the native package is loaded and checked"
    (with-native-collections collects
      (define root (make-native-package! collects))
      (define location (locate (build-path collects "staged")))
      (check-match location (native-location 'package (== (libs root)) _ _ _))
      (check-false (native-library-problem location "0.3"))))

  (test-case "the native version is checked exactly"
    (with-native-collections collects
      (define root (make-native-package! collects #:version "0.3.1"))
      (check-equal?
       (native-library-problem (locate (build-path collects "staged")) "0.3")
       (format (string-append "the package polars-x86_64-linux is version 0.3.1, but this polars "
                              "needs version 0.3\n  found in: ~a\n  update both with "
                              "`raco pkg update polars polars-x86_64-linux`")
               (simplify-path (path->directory-path root))))))

  (test-case "a missing native package names the package to install"
    (with-native-collections collects
      (define staged (build-path collects "staged"))
      (define location (locate staged))
      (check-equal? (native-location-kind location) 'missing)
      (check-equal?
       (native-library-problem location "0.3")
       (format (string-append "libcompat is not installed: the package polars-x86_64-linux is "
                              "missing\n  looked in: ~a\n  install it with `raco pkg install "
                              "polars-x86_64-linux`; to use a libcompat built by hand, set "
                              "RKT_POLARS_COMPAT_LIB_PATH to the directory whose lib/ holds it")
               (simplify-path staged)))))

  (test-case "on pkg-build's natipkg platform the Linux package is the one to install"
    (with-native-collections collects
      (parameterize ([current-native-platform "x86_64-linux-natipkg"])
        (check-true (contains-all? (native-library-problem (locate collects) "0.3")
                                   '("`raco pkg install polars-x86_64-linux`"))))))

  (test-case "an unsupported platform names the supported ones and the override"
    (with-native-collections collects
      (make-native-package! collects)
      (parameterize ([current-native-platform "riscv64-linux"])
        (define location (locate (build-path collects "staged")))
        (check-equal? (native-location-kind location) 'missing)
        (check-equal?
         (native-library-problem location "0.3")
         (format (string-append "libcompat is not installed: polars ships it for x86_64-linux "
                                "and aarch64-macosx, not riscv64-linux\n  looked in: ~a\n  to "
                                "use a libcompat built by hand, set RKT_POLARS_COMPAT_LIB_PATH "
                                "to the directory whose lib/ holds it")
                 (simplify-path (build-path collects "staged")))))))

  (test-case "the macOS package is looked up on aarch64-macosx"
    (with-native-collections collects
      (define root (make-native-package! collects #:package "polars-aarch64-macosx"))
      (parameterize ([current-native-platform "aarch64-macosx"])
        (check-match (locate (build-path collects "staged"))
                     (native-location 'package (== (libs root)) _ _ _)))))

  (test-case "an override whose lib/ holds no library is reported"
    (with-native-collections collects
      (with-environment-variable #"RKT_POLARS_COMPAT_LIB_PATH" (path->bytes collects)
        (check-true
         (contains-all? (native-library-problem (locate-native-library collects) "0.3")
                        (list "libcompat is not where RKT_POLARS_COMPAT_LIB_PATH points"
                              (path->string (simplify-path (build-path collects "lib")))))))))

  (test-case "a native package whose main.rkt fails is reported with its reason"
    (with-native-collections collects
      (make-native-package! collects
                            #:main (module-text '(provide native-libs-dir)
                                                '(define native-libs-dir
                                                   (error "broken on purpose"))))
      (define location (locate (staged-library! collects)))
      (check-equal? (native-location-kind location) 'broken)
      (check-true (contains-all? (native-library-problem location "0.3")
                                 '("the package polars-x86_64-linux is installed but would not load"
                                   "broken on purpose"
                                   "`raco pkg remove --force polars-x86_64-linux`")))))

  (test-case "an unloadable library passes on the loader's reason"
    (with-native-collections collects
      (define location (locate (staged-library! collects)))
      (check-true (contains-all? (unloadable-message location "invalid ELF header")
                                 '("libcompat was found but would not load"
                                   "the loader said: invalid ELF header"
                                   "`nix run .#copy-native-libs`")))))

  (test-case "a missing export names the Racket binding and how to update"
    (with-native-collections collects
      (make-native-package! collects)
      (check-true
       (contains-all? (missing-export-message (locate collects) 'series-new-i32/raw)
                      '("libcompat lacks the export for series-new-i32/raw, so it is older"
                        "`raco pkg update polars polars-x86_64-linux`")))))

  (test-case "a manifest that lists the library's sha256 passes"
    (with-native-collections collects
      (make-native-package! collects)
      (check-false (manifest-problem (locate collects) "0.3"))))

  (test-case "a library whose sha256 the manifest does not give is refused"
    (with-native-collections collects
      (define root (make-native-package! collects))
      (scratch-file (build-path root "native-libs") library-file "tampered bytes")
      (check-true (contains-all? (manifest-problem (locate collects) "0.3")
                                 (list (format "~a in the package polars-x86_64-linux has sha256 ~a"
                                               library-file
                                               (sha256-hex (build-path root "native-libs"
                                                                       library-file)))
                                       "but its manifest.json says")))))

  (test-case "a library the manifest does not list is refused"
    (with-native-collections collects
      (define root
        (make-native-package! collects
                              #:manifest-text "{\"native_version\":\"0.3\",\"files\":{}}"))
      (check-true (contains-all? (manifest-problem (locate collects) "0.3")
                                 (list (format "~a in the package" library-file)
                                       "but its manifest.json does not list it")))))

  (test-case "a listed file that is missing is refused"
    (with-native-collections collects
      (make-native-package!
       collects
       #:library #f
       #:manifest-text "{\"native_version\":\"0.3\",\"files\":{\"libcompat.so\":\"00\"}}")
      (check-true (contains-all? (manifest-problem (locate collects) "0.3")
                                 '("libcompat.so in the package polars-x86_64-linux is missing")))))

  (test-case "a manifest for another native version is refused"
    (with-native-collections collects
      (make-native-package! collects #:manifest-text "{\"native_version\":\"0.2\",\"files\":{}}")
      (check-true (contains-all? (manifest-problem (locate collects) "0.3")
                                 '("manifest.json is for native version 0.2"
                                   "this polars needs version 0.3")))))

  (test-case "a missing, malformed or misshapen manifest is refused"
    (with-native-collections collects
      (define root (make-native-package! collects #:manifest? #f))
      (check-true (contains-all? (manifest-problem (locate collects) "0.3")
                                 '("the package polars-x86_64-linux has no manifest.json")))
      (scratch-file root "manifest.json" "{\"native_version\":")
      (check-true (contains-all? (manifest-problem (locate collects) "0.3")
                                 '("manifest.json is not JSON")))
      (scratch-file root "manifest.json" "[1, 2]")
      (check-true (contains-all? (manifest-problem (locate collects) "0.3")
                                 '("manifest.json names no native_version and files")))))

  (define wanted (required-native-version polars-dir))
  (define native-package-names (remove-duplicates (map cdr native-packages)))
  (define repo (simplify-path (build-path polars-dir 'up)))
  (define skeletons (build-path repo "native"))

  (test-case "polars depends on each native package at its native version"
    (check-equal? wanted "0.3")
    (check-equal?
     (for/list ([dep (in-list ((get-info/full polars-dir) 'deps))] #:when (pair? dep)) dep)
     (for/list ([entry (in-list native-packages)])
       (list (cdr entry) '#:platform (car entry) '#:version wanted)))
    (check-equal? native-package-names '("polars-x86_64-linux" "polars-aarch64-macosx")))

  (test-case "in a checkout, each native package's skeleton is at polars' native version"
    (when (directory-exists? skeletons)
      (check-equal? (sort (map path->string (directory-list skeletons)) string<?)
                    (sort native-package-names string<?))
      (for ([package (in-list native-package-names)])
        (check-equal? ((get-info/full (build-path skeletons package)) 'version) wanted package))))

  (test-case "in a checkout, no skeleton is a collection, so none passes for an installed package"
    (when (directory-exists? skeletons)
      (for ([package (in-list native-package-names)])
        (check-false (directory-exists? (build-path repo package)) package))))

  (test-case "a libcompat.* in the package that is not a regular file is refused"
    (with-native-collections collects
      (define root (make-native-package! collects))
      (make-directory* (build-path root "native-libs" "libcompat.d"))
      (check-true
       (contains-all? (manifest-problem (locate collects) "0.3")
                      '("libcompat.d in the package polars-x86_64-linux is not a regular file"
                        "`raco pkg remove --force polars-x86_64-linux`"))))))
