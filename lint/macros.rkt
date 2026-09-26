#lang racket/base

(require racket/contract/base)

(provide
 (contract-out
  [syntax-parse-migrations refactoring-suite?]))

(require resyntax/base
         syntax/parse
         syntax/parse/define)

;; Where syntax-parse reads a define-syntax-rule pattern differently, the
;; pattern is left alone: `a:b` is a syntax-class annotation, a `~` prefix a
;; pattern keyword, `...+` one-or-more, `(... ...)` is not allowed, and an
;; ellipsis before a dotted tail matches greedily where syntax-rules matches
;; to the end of the list.
(define (portable-name? id)
  (define name (symbol->string (syntax-e id)))
  (not (or (regexp-match? #rx":" name)
           (regexp-match? #rx"^~" name)
           (equal? name "...+"))))

(define (ellipsis? stx)
  (and (identifier? stx) (eq? (syntax-e stx) '...)))

(define (portable-pattern? stx)
  (syntax-parse stx
    [x:id (portable-name? #'x)]
    [(head . _) #:when (ellipsis? #'head) #f]
    [(p ...) (andmap portable-pattern? (attribute p))]
    [(p ...+ . tail)
     (and (not (ormap ellipsis? (attribute p)))
          (andmap portable-pattern? (attribute p))
          (portable-pattern? #'tail))]
    [#(p ...) (andmap portable-pattern? (attribute p))]
    [(~or* :number :str :keyword :boolean :char) #t]
    [_ #f]))

;; define-syntax-parse-rule binds the macro's name as a pattern variable, so a
;; use of the name inside the macro would become whatever identifier the
;; caller wrote.
(define (mentions? stx name)
  (let loop ([e (syntax->datum stx)])
    (cond
      [(pair? e) (or (loop (car e)) (loop (cdr e)))]
      [(vector? e) (loop (vector->list e))]
      [(box? e) (loop (unbox e))]
      [(prefab-struct-key e) (loop (struct->vector e))]
      [else (eq? e name)])))

(define (portable-rule? name pattern template)
  (and (portable-name? name)
       (portable-pattern? pattern)
       (not (mentions? pattern (syntax-e name)))
       (not (mentions? template (syntax-e name)))
       (not (keyword? (syntax-e template)))))

(define (parse-rule-bound-at? id)
  (free-identifier=? (datum->syntax id 'define-syntax-parse-rule) #'define-syntax-parse-rule))

(define parse-rule-description
  "Use `define-syntax-parse-rule` from `syntax/parse/define`: its pattern variables can carry syntax classes (`name:id`, `e:expr`), which check each use and report the part that failed at the use site. Require the whole module, `(require syntax/parse/define)`: it also provides the syntax classes, which an `only-in` of `define-syntax-parse-rule` leaves unbound.")

(define-refactoring-rule define-syntax-rule-to-define-syntax-parse-rule
  #:description parse-rule-description
  #:literals (define-syntax-rule)
  ((~and head define-syntax-rule) (~and header (name:id . pattern)) template)
  #:when (parse-rule-bound-at? #'head)
  #:when (portable-rule? #'name #'pattern #'template)
  ((~focus-replacement-on define-syntax-parse-rule) header template))

(define-refactoring-rule define-syntax-syntax-rules-to-define-syntax-parse-rule
  #:description parse-rule-description
  #:literals (define-syntax syntax-rules)
  ((~and head define-syntax) name:id (syntax-rules () [((~datum _) . pattern) template]))
  #:when (parse-rule-bound-at? #'head)
  #:when (portable-rule? #'name #'pattern #'template)
  (define-syntax-parse-rule (name . pattern) template))

(define-refactoring-suite syntax-parse-migrations
  #:rules (define-syntax-rule-to-define-syntax-parse-rule
           define-syntax-syntax-rules-to-define-syntax-parse-rule))
