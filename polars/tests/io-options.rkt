#lang racket/base

(module+ test
  (require rackunit
           (for-syntax racket/base)
           (only-in racket/contract/region define/contract)
           (only-in polars/private/io-options define-io-options keyword-forwarder))

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
