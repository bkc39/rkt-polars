#lang racket/base

(require (only-in file/sha1 bytes->hex-string)
         (only-in racket/list filter-map remove-duplicates)
         (only-in racket/match match)
         (only-in racket/path find-relative-path path-has-extension? path-only)
         (only-in threading ~>))

(struct failure (module message symbol))

(define polars-dir (path-only (collection-file-path "main.rkt" "polars")))

(define lib
  (build-path polars-dir "native-libs"
              (path-add-extension "libcompat" (system-type 'so-suffix))))

(define modules
  (sort (for/list ([f (in-directory (build-path polars-dir "private"))]
                   #:when (path-has-extension? f #".rkt"))
          f)
        path<?))

(define (missing-symbol message)
  (match message
    [(regexp #rx"could not find export from foreign library\n  name: ([^\n]+)"
             (list _ name))
     name]
    [_ #f]))

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
  (~> (build-path polars-dir 'up) simplify-path (find-relative-path path)))

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
