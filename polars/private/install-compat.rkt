#lang racket/base

(require (only-in file/sha1 bytes->hex-string)
         (only-in racket/file
                  delete-directory/files make-directory* make-temporary-file)
         (only-in racket/match match)
         (only-in "resource.rkt" with-release))

(provide pre-installer)

(define compat-lib-env-var "RKT_POLARS_COMPAT_LIB_PATH")
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

(define (dev-marker dst)
  (define-values (dir name _) (split-path dst))
  (build-path dir (string-append "." (path->string name) ".dev")))

(define marker-pattern #px#"^([0-9a-f]{64})\n$")

(define (marked-sha256 marker)
  (define contents
    (call-with-input-file* marker (lambda (in) (read-bytes 66 in))))
  (match (and (bytes? contents) (regexp-match marker-pattern contents))
    [(list _ hex) (bytes->string/utf-8 hex)]
    [#f #f]))

(define (sha256-hex path)
  (call-with-input-file* path (lambda (in) (bytes->hex-string (sha256-bytes in)))))

(define (dev-built? dst marker)
  (with-handlers ([exn:fail:filesystem? (lambda (_) #f)])
    (define marked (and (file-exists? marker) (file-exists? dst) (marked-sha256 marker)))
    (and marked (equal? marked (sha256-hex dst)))))

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
                        compat-lib-pattern
                        install-if-different!)]
    ;; 2. Committed per-platform prebuilt candidate (catalog install).
    [(find-candidate-dir candidates-dir)
     => (lambda (dir)
          (copy-native-libs! native-libs-dir
                             dir
                             compat-lib-pattern
                             (install-candidate!
                              (equal? (getenv force-candidate-env-var) "1"))))]
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
