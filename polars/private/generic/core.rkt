#lang racket/base

(module column-options racket/base
  (provide column-option-keywords)
  (define column-option-keywords '(#:dtype)))

(require racket/generic
         (only-in racket/contract/base
                  -> ->* ->i any contract contract-out define-module-boundary-contract
                  get/build-late-neg-projection listof or/c)
         (only-in racket/contract/combinator make-contract raise-blame-error)
         (only-in racket/list append-map check-duplicates)
         (only-in racket/match match match* match-define)
         syntax/location
         syntax/parse/define
         (for-syntax racket/base
                     (only-in racket/list check-duplicates)
                     (only-in racket/match match match-define)
                     (only-in racket/string string-join)
                     syntax/parse
                     (submod "." column-options))
         (only-in ffi/unsafe prop:cpointer)
         (only-in polars/private/bulk in-series)
         (only-in polars/private/expr-core lazyframe-dropped)
         polars/private/foreign
         (only-in (submod polars/private/foreign internal)
                  dataframe-column/who dataframe-select/who named series-cast-to series-slice/who)
         (only-in polars/private/resource utf-8-name/c with-release-pool)
         polars/private/generic/dtype
         (only-in polars/private/dtype-spelling cast-target/c normalize-dtype)
         polars/private/generic/printing
         (submod "." column-options))

(provide (except-out (all-defined-out)
                     (struct-out column-clause)
                     build-frame clause->series column-clause-at column-clause/c column-name/c
                     column-part-at column-part/c column-values/c columns->dataframe core-party
                     dataframe-procedure dataframe/contracted make-column-clause series series-of
                     sequence-elements top-level-variable? values-expectation)
         (contract-out
          [series (->i ([elements (dtype) (series-elements/c dtype)])
                       (#:name [name utf-8-name/c] #:dtype [dtype datetime-zone/c])
                       [result series?])]))

(define unset (gensym 'unset))

(define-generics has-ref
  (ref has-ref [key] #:columns [columns] #:rows [rows]))

(define-generics sized
  (len sized))

(define-generics has-shape
  (shape has-shape))

(define-generics has-dtype
  (dtype has-dtype))

(define-generics has-null-count
  (null-count has-null-count))

;; ---------------------------------------------------------------------------
;; the series wrapper

(struct series-rec (ptr)
  #:reflection-name 'series
  #:property prop:cpointer 0                ; marshals as a _Series-ptr
  #:property prop:owned-pointer 0
  #:property prop:custom-write (write-owned 'series series-dropped series->printed)
  #:property prop:sequence in-series
  #:methods gen:has-ref
  [(define (ref s [key unset] #:columns [columns unset] #:rows [rows unset])
     (series-ref* s key columns rows))]
  #:methods gen:sized
  [(define (len s) (series-len s))]
  #:methods gen:has-shape
  [(define (shape s) (list (series-len s)))]
  #:methods gen:has-dtype
  [(define (dtype s) (series-dtype s))]
  #:methods gen:has-null-count
  [(define (null-count s) (series-null-count s))])

(define series? series-rec?)
(define (wrap-series ptr) (series-rec ptr))
(define (null-series? v) (and (series? v) (eq? (series-dtype v) 'null)))

;; ---------------------------------------------------------------------------
;; the dataframe wrapper

(struct dataframe-rec (ptr)
  #:reflection-name 'dataframe
  #:property prop:cpointer 0
  #:property prop:owned-pointer 0
  #:property prop:custom-write
  (write-owned 'dataframe dataframe-dropped
               (lambda (d) (printed-or-placeholder 'dataframe (lambda () (dataframe->string/raw d)))))
  #:methods gen:has-ref
  [(define (ref d [key unset] #:columns [columns unset] #:rows [rows unset])
     (dataframe-ref* d key columns rows))]
  #:methods gen:sized
  [(define (len d) (dataframe-height d))]
  #:methods gen:has-shape
  [(define (shape d)
     (define-values (rows cols) (dataframe-shape d))
     (list rows cols))])

(define (dataframe? v) (dataframe-rec? v))
(define (wrap-dataframe ptr) (dataframe-rec ptr))

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

(define (column-problem present names)
  (cond
    [(for/first ([name (in-list names)] #:unless (member name present)) name)
     => (lambda (name) (format "~s not found" name))]
    [(check-duplicates names) => (lambda (name) (format "~s named more than once" name))]
    [else #f]))


;; ---------------------------------------------------------------------------
;; the lazyframe wrapper

(struct lazyframe-rec (ptr)
  #:reflection-name 'lazyframe
  #:property prop:cpointer 0
  #:property prop:owned-pointer 0
  #:property prop:custom-write
  (write-owned 'lazyframe lazyframe-dropped (lambda (lf) "#<lazyframe>")))

(define (lazyframe? v) (lazyframe-rec? v))
(define (wrap-lazyframe ptr) (lazyframe-rec ptr))

(define-syntax-parse-rule (define-wrapped name:id wrap:expr reader:expr)
  (define name (procedure-rename (compose1 wrap reader) 'name)))

;; ---------------------------------------------------------------------------
;; dataframe-only accessors (plain functions guarded on dataframe?).

(define (guard-dataframe who d)
  (unless (dataframe? d)
    (error who "expected a dataframe, got ~v" d)))

(define (width d)  (guard-dataframe 'width d)  (dataframe-width d))
(define (height d) (guard-dataframe 'height d) (dataframe-height d))
(define (column-name d i)
  (guard-dataframe 'column-name d)
  (dataframe-column-name d i))
(define (column-names d)
  (guard-dataframe 'column-names d)
  (dataframe-column-names d))

(define (shape/values x) (apply values (shape x)))

;; ---------------------------------------------------------------------------
;; series: keyword constructor with dtype inference (see dtype.rkt)

(define (series-of who elements name dtype)
  (define canonical (if dtype (normalize-dtype dtype who) (infer-dtype who elements)))
  (define ctor (dtype->constructor who canonical (vector? elements)))
  (wrap-series (ctor name (coerce-elements canonical elements))))

(define (series elements #:name [name ""] #:dtype [dtype #f])
  (series-of 'series elements name dtype))

;; ---------------------------------------------------------------------------
;; ref dispatch helpers (referenced by the struct methods above)

(define (series-ref* s key columns rows)
  (unless (eq? columns unset)
    (error 'ref "a series has no columns to select"))
  (unless (eq? rows unset)
    (error 'ref "series row slicing not supported"))
  (when (eq? key unset)
    (error 'ref "ref on a series requires an index"))
  (series-value 'ref s key))

(define (column->name d c)
  (cond
    [(string? c) c]
    [(and (exact-nonnegative-integer? c) (< c (dataframe-width d))) (dataframe-column-name d c)]
    [(exact-nonnegative-integer? c)
     (raise-arguments-error 'ref "column index out of range" "index" c "width" (dataframe-width d))]
    [else (error 'ref "dataframe column selector must be a string or index, got ~v" c)]))

(define (dataframe-ref* d key columns rows)
  (unless (eq? rows unset)
    (error 'ref "dataframe row slicing not yet implemented"))
  (define sel
    (cond
      [(not (eq? columns unset)) columns]
      [(not (eq? key unset)) key]
      [else (error 'ref "ref on a dataframe requires a column key or #:columns")]))
  (cond
    [(list? sel)
     (define names (map (lambda (c) (column->name d c)) sel))
     (wrap-dataframe
      (dataframe-select/who 'ref d names
                            #:problem (lambda () (column-problem (dataframe-column-names d) names))))]
    [else
     (define name (column->name d sel))
     (wrap-series
      (dataframe-column/who 'ref d name
                            #:problem (lambda ()
                                        (column-problem (dataframe-column-names d) (list name)))))]))

;; ---------------------------------------------------------------------------
;; dataframe: column clauses over series' constructor

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

(struct column-clause (name values dtype))

(define (make-column-clause vals #:name name #:dtype [dtype #f])
  (column-clause (if (symbol? name) (symbol->string name) name) vals dtype))

(define column-clause/c
  (->i ([values (dtype) (column-values/c dtype)] #:name [name column-name/c])
       (#:dtype [dtype (or/c #f cast-target/c)])
       [_ column-clause?]))

(define (column-clause-at srcloc party)
  (contract column-clause/c make-column-clause core-party party 'dataframe srcloc))

(define (column-part-at srcloc party)
  (contract (-> column-part/c any) values core-party party 'dataframe srcloc))

(define (clause->series who own clause)
  (match-define (column-clause name vals dtype) clause)
  (cond
    [(not (Series-ptr? vals)) (own (series-of who vals name dtype))]
    [dtype ((named who name) (own (series-cast-to who vals dtype)))]
    [else ((named who name) (own (series-slice/who who vals 0 (series-len vals))))]))

(define (build-frame who parts)
  (with-release-pool ([own series-drop])
    (define columns
      (append-map (lambda (part)
                    (match part
                      [(? column-clause?) (list (clause->series who own part))]
                      [(? list?) part]
                      [_ (list part)]))
                  parts))
    (wrap-dataframe
     (or (dataframe-new/raw columns)
         (raise-arguments-error who (or (frame-columns-problem columns)
                                        "could not create a new DataFrame"))))))

(define (columns->dataframe . parts)
  (build-frame 'dataframe parts))

(define dataframe-procedure (procedure-rename columns->dataframe 'dataframe))

(define-module-boundary-contract dataframe/contracted dataframe-procedure
  (->* () #:rest (listof column-part/c) dataframe?)
  #:name-for-blame dataframe)

(define (top-level-variable? variable-reference name)
  (not (eq? (namespace-variable-value name #f (lambda () unset)
                                      (variable-reference->namespace variable-reference))
            unset)))

(begin-for-syntax
  (define (head-binding id)
    (cond [(identifier-binding id 0 #t) 'bound]
          [(syntax-transforming-module-expression?) 'unbound]
          [else 'deferred]))

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

  (define (options-problem kws name-message)
    (let loop ([kws kws] [seen '()])
      (match kws
        ['() #f]
        [(cons kw rest)
         (define key (syntax-e kw))
         (cond
           [(and name-message (eq? key '#:name)) (list name-message kw)]
           [(not (memq key option-keywords))
            (list (format "~a is not a column option; the options are ~a" key option-list) kw)]
           [(memq key seen) (list (format "~a appears twice in one column" key) kw)]
           [else (loop rest (cons key seen))])])))

  (define (bound-head-message head)
    (define name (syntax-e head))
    (format (string-append "~s is bound here, so this bracketed clause is not a column; "
                           "name a column with #:name, as in [vals #:name '~s], "
                           "or with a string, as in [~s vals], "
                           "or drop the brackets for an expression")
            name name (symbol->string name)))

  (define (renamed-head-message head)
    (if (identifier? head)
        (format "~s has no binding here, so it names the column, and #:name cannot name it again"
                (syntax-e head))
        (format "~s names the column, so #:name cannot name it again" (syntax-e head))))

  (define bracketed-message
    (string-append "a bracketed clause is a column, [vals #:name name option ...] "
                   "or [name vals option ...], where name is a string or an "
                   "identifier with no binding"))

  (define (expression-problem clause)
    (syntax-parse clause
      [(text:str . _)
       (list (format "a clause headed by a string is a column, [~s vals option ...]"
                     (syntax-e #'text))
             clause)]
      [_ #:when (not (bracketed? clause)) #f]
      [(head:id . _)
       #:when (eq? (head-binding #'head) 'bound)
       (list (bound-head-message #'head) #'head)]
      [_ (list bracketed-message clause)]))

  (define (raise-problem clause problem)
    (match problem
      [#f (void)]
      [(list message at) (raise-syntax-error 'dataframe message clause at)]))

  (define (raise-problem-later clause problem)
    (match-define (list message at) problem)
    #`(raise-syntax-error 'dataframe #,message (quote-syntax #,clause) (quote-syntax #,at)))

  (define (literal-name kws es)
    (for/first ([kw (in-list kws)] [e (in-list es)]
                #:when (eq? (syntax-e kw) '#:name)
                #:when (syntax-parse e
                         #:literals (quote)
                         [(~or* _:str (quote _:id)) #t]
                         [_ #f]))
      e))

  (define (repeated-name-problem names)
    (let loop ([names (filter values names)] [seen '()])
      (match names
        ['() #f]
        [(cons name rest)
         (define text (name-string name))
         (if (member text seen)
             (list (format "duplicate column name ~s" text) name)
             (loop rest (cons text seen)))])))

  (define-splicing-syntax-class keyword-arguments
    #:attributes ([kw 1] [e 1])
    (pattern (~seq (~seq kw:keyword e:expr) ...)))

  (define-syntax-class column-name-head
    #:attributes (name deferred?)
    #:description "a column name: a string, or an identifier with no binding"
    (pattern text:str
      #:attr deferred? #f
      #:with name #'text)
    (pattern head:id
      #:do [(define binding (head-binding #'head))]
      #:when (not (eq? binding 'bound))
      #:attr deferred? (eq? binding 'deferred)
      #:with name (datum->syntax #'head (name-string #'head) #'head)))

  (define-syntax-class values-clause
    #:attributes (part literal-name)
    (pattern (~and clause (vals:expr args:keyword-arguments))
      #:when (memq '#:name (syntax->datum #'(args.kw ...)))
      #:do [(raise-problem #'clause (options-problem (attribute args.kw) #f))]
      #:attr literal-name (literal-name (attribute args.kw) (attribute args.e))
      #:with part #'((column-clause-at (quote-srcloc clause) (quote-module-name))
                     vals (~@ args.kw args.e) ...)))

  (define-syntax-class named-clause
    #:attributes (part literal-name)
    (pattern (~and clause (head:column-name-head vals:expr args:keyword-arguments))
      #:do [(define problem
              (options-problem (attribute args.kw) (renamed-head-message #'head)))
            (define deferred? (attribute head.deferred?))
            (unless deferred? (raise-problem #'clause problem))]
      #:attr literal-name (and (not deferred?) #'head)
      #:with column (if problem
                        (raise-problem-later #'clause problem)
                        #'((column-clause-at (quote-srcloc clause) (quote-module-name))
                           vals #:name head.name (~@ args.kw args.e) ...))
      #:with part (cond
                    [(not deferred?) #'column]
                    [(bracketed? #'clause)
                     #`(if (top-level-variable? (#%variable-reference) 'head)
                           #,(raise-problem-later #'clause
                                                  (list (bound-head-message #'head) #'head))
                           column)]
                    [else
                     #'(if (top-level-variable? (#%variable-reference) 'head)
                           ((column-part-at (quote-srcloc clause) (quote-module-name)) clause)
                           column)])))

  (define-syntax-class expression-clause
    #:attributes (part literal-name)
    (pattern (~and clause _:expr)
      #:do [(raise-problem #'clause (expression-problem #'clause))]
      #:attr literal-name #f
      #:with part #'((column-part-at (quote-srcloc clause) (quote-module-name)) clause)))

  (define-syntax-class column-clause
    #:attributes (part literal-name)
    #:commit
    (pattern :values-clause)
    (pattern :named-clause)
    (pattern :expression-clause)))

(define-syntax-parser dataframe
  [(_ column:column-clause ...)
   #:do [(raise-problem this-syntax (repeated-name-problem (attribute column.literal-name)))]
   #'(build-frame 'dataframe (list column.part ...))]
  [_:id #'dataframe/contracted])

(module+ internal
  (provide columns->dataframe column-option-keywords))
