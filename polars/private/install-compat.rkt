#lang racket/base

(require racket/file)

(provide pre-installer)

(define compat-lib-env-var "RKT_POLARS_COMPAT_LIB_PATH")
(define compat-lib-pattern #rx"^libcompat\\.")

(define (preinstall-error . args)
  (apply error (cons 'pre-installer args)))

(define (copy-native-libs! dest-dir source-dir pattern)
  (make-directory* dest-dir)
  (for ([f (in-list (directory-list source-dir))])
    (when (regexp-match? pattern (path->string f))
      (define src (build-path source-dir f))
      (define dst (build-path dest-dir f))
      (when (file-exists? dst)
        (delete-file dst))
      (copy-file src dst))))

(define (has-matching-files? dir pattern)
  (and (directory-exists? dir)
       (pair? (filter (lambda (f)
                        (regexp-match? pattern (path->string f)))
                      (directory-list dir)))))

(define (pre-installer collections-top-path this-collection-path user-specific?)
  (define native-libs-dir
    (build-path this-collection-path "native-libs"))
  (define compat-lib-path
    (getenv compat-lib-env-var))
  (cond
    [compat-lib-path
     (copy-native-libs! native-libs-dir
                        (build-path compat-lib-path "lib")
                        compat-lib-pattern)]
    [(has-matching-files? native-libs-dir compat-lib-pattern)
     (void)]
    [else
     (preinstall-error
      "compatibility library not found. Either:\n  1. Run: nix run .#copy-native-libs\n  2. Set ~a to a Nix build output containing lib/libcompat.*\n  3. Copy libcompat into ~a"
      compat-lib-env-var
      (path->string native-libs-dir))]))
