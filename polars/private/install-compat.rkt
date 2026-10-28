#lang racket/base

(require (only-in racket/file
                  delete-directory/files make-directory* make-temporary-file))

(provide pre-installer)

(define compat-lib-env-var "RKT_POLARS_COMPAT_LIB_PATH")
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
  (and (file-exists? src)
       (file-exists? dst)
       (= (file-size src) (file-size dst))
       (call-with-input-file* src
         (lambda (in-src)
           (call-with-input-file* dst
             (lambda (in-dst) (same-contents? in-src in-dst)))))))

(define (install-by-rename! src dst dest-dir f)
  (define staged
    (make-temporary-file (string-append "." (path->string f) ".~a") #:base-dir dest-dir))
  (define installed? #f)
  (dynamic-wind
   void
   (lambda ()
     (copy-file src staged #:exists-ok? #t #:permissions #o755)
     (rename-file-or-directory staged dst #t)
     (set! installed? #t))
   (lambda ()
     (unless installed?
       (delete-directory/files staged #:must-exist? #f)))))

(define (copy-native-libs! dest-dir source-dir pattern)
  (make-directory* dest-dir)
  (for ([f (in-list (directory-list source-dir))]
        #:when (regexp-match? pattern (path->string f)))
    (define src (build-path source-dir f))
    (define dst (build-path dest-dir f))
    (unless (same-bytes? src dst)
      (install-by-rename! src dst dest-dir f))))

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

(define (pre-installer collections-top-path this-collection-path user-specific?)
  (define native-libs-dir
    (build-path this-collection-path "native-libs"))
  (define candidates-dir
    (build-path native-libs-dir "candidates"))
  (define compat-lib-path
    (getenv compat-lib-env-var))
  (cond
    ;; 1. Explicit override (Nix build output / dev shell).
    [compat-lib-path
     (copy-native-libs! native-libs-dir
                        (build-path compat-lib-path "lib")
                        compat-lib-pattern)]
    ;; 2. Committed per-platform prebuilt candidate (catalog install).
    [(find-candidate-dir candidates-dir)
     => (lambda (dir)
          (copy-native-libs! native-libs-dir dir compat-lib-pattern))]
    ;; 3. Already staged (nothing to do).
    [(has-matching-files? native-libs-dir compat-lib-pattern)
     (void)]
    [else
     (preinstall-error
      (string-append
       "compatibility library not found. Either:\n"
       "  1. Run: scripts/build-so.sh   (requires the Rust toolchain)\n"
       "  2. Run: nix run .#copy-native-libs\n"
       "  3. Set ~a to a Nix build output containing lib/libcompat.*\n"
       "  4. Copy libcompat into ~a")
      compat-lib-env-var
      (path->string native-libs-dir))]))
