#lang racket/base

(module+ test
  (require rackunit
           (only-in ffi/unsafe _fun _void)
           (only-in ffi/unsafe/define define-ffi-definer)
           (only-in racket/path file-name-from-path)
           (only-in threading ~>)
           (only-in polars/private/native-library
                    compat-library missing-export native-library-file)
           (only-in polars/private/native-location library-file)
           (only-in polars/tests/test-helpers contains-all? message-of))

  (define-ffi-definer define-probe compat-library #:default-make-fail missing-export)

  (test-case "a binding the library lacks fails naming the binding, not the C symbol"
    (define message
      (message-of (lambda ()
                    (define-probe polars-probe-no-such-export (_fun -> _void))
                    polars-probe-no-such-export)))
    (check-true (contains-all? message
                               (list "polars: libcompat lacks the export for "
                                     "polars-probe-no-such-export, so it is older than this polars"
                                     "\n  found in: "))))

  (test-case "the library loaded is libcompat"
    (check-equal? (~> native-library-file file-name-from-path path->string) library-file)
    (check-true (file-exists? native-library-file))))
