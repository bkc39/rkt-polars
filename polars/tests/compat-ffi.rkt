#lang racket/base

(module+ test
  (require rackunit
           (only-in racket/match match-define))

  (define (compat-namespace)
    (parameterize ([current-namespace (make-base-namespace)])
      (namespace-require 'ffi/unsafe)
      (namespace-require '(only polars/private/compat-ffi define-compat))
      (current-namespace)))

  (define (define-compat-result form)
    (match-define (list 'define-compat name _ ...) form)
    (parameterize ([current-namespace (compat-namespace)])
      (eval form)
      (eval `(object-name ,name))))

  (define (define-compat-refusal form)
    (parameterize ([current-namespace (compat-namespace)])
      (with-handlers ([exn:fail:syntax? exn-message])
        (eval form)
        #f)))

  (test-case "a binding's procedure takes the binding's name, after its #:wrap"
    (check-equal? (define-compat-result '(define-compat drops (_fun -> _size)
                                           #:c-id str_block_drop_count))
                  'drops)
    (check-equal? (define-compat-result '(define-compat drops (_fun -> _size)
                                           #:wrap (lambda (f) (lambda () (f)))
                                           #:c-id str_block_drop_count))
                  'drops))

  (test-case "define-compat names the option it refuses"
    (check-regexp-match
     #rx"^define-compat: expected one of these literals: #:c-id or #:wrap\n  at: #:blocking[?]"
     (define-compat-refusal '(define-compat drops (_fun -> _size) #:blocking? #t)))
    (check-regexp-match
     #rx"^define-compat: too many occurrences of the #:wrap option"
     (define-compat-refusal '(define-compat drops (_fun -> _size) #:wrap values #:wrap values)))
    (check-regexp-match
     #rx"^define-compat: too many occurrences of the #:c-id option"
     (define-compat-refusal '(define-compat drops (_fun -> _size)
                               #:c-id str_block_drop_count #:c-id str_block_drop)))
    (check-regexp-match
     #rx"^define-compat: expected identifier for the C symbol\n  at: \"str_block_drop\""
     (define-compat-refusal '(define-compat drops (_fun -> _size) #:c-id "str_block_drop")))))
