#lang racket/base

(require racket/contract/base)

(provide
 (contract-out
  [syntax-parse-migrations refactoring-suite?]))

(require racket/match
         racket/string
         resyntax/base
         syntax/parse
         syntax/parse/define)

(define-syntax-class ellipsis
  (pattern x:id
    #:when (or (eq? (syntax-e #'x) '...)
               (free-identifier=? #'x (quote-syntax ...)))))

;; Where syntax-parse reads a define-syntax-rule pattern differently, the
;; pattern is left alone: `a:b` is a syntax-class annotation, a `~` prefix a
;; pattern keyword, `...+` one-or-more, `(... ...)` is not allowed, and an
;; ellipsis before a dotted tail matches greedily where syntax-rules matches
;; to the end of the list.
(define-syntax-class portable-id
  (pattern (~and x:id (~not :ellipsis))
    #:do [(define name (symbol->string (syntax-e #'x)))]
    #:when (not (or (string-contains? name ":")
                    (string-prefix? name "~")
                    (equal? name "...+")))))

(define-syntax-class portable-pattern
  (pattern :portable-id)
  (pattern ())
  (pattern (:portable-pattern (~or* :ellipsis :portable-pattern) ...))
  (pattern (:portable-pattern ...+ . :portable-pattern))
  (pattern #((~or* :ellipsis :portable-pattern) ...))
  (pattern (~or* :number :str :keyword :boolean :char)))

;; define-syntax-rule gives the outermost form of each expansion the use
;; site's location, and define-syntax-parse-rule keeps the template's.  A
;; lambda's inferred name and a rackunit check's reported line show it.
(define-syntax-class location-observing-head
  (pattern x:id
    #:do [(define name (symbol->string (syntax-e #'x)))]
    #:when (or (member name '("lambda" "λ" "case-lambda" "check"))
               (string-prefix? name "check-")
               (string-prefix? name "test-"))))

(define-syntax-class location-free-template
  (pattern (~and :expr (~not (:location-observing-head . _)))))

;; define-syntax-parse-rule binds the macro's name as a pattern variable, so a
;; use of the name inside the macro would become whatever identifier the
;; caller wrote.
(define (mentions? stx name)
  (let loop ([e (syntax->datum stx)])
    (match e
      [(cons head tail) (or (loop head) (loop tail))]
      [(? vector?) (loop (vector->list e))]
      [(box contents) (loop contents)]
      [(? prefab-struct-key) (loop (struct->vector e))]
      [_ (eq? e name)])))

(define (parse-rule-bound-at? id)
  (free-identifier=? (datum->syntax id 'define-syntax-parse-rule) #'define-syntax-parse-rule))

(define parse-rule-description
  "Use `define-syntax-parse-rule` from `syntax/parse/define`: its pattern variables can carry syntax classes (`name:id`, `e:expr`), which check each use and report the part that failed at the use site. Require the whole module, `(require syntax/parse/define)`: it also provides the syntax classes, which an `only-in` of `define-syntax-parse-rule` leaves unbound.")

(define-refactoring-rule define-syntax-rule-to-define-syntax-parse-rule
  #:description parse-rule-description
  #:literals (define-syntax-rule)
  ((~and head define-syntax-rule)
   (~and header (name:portable-id . pattern:portable-pattern))
   template:location-free-template)
  #:when (parse-rule-bound-at? #'head)
  #:when (not (mentions? #'(pattern template) (syntax-e #'name)))
  ((~focus-replacement-on define-syntax-parse-rule) header template))

(define-refactoring-rule define-syntax-syntax-rules-to-define-syntax-parse-rule
  #:description parse-rule-description
  #:literals (define-syntax syntax-rules)
  ((~and head define-syntax)
   name:portable-id
   (syntax-rules ()
     [((~datum _) . pattern:portable-pattern) template:location-free-template]))
  #:when (parse-rule-bound-at? #'head)
  #:when (not (mentions? #'(pattern template) (syntax-e #'name)))
  (define-syntax-parse-rule (name . pattern) template))

(define-refactoring-suite syntax-parse-migrations
  #:rules (define-syntax-rule-to-define-syntax-parse-rule
           define-syntax-syntax-rules-to-define-syntax-parse-rule))
