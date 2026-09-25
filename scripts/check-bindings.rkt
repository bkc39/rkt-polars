#lang racket/base

;; Instantiates every module under the installed polars collection's private/
;; against the libcompat staged in its native-libs/.  define-compat resolves
;; each C symbol at instantiation, so this fails on any symbol the library
;; does not export, including symbols bound through macros.

(require (only-in file/sha1 bytes->hex-string)
         (only-in racket/list filter-map remove-duplicates)
         (only-in racket/path find-relative-path path-only)
         (only-in threading ~>))

(struct failure (module message symbol))

(define polars-dir (path-only (collection-file-path "main.rkt" "polars")))

(define lib
  (build-path polars-dir "native-libs"
              (bytes->path (bytes-append #"libcompat" (system-type 'so-suffix)))))

(define modules
  (sort (for/list ([f (in-directory (build-path polars-dir "private"))]
                   #:when (regexp-match? #rx"[.]rkt$" f))
          f)
        path<?))

(define (missing-symbol message)
  (define m
    (regexp-match #rx"could not find export from foreign library\n  name: ([^\n]+)"
                  message))
  (and m (cadr m)))

;; One namespace per module: once an instantiation fails, a module requiring
;; the failed one reports an uninitialized variable instead of the cause.
(define (instantiation-failure module)
  (parameterize ([current-namespace (make-base-empty-namespace)])
    (with-handlers ([exn:fail? (lambda (e)
                                 (define message (exn-message e))
                                 (failure module message (missing-symbol message)))])
      (dynamic-require module #f)
      #f)))

(define (relative path)
  (find-relative-path (simplify-path (build-path polars-dir 'up)) path))

(module+ main
  (printf "libcompat: ~a (sha256 ~a)\n"
          lib
          (~> (call-with-input-file lib sha256-bytes) bytes->hex-string (substring 0 16)))
  (define failures (filter-map instantiation-failure modules))
  (define missing (remove-duplicates (filter-map failure-symbol failures)))
  (for ([symbol (in-list missing)])
    (printf "MISSING ~a\n" symbol))
  (for ([f (in-list (remove-duplicates failures #:key failure-message))]
        #:unless (failure-symbol f))
    (printf "FAILED  ~a: ~a\n" (relative (failure-module f)) (failure-message f)))
  (printf "~a of ~a modules under polars/private instantiate against it\n"
          (- (length modules) (length failures))
          (length modules))
  (unless (null? missing)
    (printf "(each module stops at its first missing symbol; more may be missing)\n"))
  (unless (null? failures)
    (exit 1)))
