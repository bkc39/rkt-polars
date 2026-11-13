#lang racket/base

(require (only-in racket/list take)
         (only-in racket/match match)
         (only-in racket/path path-only)
         (only-in pkg/lib pkg-directory)
         (only-in polars/private/native-location
                  locate-native-library native-location-dir native-location-kind))

(define (fail fmt . args)
  (eprintf "check-native-install: ~a\n" (apply format fmt args))
  (exit 1))

(define (under? path dir)
  (define parts (explode-path (simplify-path path)))
  (define prefix (explode-path (simplify-path dir)))
  (and (<= (length prefix) (length parts)) (equal? (take parts (length prefix)) prefix)))

(define (check! package)
  (define root (or (pkg-directory package) (fail "~a is not installed" package)))
  (define staged (build-path (path-only (collection-file-path "main.rkt" "polars")) "native-libs"))
  (define kind (native-location-kind (locate-native-library staged)))
  (define file (dynamic-require 'polars/private/native-library 'native-library-file))
  (define candidates
    (for/list ([name (in-list (directory-list staged))]
               #:when (regexp-match? #rx"^libcompat[.]" (path->string name)))
      name))
  (unless (eq? kind 'package)
    (fail "polars locates libcompat as ~a, not in the package ~a" kind package))
  (unless (under? file root)
    (fail "polars loads ~a, which is not in the package ~a at ~a" file package root))
  (unless (null? candidates)
    (fail "the polars install staged ~a in ~a" candidates staged))
  (printf "polars loads ~a from the package ~a\n" file package))

(module+ main
  (match (current-command-line-arguments)
    [(vector package) (check! package)]
    [_ (fail "usage: racket scripts/check-native-install.rkt PACKAGE")]))
