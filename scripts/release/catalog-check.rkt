#lang racket/base

(require (only-in ffi/unsafe _fun _path _uint32 get-ffi-obj)
         (only-in file/sha1 bytes->hex-string)
         (only-in json read-json)
         (only-in net/url string->url)
         (only-in racket/file file->lines)
         (only-in racket/lazy-require lazy-require)
         (only-in racket/list remove-duplicates)
         (only-in racket/match match)
         (only-in racket/path normalize-path)
         (only-in racket/string string-join)
         (only-in pkg/lib
                  current-pkg-catalogs current-pkg-error get-pkg-details-from-catalogs pkg-directory)
         (only-in setup/getinfo get-info/full))

(lazy-require [polars
               ((col pl:col)
                (dataframe pl:dataframe)
                (filter pl:filter)
                (ref pl:ref)
                (series pl:series)
                (series->list pl:series->list)
                (> pl:>))])

(define library-file (string-append "libcompat" (bytes->string/utf-8 (system-type 'so-suffix))))

(define (check ok? pass fail)
  (printf "~a ~a\n" (if ok? "ok  " "FAIL") (if ok? pass fail))
  (if ok?
      '()
      (list fail)))

(define (catalog-entry name)
  (let/ec absent
    (parameterize ([current-pkg-error (lambda _ (absent #f))])
      (get-pkg-details-from-catalogs name))))

(define (dependency-name dependency)
  (match dependency
    [(cons name _) name]
    [name name]))

(define (in-catalogs package catalogs)
  (define where (string-join catalogs " "))
  (define-values (polars native)
    (parameterize ([current-pkg-catalogs (map string->url catalogs)])
      (values (catalog-entry "polars") (catalog-entry package))))
  (define (listed name entry)
    (check entry
           (format "~a is in ~a, from ~a" name where (and entry (hash-ref entry 'source #f)))
           (format (string-append "~a is absent from ~a: register it there"
                                  " (polars/native-libs/BUILDING.md, Release checklist)")
                   name
                   where)))
  (append (listed "polars" polars)
          (listed package native)
          (match polars
            [#f '()]
            [(hash* ['source source] ['dependencies dependencies #:default '()])
             (check (member package (map dependency-name dependencies))
                    (format "the catalog's polars depends on ~a" package)
                    (format "the catalog's polars, from ~a, does not depend on ~a" source package))])))

(define (canonical path)
  (if (file-exists? path)
      (normalize-path path)
      (simplify-path path)))

(define (mapped-paths lines name)
  (define suffix (regexp (string-append "/" (regexp-quote name) "$")))
  (remove-duplicates (for*/list ([line (in-list lines)]
                                 [found (in-value (regexp-match #rx"/.*$" line))]
                                 #:when (and found (regexp-match? suffix (car found))))
                       (canonical (car found)))))

(define (mapped-once lines library)
  (define-values (dir name _) (split-path library))
  (define paths (mapped-paths lines (path->string name)))
  (check (equal? paths (list (canonical library)))
         (format "~a is mapped once, from ~a" name dir)
         (format "~a is mapped from ~a, not once from ~a"
                 name
                 (if (null? paths)
                     "nowhere"
                     (string-join (map path->string paths) ", "))
                 dir)))

(define (dyld-images)
  (define count (get-ffi-obj "_dyld_image_count" #f (_fun -> _uint32)))
  (define image-name (get-ffi-obj "_dyld_get_image_name" #f (_fun _uint32 -> _path)))
  (for/list ([i (in-range (count))])
    (path->string (image-name i))))

(define (loaded-images)
  (match (system-type 'os*)
    ['linux (file->lines "/proc/self/maps")]
    ['macosx (dyld-images)]
    [os (raise-user-error 'catalog-check "no way to list the loaded libraries on ~a" os)]))

(define (file-sha256 path)
  (call-with-input-file path (lambda (in) (bytes->hex-string (sha256-bytes in)))))

(define (library-files dir)
  (if (directory-exists? dir)
      (for/hash ([name (in-list (directory-list dir))]
                 #:when (regexp-match? #rx"^libcompat[.]" (path->string name)))
        (values (path->string name) (file-sha256 (build-path dir name))))
      (hash)))

(define (read-manifest path)
  (call-with-input-file path read-json))

(define (manifest-files manifest)
  (for/hash ([(name sha) (in-hash (hash-ref manifest 'files (hash)))])
    (values (symbol->string name) sha)))

(define (describe files)
  (if (hash-empty? files)
      "nothing"
      (string-join (for/list ([(name sha) (in-hash files)])
                     (format "~a ~a" name sha))
                   ", ")))

(define (matches-manifest manifest-path dir)
  (define listed (manifest-files (read-manifest manifest-path)))
  (define found (library-files dir))
  (check (and (not (hash-empty? listed)) (equal? found listed))
         (format "~a holds the libraries ~a lists: ~a" dir manifest-path (describe listed))
         (format "~a holds ~a, but ~a lists ~a" dir (describe found) manifest-path (describe listed))))

(define (matches-release manifest-path release)
  (define released (build-path release "manifest.json"))
  (append (check (equal? (read-manifest manifest-path) (read-manifest released))
                 (format "~a is the published Release's manifest.json" manifest-path)
                 (format "~a differs from the published Release's ~a" manifest-path released))
          (matches-manifest manifest-path (build-path release "native-libs"))))

(define (info-ref dir key)
  (define info (get-info/full dir))
  (and info (info key (lambda () #f))))

(define (round-trip)
  (define kept
    (pl:filter (pl:dataframe (list (pl:series '(1 2 3) #:name "v"))) (pl:> (pl:col "v") 1)))
  (define got (pl:series->list (pl:ref kept "v")))
  (check (equal? got '(2 3))
         "a filter of v > 1 over 1, 2, 3 keeps 2, 3"
         (format "a filter of v > 1 over 1, 2, 3 kept ~a" got)))

(define (installed-package package root polars-dir release)
  (define libs (simplify-path (dynamic-require (string->symbol package) 'native-libs-dir)))
  (define manifest (build-path root "manifest.json"))
  (define version (info-ref root 'version))
  (define native-version (info-ref polars-dir 'native-version))
  (define staged (build-path polars-dir "native-libs"))
  (append (mapped-once (loaded-images) (build-path libs library-file))
          (check (hash-empty? (library-files staged))
                 (format "nothing is staged in ~a" staged)
                 (format "~a holds ~a" staged (describe (library-files staged))))
          (check (equal? version native-version)
                 (format "~a is version ~a, polars' native-version" package version)
                 (format "~a is version ~a, but polars' native-version is ~a"
                         package
                         version
                         native-version))
          (matches-manifest manifest libs)
          (matches-release manifest release)
          (round-trip)))

(define (installed package release)
  (dynamic-require 'polars #f)
  (define polars-dir (pkg-directory "polars"))
  (printf "polars ~a loaded from ~a\n" (info-ref polars-dir 'version) polars-dir)
  (match (pkg-directory package)
    [#f (check #f "" (format "~a is not installed, so polars did not pull it" package))]
    [root (installed-package package root polars-dir release)]))

(module+ main
  (define failures
    (match (current-command-line-arguments)
      [(vector "catalog" package catalogs ..1) (in-catalogs package catalogs)]
      [(vector "installed" package release) (installed package release)]
      [(vector "mapped" listing library) (mapped-once (file->lines listing) library)]
      [(vector "manifest" manifest dir) (matches-manifest manifest dir)]
      [(vector "release" manifest release) (matches-release manifest release)]
      [_
       (raise-user-error 'catalog-check
                         (string-append "usage: catalog-check.rkt catalog PACKAGE CATALOG..."
                                        " | installed PACKAGE RELEASE-DIR"
                                        " | mapped LISTING LIBRARY"
                                        " | manifest MANIFEST.json DIR"
                                        " | release MANIFEST.json RELEASE-DIR"))]))
  (exit (if (null? failures) 0 1)))
