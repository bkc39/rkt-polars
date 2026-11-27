#lang racket/base

(module column-options racket/base
  (provide column-option-keywords)
  (define column-option-keywords '(#:dtype)))

(require (only-in racket/contract/base
                  -> ->* ->i any contract define-module-boundary-contract
                  get/build-late-neg-projection listof or/c)
         (only-in racket/contract/combinator make-contract raise-blame-error)
         (only-in racket/list append-map check-duplicates)
         (only-in racket/match match match* match-define)
         syntax/location
         syntax/parse/define
         (for-syntax racket/base
                     (only-in racket/list check-duplicates)
                     (only-in racket/string string-join)
                     syntax/parse
                     (submod "." column-options))
         (only-in polars/private/foreign
                  dataframe-new/raw Series-ptr? series-drop series-len series-name)
         (only-in (submod polars/private/foreign internal) named series-cast-to series-slice/who)
         (only-in polars/private/resource utf-8-name/c with-release-pool)
         (only-in polars/private/dtype-spelling cast-target/c)
         (only-in polars/private/generic/core dataframe? wrap-dataframe)
         (only-in (submod polars/private/generic/core internal) series-of)
         (only-in polars/private/generic/dtype series-elements/c)
         (submod "." column-options))

(provide dataframe)

(define core-party (quote-module-name))

(define column-name/c (or/c symbol? utf-8-name/c))

(define column-part/c (or/c Series-ptr? (listof Series-ptr?)))

(define values-expectation
  "a list, vector, series or sequence, not a string, byte string, hash or number")

(define (sequence-elements blame vals neg)
  (for/list ([elements (in-values-sequence vals)])
    (match elements
      [(list element) element]
      [_ (raise-blame-error blame vals #:missing-party neg
                            '(expected: "~a" given: "~e") "a sequence of single values" vals)])))

(define (column-values/c dtype)
  (define elements-projection (get/build-late-neg-projection (series-elements/c dtype)))
  (make-contract
   #:name 'column-values/c
   #:late-neg-projection
   (lambda (blame)
     (define check-elements (elements-projection blame))
     (lambda (vals neg)
       (cond
         [(Series-ptr? vals) vals]
         [(or (list? vals) (vector? vals)) (check-elements vals neg)]
         [(and (sequence? vals) (not (or (string? vals) (bytes? vals) (hash? vals) (number? vals))))
          (check-elements (sequence-elements blame vals neg) neg)]
         [else (raise-blame-error blame vals #:missing-party neg
                                  '(expected: "~a" given: "~e") values-expectation vals)])))))

(struct column-request (name values dtype))

(define (make-column-request vals #:name name #:dtype [dtype #f])
  (column-request (if (symbol? name) (symbol->string name) name) vals dtype))

(define column-request/c
  (->i ([values (dtype) (column-values/c dtype)] #:name [name column-name/c])
       (#:dtype [dtype (or/c #f cast-target/c)])
       [_ column-request?]))

(define (column-clause-at srcloc party)
  (contract column-request/c make-column-request core-party party 'dataframe srcloc))

(define (column-part-at srcloc party)
  (contract (-> column-part/c any) values core-party party 'dataframe srcloc))

(define (frame-columns-problem columns)
  (define heights (map series-len columns))
  (define names (map series-name columns))
  (match* ((for/first ([h (in-list heights)] [n (in-list names)] #:unless (= h (car heights)))
             (list n h))
           (check-duplicates names))
    [((list name height) _)
     (format "could not create a new DataFrame: height of column '~a' (~a) does not match ~a"
             name height (format "height of column '~a' (~a)" (car names) (car heights)))]
    [(#f (? string? name))
     (format "could not create a new DataFrame: column with name '~a' has more than one occurrence"
             name)]
    [(#f #f) #f]))

(define (request->series who own request)
  (match-define (column-request name vals dtype) request)
  (cond
    [(not (Series-ptr? vals)) (own (series-of who vals name dtype))]
    [dtype ((named who name) (own (series-cast-to who vals dtype)))]
    [else ((named who name) (own (series-slice/who who vals 0 (series-len vals))))]))

(define (build-frame who parts)
  (with-release-pool ([own series-drop])
    (define columns
      (append-map (lambda (part)
                    (match part
                      [(? column-request?) (list (request->series who own part))]
                      [(? list?) part]
                      [_ (list part)]))
                  parts))
    (wrap-dataframe
     (or (dataframe-new/raw columns)
         (raise-arguments-error who (or (frame-columns-problem columns)
                                        "could not create a new DataFrame"))))))

(define columns->dataframe
  (let ()
    (define (dataframe . parts)
      (build-frame 'dataframe parts))
    dataframe))

(define-module-boundary-contract dataframe/contracted columns->dataframe
  (->* () #:rest (listof column-part/c) dataframe?)
  #:name-for-blame dataframe)

(define (top-level-variable? variable-reference name)
  (define absent (gensym 'absent))
  (not (eq? (namespace-variable-value name #f (lambda () absent)
                                      (variable-reference->namespace variable-reference))
            absent)))

(begin-for-syntax
  (define (head-binding id)
    (cond [(identifier-binding id 0 #t) 'bound]
          [(syntax-transforming-module-expression?) 'unbound]
          [else 'deferred]))

  (define (expanded-later?)
    (define context (syntax-local-context))
    (or (eq? context 'module) (pair? context)))

  (define (bracketed? stx)
    (eqv? (syntax-property stx 'paren-shape) #\[))

  (define (name-string stx)
    (syntax-parse stx
      #:literals (quote)
      [text:str (syntax-e #'text)]
      [name:id (symbol->string (syntax-e #'name))]
      [(quote name:id) (symbol->string (syntax-e #'name))]))

  (define option-keywords (cons '#:name column-option-keywords))

  (define option-list
    (string-join (map (lambda (kw) (format "~a" kw)) option-keywords) ", " #:before-last " and "))

  (define (name-option kws)
    (findf (lambda (kw) (eq? (syntax-e kw) '#:name)) kws))

  (define (unknown-option kws)
    (findf (lambda (kw) (not (memq (syntax-e kw) option-keywords))) kws))

  (define (repeated-option kws)
    (check-duplicates kws #:key syntax-e))

  (define (unknown-option-message kw)
    (format "~a is not a column option; the options are ~a" (syntax-e kw) option-list))

  (define (repeated-option-message kw)
    (format "~a appears twice in one column" (syntax-e kw)))

  (define (renamed-head-message head)
    (if (identifier? head)
        (format "~s has no binding here, so it names the column, and #:name cannot name it again"
                (syntax-e head))
        (format "~s names the column, so #:name cannot name it again" (syntax-e head))))

  (define (bound-head-message head)
    (define name (syntax-e head))
    (format (string-append "~s is bound here, so this bracketed clause is not a column; "
                           "name a column with #:name, as in [vals #:name '~s], "
                           "or with a string, as in [~s vals], "
                           "or drop the brackets for an expression")
            name name (symbol->string name)))

  (define bracketed-message
    (string-append "a bracketed clause is a column, [vals #:name name option ...] "
                   "or [name vals option ...], where name is a string or an "
                   "identifier with no binding"))

  (define (string-headed clause)
    (syntax-parse clause
      [(_:str . _) clause]
      [_ #f]))

  (define (string-head-message clause)
    (syntax-parse clause
      [(text:str . _)
       (format "a clause headed by a string is a column, [~s vals option ...]" (syntax-e #'text))]))

  (define (bound-bracketed-head clause)
    (syntax-parse clause
      [(head:id . _)
       #:when (and (bracketed? clause) (eq? (head-binding #'head) 'bound))
       #'head]
      [_ #f]))

  (define (named-clause-problem head kws)
    (cond
      [(name-option kws) => (lambda (kw) (cons (renamed-head-message head) kw))]
      [(unknown-option kws) => (lambda (kw) (cons (unknown-option-message kw) kw))]
      [(repeated-option kws) => (lambda (kw) (cons (repeated-option-message kw) kw))]
      [else #f]))

  (define (literal-name kws es)
    (for/first ([kw (in-list kws)] [e (in-list es)]
                #:when (eq? (syntax-e kw) '#:name)
                #:when (syntax-parse e
                         #:literals (quote)
                         [(~or* _:str (quote _:id)) #t]
                         [_ #f]))
      e))

  (define-splicing-syntax-class keyword-arguments
    #:attributes ([kw 1] [e 1])
    (pattern (~seq (~seq kw:keyword e:expr) ...)))

  (define-syntax-class column-name-head
    #:attributes (name)
    #:description "a column name: a string, or an identifier with no binding"
    (pattern text:str
      #:with name #'text)
    (pattern head:id
      #:when (eq? (head-binding #'head) 'unbound)
      #:with name (datum->syntax #'head (name-string #'head) #'head)))

  (define-syntax-class deferred-column
    #:attributes (head part)
    #:description "a column clause headed by an identifier with no binding yet"
    (pattern (~and clause (head:id vals:expr args:keyword-arguments))
      #:when (eq? (head-binding #'head) 'deferred)
      #:do [(define problem (named-clause-problem #'head (attribute args.kw)))]
      #:attr message (and problem (datum->syntax #'clause (car problem)))
      #:attr at (and problem (cdr problem))
      #:with name (datum->syntax #'head (name-string #'head) #'head)
      #:with part #'(~? (raise-syntax-error 'dataframe message (quote-syntax clause)
                                            (quote-syntax at))
                        ((column-clause-at (quote-srcloc clause) (quote-module-name))
                         vals #:name name (~@ args.kw args.e) ...))))

  (define-syntax-class dataframe-clause
    #:attributes (part literal-name)
    #:description "a column clause"
    #:commit
    (pattern (~and clause (vals:expr args:keyword-arguments)
                   (~fail #:unless (name-option (attribute args.kw)))
                   ~!)
      #:fail-when (unknown-option (attribute args.kw))
                  (unknown-option-message (unknown-option (attribute args.kw)))
      #:fail-when (repeated-option (attribute args.kw))
                  (repeated-option-message (repeated-option (attribute args.kw)))
      #:attr literal-name (literal-name (attribute args.kw) (attribute args.e))
      #:with part #'((column-clause-at (quote-srcloc clause) (quote-module-name))
                     vals (~@ args.kw args.e) ...))
    (pattern (~and clause (head:column-name-head vals:expr args:keyword-arguments) ~!)
      #:fail-when (name-option (attribute args.kw)) (renamed-head-message #'head)
      #:fail-when (unknown-option (attribute args.kw))
                  (unknown-option-message (unknown-option (attribute args.kw)))
      #:fail-when (repeated-option (attribute args.kw))
                  (repeated-option-message (repeated-option (attribute args.kw)))
      #:attr literal-name #'head
      #:with part #'((column-clause-at (quote-srcloc clause) (quote-module-name))
                     vals #:name head.name (~@ args.kw args.e) ...))
    (pattern (~and clause column:deferred-column)
      #:when (bracketed? #'clause)
      #:attr literal-name #f
      #:with message (datum->syntax #'clause (bound-head-message #'column.head))
      #:with part #'(if (top-level-variable? (#%variable-reference) 'column.head)
                        (raise-syntax-error 'dataframe message (quote-syntax clause)
                                            (quote-syntax column.head))
                        column.part))
    (pattern (~and clause column:deferred-column)
      #:attr literal-name #f
      #:with part #'(if (top-level-variable? (#%variable-reference) 'column.head)
                        ((column-part-at (quote-srcloc clause) (quote-module-name)) clause)
                        column.part))
    (pattern clause:expr
      #:fail-when (string-headed #'clause) (string-head-message #'clause)
      #:fail-when (bound-bracketed-head #'clause)
                  (bound-head-message (bound-bracketed-head #'clause))
      #:fail-when (and (bracketed? #'clause) #'clause) bracketed-message
      #:attr literal-name #f
      #:with part #'((column-part-at (quote-srcloc clause) (quote-module-name)) clause))))

(define-syntax-parser dataframe
  [(~fail #:unless (expanded-later?))
   (quasisyntax/loc this-syntax (#%expression #,this-syntax))]
  [(_ column:dataframe-clause ...)
   #:do [(define repeated
           (check-duplicates (filter values (attribute column.literal-name)) #:key name-string))]
   #:fail-when repeated (format "duplicate column name ~s" (name-string repeated))
   #'(build-frame 'dataframe (list column.part ...))]
  [_:id #'dataframe/contracted])

(module+ internal
  (provide columns->dataframe column-option-keywords))
