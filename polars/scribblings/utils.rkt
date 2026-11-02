#lang racket/base

;; Shared documentation helpers, modelled on racket-doc's
;; scribblings/reference/mz.rkt and scribblings/guide/guide-utils.rkt.
;;
;; Each chapter's preamble is then two lines:
;;
;;   #lang scribble/manual
;;   @(require "../utils.rkt")
;;
;; Three jobs:
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
;;  * Build the example evaluator.  Examples run against the real bindings at
;;    documentation-build time, so a printed frame cannot drift from what the
;;    library actually produces, and a broken example fails the build.  The
;;    library is an FFI wrapper, so the sandbox runs with the ambient security
;;    guard and without memory or time limits.

(require scribble/manual
         scribble/example
         (for-syntax racket/base (only-in syntax/parse id))
         (only-in racket/contract/base -> contract-out list/c or/c)
         (only-in racket/file file->lines)
         (only-in racket/list append-map take take-right)
         (only-in racket/match match)
         (only-in racket/sandbox
                  sandbox-error-output sandbox-eval-limits sandbox-memory-limit sandbox-output
                  sandbox-path-permissions sandbox-security-guard)
         (only-in scribble/core
                  block? make-element make-nested-flow make-paragraph make-style make-table)
         (only-in scribble/decode decode-content)
         (only-in scribble/html-properties attributes)
         (only-in syntax/parse/define define-syntax-parse-rule))

(require (for-label polars
                    ffi/vector
                    (only-in racket/contract/base
                             -> and/c any/c cons/c flat-contract? hash/c integer-in listof
                             non-empty-listof or/c)
                    (only-in threading ~> ~>>)
                    (except-in racket/base
                               min max sort filter reverse and or not when
                               + - * / > < >= <= = abs round floor sqrt exp log)))

(provide (all-from-out scribble/manual)
         (all-from-out scribble/example)
         (for-label (all-from-out polars ffi/vector racket/contract/base threading racket/base))
         make-polars-eval
         see-reference
         exnraise
         (contract-out
          [make-shell (-> #:directory path-string? (-> command/c command/c ... block?))]))

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

(define command/c
  (or/c (list/c (or/c 'head 'tail) relative-path?)
        (list/c (or/c 'head 'tail) relative-path? exact-nonnegative-integer?)))

(define default-lines 5)

(define ((make-shell #:directory directory) . commands)
  (terminal (append-map (lambda (command) (command->lines directory command)) commands)))

(define (command->lines directory command)
  (match command
    [(list verb file) (command->lines directory (list verb file default-lines))]
    [(list verb file n)
     (define lines (file->lines (build-path directory file) #:line-mode 'linefeed))
     (define pick (match verb ['head take] ['tail take-right]))
     (cons (format "$ ~a -n ~a ~a" verb n file)
           (pick lines (min n (length lines))))]))

(define terminal-style
  (make-style 'code-inset (list (attributes '((style . "overflow-x: auto"))))))
(define terminal-lines-style
  (make-style "SVerbatim" (list (attributes '((style . "white-space: pre"))))))
(define row-style (make-style 'omitable null))

(define (terminal lines)
  (make-nested-flow terminal-style (list (make-table terminal-lines-style (map row lines)))))

(define (row line)
  (list (make-paragraph row-style (list (make-element 'tt (list (blank->space line)))))))

(define (blank->space line)
  (cond
    [(string=? line "") " "]
    [else line]))
