#lang racket/base

(require (only-in ffi/unsafe ffi-lib)
         (only-in racket/match match)
         racket/runtime-path
         (only-in polars/private/native-location
                  library-file locate-native-library missing-export-message native-library-problem
                  native-location-dir required-native-version unloadable-message))

(provide compat-library
         missing-export
         native-library-file)

(define-runtime-path staged-dir "../native-libs")
(define-runtime-path polars-dir "..")

(define (raise-native-failure message)
  (raise (exn:fail (string-append "polars: " message) (current-continuation-marks))))

(define location (locate-native-library staged-dir))

(define native-library-file (build-path (native-location-dir location) library-file))

(define compat-library
  (match (native-library-problem location (required-native-version polars-dir))
    [#f
     (with-handlers ([exn:fail? (lambda (e)
                                  (raise-native-failure (unloadable-message location (exn-message e))))])
       (ffi-lib (build-path (native-location-dir location) "libcompat")))]
    [message (raise-native-failure message)]))

(define ((missing-export id))
  (raise-native-failure (missing-export-message location id)))
