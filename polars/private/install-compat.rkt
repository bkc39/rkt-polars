#lang racket/base

(require racket/file
         racket/system)

(provide pre-installer)

(define COMPAT-SRC-DIR "compat")

(define (pre-installer collections-top-path this-collection-path user-specific?)
  (printf "top: ~a~nthis: ~a~nspecific? ~a~n"
          collections-top-path
          this-collection-path
          user-specific?)


  (define private-path
    (build-path this-collection-path "private"))
  (define compat-path
    (build-path private-path "compat"))
  (define cargo-path
    (find-executable-path "cargo"))
  (unless (path? cargo-path)
    (error
     'pre-installer
     "cargo command not found on system. install cargo:~n~a"
     "https://doc.rust-lang.org/cargo/getting-started/installation.html"))

  (parameterize ([current-directory compat-path])
    (displayln (format "in directory: ~a" (current-directory)))
    (unless (system* cargo-path "build" "--release")
      (error 'pre-installer "cargo build failed"))
    (displayln "here we are")))
