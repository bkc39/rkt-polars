#lang racket/base

(require (only-in racket/file
                  delete-directory/files make-directory* make-temporary-file)
         (only-in racket/dict dict-ref)
         (only-in "native-location.rkt"
                  dev-built? dev-built-library? dev-marker library-file manifest-problem
                  missing-message native-library-problem native-package outranking-package
                  override-dir required-native-version)
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

(define package-candidates
  '(("polars-x86_64-linux" . "linux")
    ("polars-aarch64-macosx" . "darwin")))

(define (find-candidate-dir candidates-dir)
  (define platform (dict-ref package-candidates (native-package) #f))
  (define dir (and platform (build-path candidates-dir platform)))
  (and dir (has-matching-files? dir compat-lib-pattern) dir))

(define (check-native-package! location wanted)
  (define message (or (native-library-problem location wanted) (manifest-problem location wanted)))
  (when message
    (preinstall-error "~a" message)))

(define (pre-installer collections-top-path this-collection-path user-specific?)
  (define native-libs-dir
    (build-path this-collection-path "native-libs"))
  (define candidates-dir
    (build-path native-libs-dir "candidates"))
  (define override (override-dir))
  (define package (and (not override) (outranking-package)))
  (define dev-library (and package (dev-built-library? native-libs-dir)))
  (cond
    [override
     (copy-native-libs! native-libs-dir override compat-lib-pattern install-if-different!)]
    [dev-library
     (printf "pre-installer: keeping the dev-built ~a over the package ~a\n"
             (build-path native-libs-dir library-file)
             (native-package))]
    [package (check-native-package! package (required-native-version this-collection-path))]
    [(find-candidate-dir candidates-dir)
     => (lambda (dir)
          (copy-native-libs! native-libs-dir
                             dir
                             compat-lib-pattern
                             (install-candidate!
                              (equal? (getenv force-candidate-env-var) "1"))))]
    [(has-matching-files? native-libs-dir compat-lib-pattern)
     (void)]
    [else
     (eprintf "pre-installer: ~a\n" (missing-message native-libs-dir))]))
