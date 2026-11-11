#lang racket/base

(require (for-syntax racket/base
                     (only-in compiler/cm-accomplice register-external-file)
                     (only-in racket/path path-only)
                     (only-in polars/private/native-location required-native-version))
         (only-in ffi/unsafe ffi-lib)
         (only-in racket/match match)
         racket/runtime-path
         syntax/parse/define
         (only-in polars/private/native-location
                  library-file locate-native-library missing-export-message native-library-problem
                  native-location-dir unloadable-message))

(provide compat-library
         missing-export
         native-library-file)

(define-syntax-parser compiled-native-version
  [(_)
   (define polars-dir (simplify-path (build-path (path-only (syntax-source this-syntax)) 'up)))
   (register-external-file (build-path polars-dir "info.rkt"))
   #`(quote #,(required-native-version polars-dir))])

(define-runtime-path staged-dir "../native-libs")

(define location (locate-native-library staged-dir))

(define native-library-file (build-path (native-location-dir location) library-file))

(define compat-library
  (match (native-library-problem location (compiled-native-version))
    [#f
     (with-handlers ([exn:fail?
                      (lambda (e)
                        (error 'polars "~a" (unloadable-message location (exn-message e))))])
       (ffi-lib (build-path (native-location-dir location) "libcompat")))]
    [message (error 'polars "~a" message)]))

(define ((missing-export id))
  (error 'polars "~a" (missing-export-message location id)))
