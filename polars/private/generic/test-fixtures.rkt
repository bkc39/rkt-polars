#lang racket/base

;; Shared fixtures for the polars/private/generic/* test submodules.  Requires
;; the wrapper core directly (not the aggregator) so a test submodule can depend
;; on it without a module cycle; re-exports the handful of low-level names the
;; tests reach for (col / Expr-ptr? / expr-add / polars-null? / datetime).

(require polars/private/generic/core
         polars/private/test-helpers
         (only-in polars/private/expr col Expr-ptr? expr-add)
         (only-in polars/private/foreign
                  polars-null polars-null? series-cast series-new-i32 series-new-i64)
         (only-in gregor datetime))

(provide (all-defined-out)
         (all-from-out polars/private/test-helpers)
         col Expr-ptr? expr-add polars-null polars-null? datetime)

(define ints   (series '(1 2 3 4) #:name "ints" #:dtype 'i32))
(define floats (series '(1.5 2.0 4.25 8.0) #:name "floats"))
(define withnull (series (list 10 polars-null 30) #:dtype 'i32))

(define past-chrono-date (wrap-series (series-cast (series-new-i32 "d" '(2000000000)) 'date)))
(define past-chrono-datetime
  (wrap-series (series-cast (series-new-i64 "t" '(9223372036854775807))
                            '(datetime milliseconds #f))))

(define frame
  (dataframe (list (series '("alice" "bob" "carol") #:name "user")
                   (series '(10 25 18) #:name "score" #:dtype 'i32)
                   (series '(1.2 3.5 2.0) #:name "cost"))))

(define ops-df
  (dataframe (list (series '("a" "a" "b" "b" "c") #:name "group")
                   (series '(10 25 7 30 18) #:name "value" #:dtype 'i32)
                   (series '(1.2 2.4 0.5 3.1 1.8) #:name "cost"))))

(define v64 (series '(10 25 7 30 18) #:name "value"))   ; int64 (default)

(define (series-cells s)
  (for/list ([i (in-range (len s))]) (ref s i)))

(define (column d name)
  (series-cells (ref d #:columns name)))

(define (frame=? a b)
  (and (equal? (column-names a) (column-names b))
       (for/and ([name (in-list (column-names a))])
         (and (equal? (dtype (ref a #:columns name)) (dtype (ref b #:columns name)))
              (equal? (column a name) (column b name))))))

(define (cause-of message)
  (cadr (regexp-match #rx"^[^:]*: [^:]*: ([^\n]*)" message)))

(define (reads-agree? read scan collect path kvs)
  (define eager (with-handlers ([exn:fail? exn-message]) (apply-keywords read kvs path)))
  (define lazy (with-handlers ([exn:fail? exn-message]) (collect (apply-keywords scan kvs path))))
  (if (string? eager)
      (and (string? lazy) (equal? (cause-of eager) (cause-of lazy)))
      (and (not (string? lazy)) (frame=? eager lazy))))

(define (one-file-pattern path)
  (define-values (dir name _) (split-path path))
  (build-path dir (regexp-replace #rx"^." (path->string name) "[&]")))

(define (dtypes-of df)
  (for/list ([name (in-list (column-names df))])
    (list name (dtype (ref df name)))))

(module+ test
  (require rackunit
           (only-in racket/file delete-directory/files file->string make-temporary-directory))

  (provide check-staged-write)

  (define char-device #o020000)

  (define (check-staged-write write! read ext df)
    (define dir (make-temporary-directory "rkt-polars-staged-~a"))
    (define (named stem) (format "~a.~a" stem ext))
    (define (failure cause)
      (pregexp (format "^~a: failed to write [^ ]+ to [^:]*: cannot create file: ~a"
                       (object-name write!) cause)))
    (define (check-replaced path)
      (write! df path)
      (check-true (frame=? (read path) df) (format "~a" path)))
    (define real (scratch-file dir (named "real") "OLD"))
    (define link (build-path dir (named "link")))
    (make-file-or-directory-link (named "real") link)
    (check-replaced link)
    (check-true (link-exists? link))
    (check-true (frame=? (read real) df))
    (define locked (scratch-file dir (named "locked") "OLD"))
    (file-or-directory-permissions locked #o444)
    (unless (memq 'write (file-or-directory-permissions locked))
      (define listing (directory-list dir))
      (check-exn (failure "Permission denied") (lambda () (write! df locked)))
      (check-equal? (file->string locked) "OLD")
      (check-equal? (directory-list dir) listing))
    (define private (scratch-file dir (named "private") "OLD"))
    (file-or-directory-permissions private #o600)
    (check-replaced private)
    (check-equal? (file-or-directory-permissions private 'bits) #o600)
    (write! df "/dev/null")
    (check-equal? (bitwise-and (hash-ref (file-or-directory-stat "/dev/null") 'mode) #o170000)
                  char-device)
    (check-replaced (build-path dir (named (make-string (- 249 (string-length ext)) #\x))))
    (define sub (build-path dir "sub"))
    (make-directory sub)
    (check-exn (failure "it is a directory$") (lambda () (write! df sub)))
    (check-equal? (staging-files dir) '())
    (check-equal? (directory-list sub) '())
    (delete-directory/files dir)))
