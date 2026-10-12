#lang racket/base

(module+ test
  (require rackunit
           (only-in racket/match match-define)
           (only-in racket/file delete-directory/files make-directory*
                    make-temporary-directory)
           (only-in polars/private/generic/core dataframe height series)
           (only-in polars/private/generic/io
                    read-csv read-ndjson read-parquet write-csv write-ndjson write-parquet)
           (only-in polars/private/generic/test-fixtures frame=?))

  (define dir (make-temporary-directory "rkt-polars-replace-~a"))
  (define (in-dir name) (build-path dir name))
  (define (entries [where dir])
    (sort (map path->string (directory-list where)) string<?))
  (define (message thunk)
    (with-handlers ([exn:fail? exn-message]) (thunk) #f))
  (define (mode path) (file-or-directory-permissions path 'bits))
  (define (x-frame xs) (dataframe (list (series xs #:name "x"))))
  (define frame (x-frame '(1 2 3)))
  (define small (x-frame '(7 8 9 10)))
  (define writers
    (list (list "csv" write-csv read-csv)
          (list "parquet" write-parquet read-parquet)
          (list "ndjson" write-ndjson read-ndjson)))

  (for ([w (in-list writers)])
    (match-define (list ext writer reader) w)
    (define kept (in-dir (string-append "kept." ext)))
    (writer frame kept)
    (file-or-directory-permissions kept #o600)
    (writer small kept)
    (check-equal? (mode kept) #o600 ext)
    (check-true (frame=? (reader kept) small) ext)

    (define long (in-dir (string-append (make-string (- 249 (string-length ext)) #\n) "." ext)))
    (writer frame long)
    (writer frame long)
    (check-true (frame=? (reader long) frame) ext)

    (writer frame "/dev/null")

    (define locked (in-dir (string-append "locked." ext)))
    (writer frame locked)
    (define before (call-with-input-file locked (lambda (in) (read-bytes 1000000 in))))
    (file-or-directory-permissions locked #o444)
    (define listed (entries))
    (define writable?
      (with-handlers ([exn:fail:filesystem? (lambda (_) #f)])
        (close-output-port (open-output-file locked #:exists 'update))
        #t))
    (unless writable?
      (check-regexp-match #rx": cannot create file: Permission denied [(]os error 13[)]$"
                          (message (lambda () (writer small locked))))
      (check-equal? (call-with-input-file locked (lambda (in) (read-bytes 1000000 in))) before)
      (check-equal? (entries) listed)))

  (define real (in-dir "real.csv"))
  (define soft (in-dir "soft.csv"))
  (write-csv frame real)
  (make-file-or-directory-link real soft)
  (write-csv small soft)
  (check-true (link-exists? soft))
  (check-true (frame=? (read-csv real) small))

  (define data (in-dir "data"))
  (make-directory data)
  (write-parquet frame (build-path data "a.parquet"))
  (copy-file (build-path data "a.parquet") (build-path data ".rkt-polars-1-0.partial"))
  (for ([source (list data (build-path data "*.parquet") (build-path data "*"))])
    (check-equal? (height (read-parquet source)) 3 (path->string source)))

  (define parent (in-dir "parent"))
  (define sub (build-path parent "sub"))
  (make-directory* sub)
  (for ([w (in-list writers)])
    (match-define (list _ writer _) w)
    (check-regexp-match #rx": cannot create file: Is a directory [(]os error 21[)]$"
                        (message (lambda () (writer frame sub))))
    (check-equal? (entries parent) '("sub")))

  (delete-directory/files dir))
