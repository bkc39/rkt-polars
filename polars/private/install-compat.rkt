#lang racket/base

(require
 (only-in dynext/file
          append-extension-suffix)
 (only-in racket/file
          make-directory*)
 (only-in racket/system
          system*)
 (only-in setup/dirs
          find-user-lib-dir
          find-lib-dir))

(provide pre-installer)

(define COMPAT-SRC-DIR "compat")

(define (preinstall-error . args)
  (apply error (cons 'pre-installer args)))

(define (pre-installer collections-top-path this-collection-path user-specific?)
  (define private-path
    (build-path this-collection-path "private"))
  (define compat-path
    (build-path private-path "compat"))
  (define cargo-path
    (find-executable-path "cargo"))
  (unless (path? cargo-path)
    (preinstall-error
     "cargo command not found on system. install cargo:~n~a"
     "https://doc.rust-lang.org/cargo/getting-started/installation.html"))
  (define shared-object-basename
    (append-extension-suffix "libcompat"))
  (define compiled-object-path
    (build-path compat-path
                "target"
                "release"
                shared-object-basename))
  (define lib-path
    (if user-specific?
        (find-user-lib-dir)
        (find-lib-dir)))
  (make-directory* lib-path)
  (define destination-object-path
    (build-path lib-path shared-object-basename))

  (parameterize ([current-directory compat-path])
    (displayln (format "in directory: ~a" (current-directory)))
    (unless (system* cargo-path "build" "--release")
      (preinstall-error "cargo build failed"))
    (unless (file-exists? compiled-object-path)
      (preinstall-error
       "libcompat shared object not in expected location:~n~a"
       compiled-object-path))
    (copy-file compiled-object-path destination-object-path
               #:exists-ok? #t)
    (printf "Copied ~a => ~a\n"
            compiled-object-path
            destination-object-path)))
