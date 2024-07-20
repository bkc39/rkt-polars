#lang racket/base

(require setup/dirs)
(require file/glob) ; To match files using wildcards
(require racket/file) ; For file utilities
(require racket/path)

(module+ test
  (require rackunit))

;; Code here

(define (copy-file-to-user-lib source-file)
  (define-values (a basename c)
    (split-path source-file))
  (define user-lib-dir
    (find-user-lib-dir))
  (define destination
    (build-path user-lib-dir
                (path->string basename)))
  (unless (directory-exists? user-lib-dir)
    (make-directory* user-lib-dir))
  (copy-file source-file destination
             #:exists-ok? #t)
  (printf "Copied ~a => ~a\n" source-file destination))

(define (main)
  (define target-dir "compat/target/release")
  (define files (glob (build-path target-dir "*.so")))
  (for ([file files])
    (when (file-exists? file)
      (copy-file-to-user-lib file))))

(module+ test
  (check-equal? (+ 2 2) 4))

(module+ main
  (main))
