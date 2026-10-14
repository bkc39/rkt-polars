#lang racket/base

(require syntax/parse/define
         (for-syntax racket/base racket/list syntax/parse)
         (only-in racket/contract/base ->i))

(provide define-io-options keyword-forwarder)

(begin-for-syntax
  (define-syntax-class option
    #:description "an option [keyword name contract default]"
    (pattern [kw:keyword name:id contract:expr default:expr]))

  (define-splicing-syntax-class pre-clause
    #:description "a #:pre (name ...) message check or #:pre/desc (name ...) check clause"
    #:attributes ((name 1) (clause 1))
    (pattern (~seq #:pre (name:id ...) message:str check:expr)
             #:with (clause ...) #'(#:pre/name (name ...) message check))
    (pattern (~seq #:pre/desc (name:id ...) check:expr)
             #:with (clause ...) #'(#:pre/desc (name ...) check)))

  (define-syntax-class io-contract
    #:description "a contract [(name param) keywords ([arg contract] ...) result option ...]"
    (pattern [(name:id param:id) keywords:id ([arg:id arg/c:expr] ...) result:expr
              (~alt (~optional (~seq #:omit (omit:keyword ...)))
                    (~optional (~seq #:arguments arguments:id)))
              ...]
             #:attr omitted (map syntax-e (or (attribute omit) '()))))

  (define (kept-options options omitted)
    (filter (lambda (o) (not (memq (syntax-e (car (syntax-e o))) omitted))) options))

  (define (option-name o)
    (syntax-e (cadr (syntax-e o))))

  (define (optional-arguments options)
    (append* (for/list ([o (in-list options)])
               (syntax-case o ()
                 [(kw name contract _) (list #'kw #'[name contract])]))))

  (define (applicable-pres names-per-pre clauses-per-pre options)
    (define names (map option-name options))
    (append* (for/list ([pre-names (in-list names-per-pre)]
                        [clauses (in-list clauses-per-pre)]
                        #:when (for/and ([n (in-list pre-names)])
                                 (memq (syntax-e n) names)))
               clauses)))

  (define (sorted-keywords options)
    (sort (map (lambda (o) (syntax-e (car (syntax-e o)))) options) keyword<?)))

(define-syntax-parse-rule
  (define-io-options options-id:id
    (c:io-contract ...)
    (o:option ...)
    pre:pre-clause ...
    body:expr)
  #:do [(define options (attribute o))
        (define kept (for/list ([omitted (in-list (attribute c.omitted))])
                       (kept-options options omitted)))]
  #:with (optionals ...) (map optional-arguments kept)
  #:with ((pres ...) ...) (for/list ([k (in-list kept)])
                             (applicable-pres (attribute pre.name) (attribute pre.clause) k))
  #:with (keyword-list ...) (map sorted-keywords kept)
  #:with ((kept-option ...) ...) kept
  (begin
    (define (c.name c.param)
      (->i ([c.arg c.arg/c] ...) optionals pres ... [result c.result]))
    ...
    (define c.keywords 'keyword-list) ...
    (~? (define-syntax c.arguments (quote-syntax (kept-option ...))))
    ...
    (define (options-id (~@ o.kw [o.name o.default]) ...)
      body)))

(define (keyword-forwarder who options keywords arity call)
  (procedure-rename
   (procedure-reduce-keyword-arity
    (make-keyword-procedure
     (lambda (kws args . positional)
       (apply call (keyword-apply options kws args '()) positional)))
    arity '() keywords)
   who))

(module+ test
  (require rackunit
           (for-syntax racket/base)
           (only-in racket/contract/region define/contract))

  (define-io-options demo-options
    ([(reader/c range/c) read-keywords ([path string?]) range/c]
     [(scanner/c range/c) scan-keywords ([path string?]) range/c
      #:arguments scan-arguments #:omit (#:extra)])
    ([#:size size exact-nonnegative-integer? 1]
     [#:limit limit exact-nonnegative-integer? 10]
     [#:extra extra boolean? #f])
    #:pre (size limit) "size must not exceed limit" (<= (given-or size 1) (given-or limit 10))
    #:pre/desc (extra limit) (or (not (eq? extra #t)) (< (given-or limit 10) 100)
                                 "#:extra needs a limit under 100")
    (list size limit extra))

  (define (given-or v default)
    (if (exact-integer? v) v default))

  (define-syntax (arguments-of stx)
    (syntax-case stx ()
      [(_ id) #`(quote #,(syntax-local-value #'id))]))
  (check-equal? (arguments-of scan-arguments)
                '([#:size size exact-nonnegative-integer? 1]
                  [#:limit limit exact-nonnegative-integer? 10]))
  (check-equal? read-keywords '(#:extra #:limit #:size))
  (check-equal? scan-keywords '(#:limit #:size))
  (define read (keyword-forwarder 'read demo-options read-keywords 1 (lambda (o path) (cons path o))))
  (define scan (keyword-forwarder 'scan demo-options scan-keywords 1 (lambda (o path) (cons path o))))
  (check-equal? (read "p" #:extra #t #:size 2) '("p" 2 10 #t))
  (check-equal? (scan "p") '("p" 1 10 #f))
  (check-equal? (object-name read) 'read)
  (check-exn #rx"does not expect an argument with given keyword" (lambda () (scan "p" #:extra #t)))
  (define/contract checked-read (reader/c list?) read)
  (define/contract checked-scan (scanner/c list?) scan)
  (check-equal? (checked-read "p" #:limit 4 #:size 3) '("p" 3 4 #f))
  (check-exn #rx"size must not exceed limit" (lambda () (checked-scan "p" #:size 11)))
  (check-exn #rx"#:extra needs a limit under 100"
             (lambda () (checked-read "p" #:extra #t #:limit 200)))
  (check-equal? (checked-scan "p" #:limit 200) '("p" 1 200 #f))
  (check-exn #rx"contract violation" (lambda () (checked-read "p" #:extra 'maybe)))
  (check-exn #rx"contract violation" (lambda () (checked-scan 'p))))
