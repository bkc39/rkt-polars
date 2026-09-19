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
         scribble/core
         scribble/decode
         racket/sandbox
         (for-syntax racket/base))

(require (for-label polars
                    (only-in threading ~> ~>>)
                    (except-in racket/base
                               min max sort filter reverse and or not when
                               + - * / > < >= <= = abs round floor sqrt exp log)))

(provide (all-from-out scribble/manual)
         (all-from-out scribble/example)
         (for-label (all-from-out polars threading racket/base))
         make-polars-eval
         see-reference
         exnraise)

(define (make-polars-eval)
  (parameterize ([sandbox-output 'string]
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
(define-syntax exnraise
  (syntax-rules ()
    [(_ s) (*exnraise (racket s))]))

;; A margin note pointing from a guide chapter into the reference, after
;; guide-utils.rkt's `refdetails`.
(define (see-reference tag . what)
  (apply margin-note
         (decode-content (append (list "See " (secref tag) " for ")
                                 what
                                 (list ".")))))
