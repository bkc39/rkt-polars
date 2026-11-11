#lang racket/base

;; Usage: racket scripts/stage-native-package.rkt PLATFORM LIBCOMPAT OUT-DIR
;;
;; Assembles the native package for PLATFORM (x86_64-linux, aarch64-macosx)
;; in OUT-DIR from a built LIBCOMPAT: the skeleton's info.rkt and main.rkt,
;; the licences, native-libs/LIBCOMPAT and manifest.json.  OUT-DIR must not
;; exist.  The manifest names this checkout's HEAD and its rust/ tree.

(require (only-in json write-json)
         (only-in racket/file make-directory*)
         (only-in racket/match match)
         (only-in racket/path file-name-from-path)
         (only-in racket/port with-output-to-string)
         racket/runtime-path
         (only-in racket/string string-trim)
         (only-in racket/system system*)
         (only-in setup/getinfo get-info/full)
         (only-in "../polars/private/native-location.rkt"
                  current-native-platform manifest-jsexpr manifest-problem native-location
                  native-package required-native-version))

(define-runtime-path repo "..")

(define (fail fmt . args)
  (eprintf "stage-native-package: ~a\n" (apply format fmt args))
  (exit 1))

(define (library-suffix platform)
  (if (regexp-match? #rx"macosx" platform) ".dylib" ".so"))

(define (git . args)
  (define out
    (with-output-to-string
      (lambda ()
        (unless (apply system* (find-executable-path "git") "-C" (path->string repo) args)
          (fail "git ~a failed" args)))))
  (string-trim out))

(define (stage! platform library out)
  (define package (or (native-package platform) (fail "no native package for ~a" platform)))
  (define skeleton (build-path repo package))
  (define version ((get-info/full skeleton) 'version))
  (define wanted (required-native-version (build-path repo "polars")))
  (define name (path->string (file-name-from-path library)))
  (unless (equal? version wanted)
    (fail "~a is version ~a, but polars/info.rkt's native-version is ~a" package version wanted))
  (unless (equal? name (string-append "libcompat" (library-suffix platform)))
    (fail "~a is not ~a's library, libcompat~a" library platform (library-suffix platform)))
  (when (or (directory-exists? out) (file-exists? out))
    (fail "~a already exists" out))
  (define libs (build-path out "native-libs"))
  (make-directory* libs)
  (for ([file (in-list '("info.rkt" "main.rkt"))])
    (copy-file (build-path skeleton file) (build-path out file)))
  (for ([file (in-list '("LICENSE-APACHE" "LICENSE-MIT"))])
    (copy-file (build-path repo file) (build-path out file)))
  (copy-file library (build-path libs name))
  (call-with-output-file* (build-path out "manifest.json")
    (lambda (port)
      (write-json (manifest-jsexpr libs version (git "rev-parse" "HEAD:rust") (git "rev-parse" "HEAD"))
                  port)))
  (match (manifest-problem (native-location 'package libs out version #f) version)
    [#f (printf "staged ~a ~a in ~a\n" package version out)]
    [problem (fail "~a" problem)]))

(module+ main
  (match (current-command-line-arguments)
    [(vector platform library out)
     (parameterize ([current-native-platform platform])
       (stage! platform (path->complete-path library) (path->complete-path out)))]
    [_ (fail "usage: racket scripts/stage-native-package.rkt PLATFORM LIBCOMPAT OUT-DIR")]))
