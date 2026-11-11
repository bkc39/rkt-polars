#lang racket/base

(require (only-in file/sha1 bytes->hex-string)
         (only-in json read-json)
         (only-in racket/contract/base
                  -> ->* cons/c contract-out flat-named-contract listof or/c parameter/c)
         (only-in racket/dict dict-ref)
         (only-in racket/list filter-not remove-duplicates)
         (only-in racket/match match match-define)
         (only-in racket/path path-only)
         (only-in racket/string string-join)
         (only-in setup/getinfo get-info/full)
         (only-in threading ~>))

(provide compat-lib-env-var
         (contract-out
          (struct native-location ([kind (or/c 'override 'staged 'package 'broken 'missing)]
                                   [dir path?]
                                   [root (or/c path? #f)]
                                   [version (or/c string? #f)]
                                   [cause (or/c string? #f)]))
          [current-native-platform (parameter/c string?)]
          [dev-built? (-> path-string? path-string? boolean?)]
          [dev-built-library? (-> path-string? boolean?)]
          [dev-marker (-> path-string? path?)]
          [installed-native-package (-> (or/c native-location? #f))]
          [library-file string?]
          [locate-native-library (-> path-string? native-location?)]
          [manifest-jsexpr (-> path-string? string? string? string? hash?)]
          [manifest-problem (-> native-location? (or/c string? #f) (or/c string? #f))]
          [missing-export-message (-> loaded-location/c symbol? string?)]
          [missing-message (-> path-string? string?)]
          [native-library-problem (-> native-location? (or/c string? #f) (or/c string? #f))]
          [native-package (->* () (string?) (or/c string? #f))]
          [native-packages (listof (cons/c string? string?))]
          [outranking-package (-> (or/c native-location? #f))]
          [override-dir (-> (or/c path? #f))]
          [required-native-version (-> path-string? (or/c string? #f))]
          [sha256-hex (-> path-string? string?)]
          [unloadable-message (-> loaded-location/c string? string?)]))

(struct native-location (kind dir root version cause) #:transparent)

(define loaded-location/c
  (flat-named-contract
   'loaded-native-location?
   (lambda (location)
     (and (native-location? location)
          (memq (native-location-kind location) '(override staged package))
          #t))))

(define compat-lib-env-var "RKT_POLARS_COMPAT_LIB_PATH")

(define native-packages
  '(("x86_64-linux" . "polars-x86_64-linux")
    ("x86_64-linux-natipkg" . "polars-x86_64-linux")
    ("aarch64-macosx" . "polars-aarch64-macosx")))

(define current-native-platform
  (make-parameter (path->string (system-library-subpath #f))))

(define (native-package [platform (current-native-platform)])
  (dict-ref native-packages platform #f))

(define library-file
  (string-append "libcompat" (bytes->string/utf-8 (system-type 'so-suffix))))

(define (holds-library? dir)
  (file-exists? (build-path dir library-file)))

(define (sha256-hex path)
  (call-with-input-file* path (lambda (in) (bytes->hex-string (sha256-bytes in)))))

(define (dev-marker library)
  (define-values (dir name _) (split-path library))
  (build-path dir (string-append "." (path->string name) ".dev")))

(define marker-pattern #px#"^([0-9a-f]{64})\n$")

(define (marked-sha256 marker)
  (define contents (call-with-input-file* marker (lambda (in) (read-bytes 66 in))))
  (match (and (bytes? contents) (regexp-match marker-pattern contents))
    [(list _ hex) (bytes->string/utf-8 hex)]
    [#f #f]))

(define (dev-built? library marker)
  (with-handlers ([exn:fail:filesystem? (lambda (_) #f)])
    (define marked (and (file-exists? marker) (file-exists? library) (marked-sha256 marker)))
    (and marked (equal? marked (sha256-hex library)))))

(define (dev-built-library? dir)
  (define library (build-path dir library-file))
  (dev-built? library (dev-marker library)))

(define (info-field dir key)
  (define info (get-info/full dir))
  (and info (info key (lambda () #f))))

(define (required-native-version polars-dir)
  (info-field polars-dir 'native-version))

(define (override-dir)
  (match (getenv compat-lib-env-var)
    [(or #f "") #f]
    [dir (~> (build-path dir "lib") path->complete-path simplify-path)]))

(define (installed-native-package)
  (define package (native-package))
  (match (and package (collection-file-path "main.rkt" package #:fail (lambda (_) #f)))
    [#f #f]
    [main
     (define root (simplify-path (path-only main)))
     (define version (info-field root 'version))
     (with-handlers ([exn:fail?
                      (lambda (e) (native-location 'broken root root #f (exn-message e)))])
       (native-location 'package
                        (simplify-path (dynamic-require main 'native-libs-dir))
                        root
                        (and (string? version) version)
                        #f))]))

(define (outranking-package)
  (match (installed-native-package)
    [(and location (native-location 'package dir _ _ _)) #:when (holds-library? dir) location]
    [(and location (native-location 'broken _ _ _ _)) location]
    [_ #f]))

(define (shadowing-package staged)
  (define package (outranking-package))
  (and package (not (dev-built-library? staged)) package))

(define (locate-native-library staged-dir)
  (define staged (simplify-path (path->complete-path staged-dir)))
  (cond
    [(override-dir) => (lambda (dir) (native-location 'override dir #f #f #f))]
    [(not (holds-library? staged))
     (or (installed-native-package) (native-location 'missing staged #f #f #f))]
    [(shadowing-package staged)]
    [else (native-location 'staged staged #f #f #f)]))

(define override-advice
  (format "to use a libcompat built by hand, set ~a to the directory whose lib/ holds it"
          compat-lib-env-var))

(define (update-advice package)
  (format "update both with `raco pkg update polars ~a`" package))

(define (reinstall-advice package)
  (format "reinstall it with `raco pkg remove --force ~a` and `raco pkg install ~a`"
          package
          package))

(define supported-platforms
  (~> (map car native-packages)
      (filter-not (lambda (platform) (regexp-match? #rx"-natipkg$" platform)) _)
      (string-join ", " #:before-last " and ")))

(define (missing-message dir)
  (match (native-package)
    [#f
     (format (string-append "libcompat is not installed: polars ships it for ~a, not ~a\n"
                            "  looked in: ~a\n  ~a")
             supported-platforms
             (current-native-platform)
             dir
             override-advice)]
    [package
     (format (string-append "libcompat is not installed: the package ~a is missing\n"
                            "  looked in: ~a\n  install it with `raco pkg install ~a`; ~a")
             package
             dir
             package
             override-advice)]))

(define (native-library-problem location wanted)
  (define package (native-package))
  (match location
    [(native-location 'missing dir _ _ _) (missing-message dir)]
    [(native-location 'broken _ root _ cause)
     (format "the package ~a is installed but would not load\n  found in: ~a\n  it said: ~a\n  ~a"
             package
             root
             cause
             (reinstall-advice package))]
    [(native-location 'override dir _ _ _)
     #:when (not (holds-library? dir))
     (format "libcompat is not where ~a points\n  looked in: ~a\n  unset it, or ~a"
             compat-lib-env-var
             dir
             override-advice)]
    [(native-location 'package dir _ _ _)
     #:when (not (holds-library? dir))
     (format "the package ~a holds no libcompat\n  looked in: ~a\n  ~a"
             package
             dir
             (reinstall-advice package))]
    [(native-location 'package _ root found _)
     #:when (not (equal? found wanted))
     (format "the package ~a is version ~a, but this polars needs version ~a\n  found in: ~a\n  ~a"
             package
             (or found "unknown")
             (or wanted "unknown")
             root
             (update-advice package))]
    [_ #f]))

(define (rebuild-advice location)
  (match (native-location-kind location)
    ['package (update-advice (native-package))]
    ['override (format "rebuild the library ~a names, or unset it" compat-lib-env-var)]
    ['staged "rebuild it with `nix run .#copy-native-libs`, or delete it"]))

(define (unloadable-message location reason)
  (format "libcompat was found but would not load\n  found in: ~a\n  the loader said: ~a\n  ~a"
          (native-location-dir location)
          reason
          (rebuild-advice location)))

(define (missing-export-message location id)
  (format "libcompat lacks the export for ~a, so it is older than this polars\n  found in: ~a\n  ~a"
          id
          (native-location-dir location)
          (rebuild-advice location)))

(define (library-names dir)
  (~> (directory-list dir)
      (map path->string _)
      (filter (lambda (name) (regexp-match? #rx"^libcompat[.]" name)) _)
      (sort string<?)))

(define (manifest-files dir)
  (for/list ([name (in-list (library-names dir))])
    (cons name (sha256-hex (build-path dir name)))))

(define (irregular-file-problem package dir)
  (for/or ([name (in-list (library-names dir))]
           #:unless (eq? (file-or-directory-type (build-path dir name)) 'file))
    (format "~a in the package ~a is not a regular file\n  found in: ~a\n  ~a"
            name
            package
            dir
            (reinstall-advice package))))

(define (file-problem package dir listed actual)
  (for/or ([name (in-list (remove-duplicates (append (map car actual) (map car listed))))])
    (define want (dict-ref listed name #f))
    (define have (dict-ref actual name #f))
    (and (not (equal? want have))
         (format "~a in the package ~a ~a, but its manifest.json ~a\n  found in: ~a\n  ~a"
                 name
                 package
                 (if have (format "has sha256 ~a" have) "is missing")
                 (if want (format "says ~a" want) "does not list it")
                 dir
                 (reinstall-advice package)))))

(define (manifest-jsexpr dir native-version rust-tree commit)
  (hasheq 'native_version native-version
          'rust_tree rust-tree
          'commit commit
          'files (for/hasheq ([entry (in-list (manifest-files dir))])
                   (values (string->symbol (car entry)) (cdr entry)))))

(define (listed-files files)
  (for/list ([(name sha) (in-hash files)])
    (cons (symbol->string name) sha)))

(define (manifest-contents-problem package dir path wanted)
  (define manifest (call-with-input-file* path read-json))
  (define version (and (hash? manifest) (hash-ref manifest 'native_version #f)))
  (define files (and (hash? manifest) (hash-ref manifest 'files #f)))
  (cond
    [(not (and (string? version) (hash? files)))
     (format (string-append "the package ~a's manifest.json names no native_version and "
                            "files\n  found in: ~a\n  ~a")
             package
             path
             (reinstall-advice package))]
    [(not (equal? version wanted))
     (format (string-append "the package ~a's manifest.json is for native version ~a, "
                            "but this polars needs version ~a\n  found in: ~a\n  ~a")
             package
             version
             (or wanted "unknown")
             path
             (update-advice package))]
    [else
     (or (irregular-file-problem package dir)
         (file-problem package dir (listed-files files) (manifest-files dir)))]))

(define (manifest-problem location wanted)
  (match-define (native-location _ dir root _ _) location)
  (define package (native-package))
  (define path (build-path root "manifest.json"))
  (cond
    [(not (file-exists? path))
     (format (string-append "the package ~a has no manifest.json, so its libcompat cannot be "
                            "checked\n  looked in: ~a\n  ~a")
             package
             root
             (reinstall-advice package))]
    [else
     (with-handlers ([exn:fail:read?
                      (lambda (e)
                        (format (string-append "the package ~a's manifest.json is not JSON: "
                                               "~a\n  found in: ~a\n  ~a")
                                package
                                (exn-message e)
                                path
                                (reinstall-advice package)))])
       (manifest-contents-problem package dir path wanted))]))
