#lang racket/base

(require (only-in json write-json)
         (only-in racket/cmdline command-line)
         (only-in racket/file file->string make-directory*)
         (only-in racket/path file-name-from-path path-only)
         (only-in racket/port with-output-to-string)
         racket/runtime-path
         (only-in racket/string string-join string-trim)
         (only-in racket/system system*)
         (only-in setup/getinfo get-info/full)
         (only-in polars/private/native-location
                  current-native-platform manifest-jsexpr manifest-problem native-location
                  native-package required-native-version))

(define-runtime-path repo "..")

(define (fail fmt . args)
  (eprintf "stage-native-package: ~a\n" (apply format fmt args))
  (exit 1))

(define (library-suffix platform)
  (if (regexp-match? #rx"macosx" platform) ".dylib" ".so"))

(define (git . args)
  (define exe
    (or (find-executable-path "git")
        (fail "--head reads this checkout's HEAD with git, which is not on PATH")))
  (define out
    (with-output-to-string
      (lambda ()
        (unless (apply system* exe "-C" (path->string repo) args)
          (fail "git ~a failed" (string-join args))))))
  (string-trim out))

(define (recorded library name)
  (define path (build-path (path-only library) name))
  (and (file-exists? path) (string-trim (file->string path))))

(define (head-provenance)
  (unless (equal? (git "status" "--porcelain" "--untracked-files=all" "--" "rust") "")
    (fail "rust/ differs from HEAD, so HEAD does not name the tree the library was built from"))
  (values (git "rev-parse" "HEAD:rust") (git "rev-parse" "HEAD")))

(define (provenance library rust-tree commit head?)
  (define tree-record (recorded library "rust-tree"))
  (define commit-record (recorded library "commit"))
  (cond
    [(and rust-tree commit) (values rust-tree commit)]
    [(or rust-tree commit) (fail "--rust-tree and --commit go together")]
    [(and tree-record commit-record) (values tree-record commit-record)]
    [(or tree-record commit-record)
     (fail "~a records ~a but not ~a"
           (path-only library)
           (if tree-record "rust-tree" "commit")
           (if tree-record "commit" "rust-tree"))]
    [head? (head-provenance)]
    [else
     (fail (string-append "nothing names the rust/ tree and commit ~a was built from: pass "
                          "--rust-tree and --commit, or --head for this checkout's")
           library)]))

(define (stage! platform library out rust-tree commit notices)
  (define package (or (native-package platform) (fail "no native package for ~a" platform)))
  (define skeleton (build-path repo "native" package))
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
  (for ([source (list* (build-path skeleton "info.rkt")
                       (build-path skeleton "main.rkt")
                       (build-path repo "LICENSE-APACHE")
                       (build-path repo "LICENSE-MIT")
                       library
                       (if notices (list notices) '()))]
        [target (list "info.rkt" "main.rkt" "LICENSE-APACHE" "LICENSE-MIT"
                      (build-path "native-libs" name) "THIRD-PARTY-NOTICES.txt")])
    (copy-file source (build-path out target)))
  (call-with-output-file* (build-path out "manifest.json")
    (lambda (port) (write-json (manifest-jsexpr libs version rust-tree commit) port)))
  (define problem (manifest-problem (native-location 'package libs out version #f) version))
  (when problem
    (fail "~a" problem))
  (printf "staged ~a ~a in ~a\n" package version out))

(module+ main
  (define rust-tree #f)
  (define commit #f)
  (define head? #f)
  (define notices #f)
  (command-line
   #:program "stage-native-package"
   #:once-each
   [("--rust-tree") tree "The rust/ tree LIBCOMPAT was built from" (set! rust-tree tree)]
   [("--commit") sha "The commit LIBCOMPAT was built from" (set! commit sha)]
   [("--head") "With no record, name HEAD and its clean rust/" (set! head? #t)]
   [("--notices") file "The third-party notices to ship as THIRD-PARTY-NOTICES.txt"
                  (set! notices (path->complete-path file))]
   #:args (platform library out)
   (define library-path (path->complete-path library))
   (define-values (tree built) (provenance library-path rust-tree commit head?))
   (parameterize ([current-native-platform platform])
     (stage! platform library-path (path->complete-path out) tree built notices))))
