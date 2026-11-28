#lang racket/base

(require racket/contract/base)

(provide
 (contract-out
  [dataframe-clause-migrations refactoring-suite?]))

(require (for-label (only-in polars dataframe series))
         (only-in racket/list append-map check-duplicates filter-not)
         racket/match
         resyntax/base
         syntax/parse)

(define (bound-to? id label)
  (and (identifier? id) (free-identifier=? id label 0 #f)))

(define (bracketed? stx)
  (eqv? (syntax-property stx 'paren-shape) #\[))

(define (keyword-pairs stx)
  (syntax-parse stx
    [((~seq kw:keyword e:expr) ...) (map cons (attribute kw) (attribute e))]
    [_ #f]))

(define (keyword-named? pairs name)
  (and pairs (for/or ([pair (in-list pairs)]) (eq? (syntax-e (car pair)) name))))

(define-syntax-class literal
  #:literals (quote)
  (pattern (~or* _:str _:number _:boolean _:char (quote _))))

(define-syntax-class list-call
  #:attributes ([element 1])
  (pattern (head:id element ...)
    #:when (free-identifier=? #'head #'list 0 0)))

(define-syntax-class clause-shaped
  (pattern part
    #:when (bracketed? #'part))
  (pattern (_:str . _))
  (pattern (_:expr . options)
    #:when (keyword-named? (keyword-pairs #'options) '#:name)))

(struct convertible (values name pairs))

(define (series-arguments args)
  (let loop ([args args] [before '()] [vals #f] [pairs '()])
    (match args
      ['() (and vals
                (assq '#:name pairs)
                (convertible vals (cdr (assq '#:name pairs)) (reverse pairs)))]
      [(list* kw e rest)
       #:when (keyword? (syntax-e kw))
       (define key (syntax-e kw))
       (and (memq key '(#:name #:dtype))
            (not (assq key pairs))
            (loop rest (if vals before (cons e before)) vals (cons (cons key e) pairs)))]
      [(cons v rest)
       (and (not vals)
            (syntax-parse #`(#,@before)
              [(_:literal ...) #t]
              [_ #f])
            (loop rest before v pairs))])))

(define (series-call stx)
  (syntax-parse stx
    [(head:id arg ...)
     #:when (bound-to? #'head #'series)
     (define found (series-arguments (attribute arg)))
     (and found
          (syntax-parse (convertible-name found)
            #:literals (quote)
            [(quote _) #f]
            [_ found]))]
    [_ #f]))

(define (name-identifier name context)
  (define text (syntax-e name))
  (define symbol (and (string? text) (string->symbol text)))
  (and symbol
       (for/and ([c (in-string text)]) (char-graphic? c))
       (equal? (format "~s" symbol) text)
       (not (identifier-binding (datum->syntax context symbol) 0))
       (datum->syntax #f symbol)))

(define (clause context found)
  (match-define (convertible vals name pairs) found)
  (define (spelled pairs)
    (append-map (lambda (pair) (list (datum->syntax #f (car pair)) (cdr pair))) pairs))
  (define options (spelled (filter-not (lambda (pair) (eq? (car pair) '#:name)) pairs)))
  (define elements
    (cond
      [(name-identifier name context) => (lambda (id) (list* id vals options))]
      [(string? (syntax-e name)) (list* name vals options)]
      [else (cons vals (spelled pairs))]))
  (syntax-property (datum->syntax #f elements) 'paren-shape #\[))

(define (literal-name found)
  (define text (syntax-e (convertible-name found)))
  (and (string? text) text))

(define-syntax-class spliceable-list
  #:attributes ([element 1])
  (pattern (~and :list-call (_ (~not :clause-shaped) ...))))

(define (spliceable? part)
  (syntax-parse part
    [:spliceable-list #t]
    [_ #f]))

(define (spliced parts)
  (append-map (lambda (part)
                (syntax-parse part
                  [:spliceable-list (attribute element)]
                  [_ (list part)]))
              parts))

(define (existing-name part context)
  (syntax-parse part
    #:literals (quote)
    [(~not :clause-shaped) #f]
    [(text:str . _) (syntax-e #'text)]
    [(head:id _ . _)
     #:when (not (identifier-binding (datum->syntax context (syntax-e #'head)) 0))
     (symbol->string (syntax-e #'head))]
    [(_ . options)
     (for/first ([pair (in-list (or (keyword-pairs #'options) '()))]
                 #:when (eq? (syntax-e (car pair)) '#:name))
       (syntax-parse (cdr pair)
         #:literals (quote)
         [text:str (syntax-e #'text)]
         [(quote name:id) (symbol->string (syntax-e #'name))]
         [_ #f]))]))

(define (migrated context parts)
  (define flat (spliced parts))
  (define converted (map series-call flat))
  (define names
    (for/list ([part (in-list flat)] [found (in-list converted)])
      (if found (literal-name found) (existing-name part context))))
  (and (or (ormap spliceable? parts) (ormap values converted))
       (not (check-duplicates (filter values names)))
       (for/list ([part (in-list flat)] [found (in-list converted)])
         (if found (clause context found) part))))

(define-refactoring-rule dataframe-list-to-clauses
  #:description "Write the dataframe's columns as clauses, `[name values option ...]` or `[values #:name name option ...]`, and splice a `(list ...)` of series into the form."
  (head:id part ...)
  #:when (bound-to? #'head #'dataframe)
  #:do [(define new-parts (migrated this-syntax (attribute part)))]
  #:when new-parts
  #:with (new-part ...) new-parts
  (head new-part ...))

(define-refactoring-suite dataframe-clause-migrations
  #:rules (dataframe-list-to-clauses))
