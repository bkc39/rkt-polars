#lang racket/base

;; Shared documentation helpers, modelled on racket-doc's
;; scribblings/reference/mz.rkt and scribblings/guide/guide-utils.rkt.
;;
;; Each chapter's preamble is then two lines:
;;
;;   #lang scribble/manual
;;   @(require "../utils.rkt")
;;
;; Four jobs:
;;
;;  * Re-export `scribble/manual` and `scribble/example` so chapters do not
;;    repeat them.
;;
;;  * Re-provide the `for-label` imports every chapter needs.  polars
;;    re-exports generic operations that shadow racket/base (min, max, filter,
;;    the arithmetic and comparison operators, ...), so the shadowing dance is
;;    written once here rather than copied into each .scrbl file; without it
;;    `@racket[...]` does not hyperlink to the right binding.
;;
;;  * Show a data file's first or last lines as `head` or `tail` prints them,
;;    read at documentation-build time like the examples.
;;
;;  * Build the example evaluator.  Examples run against the real bindings at
;;    documentation-build time, so a printed frame cannot drift from what the
;;    library actually produces, and a broken example fails the build.  The
;;    library is an FFI wrapper, so the sandbox runs with the ambient security
;;    guard and without memory or time limits.

(require scribble/manual
         scribble/example
         scribble/core
         scribble/decode
         racket/sandbox
         (only-in racket/contract/base ->* contract-out)
         (only-in racket/file file->lines)
         (only-in racket/list take-right)
         scribble/html-properties
         syntax/parse/define
         (for-syntax racket/base))

(require (for-label polars
                    ffi/vector
                    (only-in racket/contract/base
                             -> and/c any/c cons/c hash/c integer-in listof non-empty-listof
                             or/c)
                    (only-in racket/string non-empty-string?)
                    (only-in threading ~> ~>>)
                    (except-in racket/base
                               min max sort filter reverse and or not when
                               + - * / > < >= <= = abs round floor sqrt exp log)))

(provide (all-from-out scribble/manual)
         (all-from-out scribble/example)
         (for-label (all-from-out polars ffi/vector racket/contract/base racket/string threading
                                  racket/base))
         make-polars-eval
         see-reference
         exnraise
         (contract-out
          [shell-head (->* (relative-path? #:directory path-string?) (exact-nonnegative-integer?)
                           block?)]
          [shell-tail (->* (relative-path? #:directory path-string?) (exact-nonnegative-integer?)
                           block?)]))

(define (make-polars-eval #:directory [directory (current-directory)])
  (parameterize ([current-directory directory]
                 [sandbox-output 'string]
                 [sandbox-error-output 'string]
                 [sandbox-memory-limit #f]
                 [sandbox-eval-limits #f]
                 [sandbox-security-guard current-security-guard]
                 [sandbox-path-permissions '((exists "/"))])
    (make-base-eval '(require gregor
                              polars
                              (only-in threading ~> ~>>)))))

;; "the @exnraise[exn:fail:contract]" => "the `exn:fail:contract` exception is
;; raised", after mz.rkt.
(define (*exnraise s)
  (make-element #f (list s " exception is raised")))
(define-syntax-parse-rule (exnraise s:id)
  (*exnraise (racket s)))

;; A margin note pointing from a guide chapter into the reference, after
;; guide-utils.rkt's `refdetails`.
(define (see-reference tag . what)
  (apply margin-note
         (decode-content (append (list "See " (secref tag) " for ")
                                 what
                                 (list ".")))))

;; Invalid UTF-8 reads as U+FFFD, as a UTF-8 terminal shows it; tabs stay
;; tabs, and the block keeps them with `white-space: pre`.
(define (shell-head file [n 5] #:directory directory)
  (terminal (format "head -n ~a ~a" n file)
            (call-with-input-file (build-path directory file)
              (lambda (in)
                (for/list ([line (in-lines in 'linefeed)]
                           [_ (in-range n)])
                  line)))))

(define (shell-tail file [n 5] #:directory directory)
  (define lines (file->lines (build-path directory file) #:line-mode 'linefeed))
  (terminal (format "tail -n ~a ~a" n file)
            (take-right lines (min n (length lines)))))

(define terminal-style
  (make-style 'code-inset (list (attributes '((style . "overflow-x: auto"))))))
(define terminal-lines-style
  (make-style "SVerbatim" (list (attributes '((style . "white-space: pre"))))))

(define (terminal command lines)
  (make-nested-flow
   terminal-style
   (list (make-table terminal-lines-style
                     (for/list ([line (cons (string-append "$ " command) lines)])
                       (list (make-paragraph (make-style 'omitable null)
                                             (list (make-element 'tt (list (nonempty line)))))))))))

(define (nonempty line)
  (cond
    [(string=? line "") " "]
    [else line]))
