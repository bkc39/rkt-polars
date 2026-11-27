#lang racket/base

(require syntax/parse/define
         (for-syntax racket/base syntax/parse))

(provide define-facade)

(begin-for-syntax
  (define-syntax-class part
    #:description "a part's module path, or an except-in of one"
    #:attributes (mod spec)
    (pattern mod:id #:with spec #'mod)
    (pattern ((~literal except-in) mod:id _:id ...) #:with spec this-syntax)))

(define-syntax-parse-rule (define-facade #:parts (part:part ...)
                            (~optional (~seq #:hide (hidden:id ...)))
                            #:internal-parts (inner:id ...)
                            (~optional (~seq #:hide-internal (hidden-inner:id ...))))
  #:with (inner-spec ...) (for/list ([mod (in-list (syntax->list #'(inner ...)))])
                            (datum->syntax mod (list 'submod mod 'internal) mod))
  (begin
    (require part.spec ...)
    (provide (except-out (all-from-out part.mod ...) (~? (~@ hidden ...))))
    (module+ internal
      (require inner-spec ...)
      (provide (except-out (all-from-out inner-spec ...)
                           (~? (~@ hidden-inner ...)))))))
