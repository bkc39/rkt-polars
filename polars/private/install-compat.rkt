#lang racket/base

(require (only-in racket/file
                  delete-directory/files make-directory* make-temporary-file)
         (only-in racket/match match)
         (only-in "native-location.rkt"
                  compat-lib-env-var dev-built? dev-built-library? dev-marker library-file
                  manifest-problem native-library-problem native-location native-package
                  outranking-package required-native-version)
         (only-in "resource.rkt" with-release))

(provide pre-installer)

(define force-candidate-env-var "RKT_POLARS_FORCE_CANDIDATE")
(define compat-lib-pattern #rx"^libcompat\\.")

(define (preinstall-error . args)
  (apply error 'pre-installer args))

(define block-size 65536)

(define (same-contents? in-a in-b)
  (define a (read-bytes block-size in-a))
  (define b (read-bytes block-size in-b))
  (cond
    [(eof-object? a) (eof-object? b)]
    [(equal? a b) (same-contents? in-a in-b)]
    [else #f]))

(define (same-bytes? src dst)
  (with-handlers ([exn:fail:filesystem? (lambda (_) #f)])
    (and (file-exists? src)
         (file-exists? dst)
         (= (file-size src) (file-size dst))
         (call-with-input-file* src
           (lambda (in-src)
             (call-with-input-file* dst
               (lambda (in-dst) (same-contents? in-src in-dst))))))))

(define (install-if-different! src dst)
  (unless (same-bytes? src dst)
    (define-values (dir name _) (split-path dst))
    (with-release ([staged
                    (make-temporary-file (string-append "." (path->string name) ".~a")
                                         #:base-dir dir)
                    (lambda (p) (delete-directory/files p #:must-exist? #f))])
      (copy-file src staged #:exists-ok? #t #:permissions #o755)
      (rename-file-or-directory staged dst #t))))

(define (copy-native-libs! dest-dir source-dir pattern install!)
  (make-directory* dest-dir)
  (for ([f (in-list (directory-list source-dir))]
        #:when (regexp-match? pattern (path->string f)))
    (install! (build-path source-dir f) (build-path dest-dir f))))

(define (remove-marker! marker)
  (when (or (link-exists? marker) (file-exists? marker))
    (with-handlers ([exn:fail:filesystem? void])
      (delete-file marker))))

(define ((install-candidate! force?) src dst)
  (define marker (dev-marker dst))
  (cond
    [(and (not force?) (dev-built? dst marker))
     (printf "pre-installer: keeping the dev-built ~a; ~a=1 installs the committed candidate\n"
             dst
             force-candidate-env-var)]
    [else
     (install-if-different! src dst)
     (remove-marker! marker)]))

(define (has-matching-files? dir pattern)
  (and (directory-exists? dir)
       (pair? (filter (lambda (f)
                        (regexp-match? pattern (path->string f)))
                      (directory-list dir)))))

;; Prebuilt shared objects committed to the repo, one directory per
;; platform.  pkgs.rkt-lang.org's build host has no Rust toolchain, so it
;; installs from these instead of compiling.  Names match the directories
;; produced by scripts/build-so.sh.
(define (candidate-platforms)
  (case (system-type 'os)
    [(macosx) '("darwin")]
    [(unix) '("linux")]
    [else '()]))

;; First committed candidate directory that actually holds a libcompat.*,
;; or #f when none of the platform candidates are present.
(define (find-candidate-dir candidates-dir)
  (for/or ([plat (in-list (candidate-platforms))])
    (define dir (build-path candidates-dir plat))
    (and (has-matching-files? dir compat-lib-pattern) dir)))

(define (check-native-package! location wanted)
  (match (or (native-library-problem location wanted) (manifest-problem location wanted))
    [#f (void)]
    [message (preinstall-error "~a" message)]))

(define (pre-installer collections-top-path this-collection-path user-specific?)
  (define native-libs-dir
    (build-path this-collection-path "native-libs"))
  (define candidates-dir
    (build-path native-libs-dir "candidates"))
  (define compat-lib-path
    (match (getenv compat-lib-env-var)
      [(or #f "") #f]
      [path path]))
  (define package (and (not compat-lib-path) (outranking-package)))
  (define dev-library (and package (dev-built-library? native-libs-dir)))
  (cond
    ;; 1. Explicit override (the Nix build).
    [compat-lib-path
     (copy-native-libs! native-libs-dir
                        (build-path compat-lib-path "lib")
                        compat-lib-pattern
                        install-if-different!)]
    ;; 2. A dev-built library outranks the native package, unchecked.
    [dev-library
     (printf "pre-installer: keeping the dev-built ~a over the package ~a\n"
             (build-path native-libs-dir library-file)
             (native-package))]
    ;; 3. The native package, which a committed candidate never shadows.
    [package (check-native-package! package (required-native-version this-collection-path))]
    ;; 4. Committed per-platform prebuilt candidate (until #254's L3).
    [(find-candidate-dir candidates-dir)
     => (lambda (dir)
          (copy-native-libs! native-libs-dir
                             dir
                             compat-lib-pattern
                             (install-candidate!
                              (equal? (getenv force-candidate-env-var) "1"))))]
    ;; 5. Already staged (nothing to do).
    [(has-matching-files? native-libs-dir compat-lib-pattern)
     (void)]
    [else
     (eprintf "pre-installer: ~a\n"
              (native-library-problem (native-location 'missing native-libs-dir #f #f #f) #f))]))
