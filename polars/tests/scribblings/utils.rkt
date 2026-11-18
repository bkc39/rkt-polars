#lang racket/base

(module+ test
  (require rackunit
           (only-in racket/match match-lambda)
           (only-in (submod polars/scribblings/utils internal) call-in-temporary-directory))

  (define (directory-evaluator start)
    (define dir start)
    (match-lambda
      [`(current-directory) dir]
      [`(current-directory ,path) (set! dir (string->path path))]))

  (define start (current-directory))

  (test-case "the forms run in a fresh directory, and the evaluator's comes back"
    (define ev (directory-evaluator start))
    (define inside
      (call-in-temporary-directory ev
                                   (lambda ()
                                     (check-true (directory-exists? (ev '(current-directory))))
                                     (ev '(current-directory)))))
    (check-not-equal? inside start)
    (check-equal? (ev '(current-directory)) start)
    (check-false (directory-exists? inside)))

  (test-case "a raise restores the evaluator's directory and deletes the temporary one"
    (define ev (directory-evaluator start))
    (define inside #f)
    (check-exn #rx"an example raised"
               (lambda ()
                 (call-in-temporary-directory ev
                                              (lambda ()
                                                (set! inside (ev '(current-directory)))
                                                (error "an example raised")))))
    (check-equal? (ev '(current-directory)) start)
    (check-false (directory-exists? inside))))
