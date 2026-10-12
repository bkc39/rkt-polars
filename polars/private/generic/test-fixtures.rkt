#lang racket/base

;; Shared fixtures for the polars/private/generic/* test submodules.  Requires
;; the wrapper core directly (not the aggregator) so a test submodule can depend
;; on it without a module cycle; re-exports the handful of low-level names the
;; tests reach for (col / Expr-ptr? / expr-add / polars-null? / datetime).

(require polars/private/generic/core
         polars/private/test-helpers
         (only-in polars/private/expr col Expr-ptr? expr-add)
         (only-in polars/private/foreign polars-null polars-null?)
         (only-in gregor datetime))

(provide (all-defined-out)
         (all-from-out polars/private/test-helpers)
         col Expr-ptr? expr-add polars-null polars-null? datetime)

(define ints   (series '(1 2 3 4) #:name "ints" #:dtype 'i32))
(define floats (series '(1.5 2.0 4.25 8.0) #:name "floats"))
(define withnull (series (list 10 polars-null 30) #:dtype 'i32))

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

(define (dtypes-of df)
  (for/list ([name (in-list (column-names df))])
    (list name (dtype (ref df name)))))

(module+ test
  (require rackunit
           (only-in racket/file delete-directory/files file->string make-temporary-directory))

  (provide check-staged-write)

  (define (check-staged-write write! ext df)
    (define dir (make-temporary-directory "rkt-polars-staged-~a"))
    (define (named stem) (format "~a.~a" stem ext))
    (define (failure cause)
      (pregexp (format "^~a: failed to write [^ ]+ to [^:]*: cannot create file: ~a"
                       (object-name write!) cause)))
    (define real (scratch-file dir (named "real") "OLD"))
    (define link (build-path dir (named "link")))
    (make-file-or-directory-link (named "real") link)
    (write! df link)
    (check-true (link-exists? link))
    (check-not-equal? (file->string real) "OLD")
    (define locked (scratch-file dir (named "locked") "OLD"))
    (file-or-directory-permissions locked #o444)
    (unless (memq 'write (file-or-directory-permissions locked))
      (check-exn (failure "Permission denied") (lambda () (write! df locked)))
      (check-equal? (file->string locked) "OLD"))
    (define private (scratch-file dir (named "private") "OLD"))
    (file-or-directory-permissions private #o600)
    (write! df private)
    (check-equal? (file-or-directory-permissions private 'bits) #o600)
    (write! df "/dev/null")
    (define long (build-path dir (named (make-string (- 249 (string-length ext)) #\x))))
    (write! df long)
    (check-true (file-exists? long))
    (define sub (build-path dir "sub"))
    (make-directory sub)
    (check-exn (failure "it is a directory$") (lambda () (write! df sub)))
    (check-equal? (staging-files dir) '())
    (check-equal? (directory-list sub) '())
    (delete-directory/files dir)))
