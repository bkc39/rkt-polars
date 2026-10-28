#lang racket/base

(require (only-in ffi/unsafe
                  _byte _gcpointer _pointer ctype-sizeof define-fun-syntax free malloc memcpy
                  ptr-add ptr-set!)
         (only-in ffi/unsafe/alloc allocator deallocator)
         (only-in racket/contract/base and/c flat-named-contract listof or/c)
         (only-in racket/match match)
         syntax/parse/define
         (for-syntax racket/base syntax/parse))

(provide _string-list
         utf-8-name->string
         utf-8-name/c
         utf-8-names/c
         with-raw-buffer
         with-release
         with-release-pool
         with-releases)

;; The finalizer allocator registers backs up a thread killed inside the
;; extent, whose dynamic-wind post thunks never run; free-buffer unregisters it.
(define free-buffer ((deallocator) free))
(define alloc-buffer
  ((allocator free-buffer) (lambda (count ctype) (malloc (max count 1) ctype 'raw))))

(begin-for-syntax
  (define-syntax-class release-clause
    (pattern [name:id acquire:expr release:expr]))
  (define-splicing-syntax-class for-clause
    (pattern [name:id sequence:expr])
    (pattern [(name:id ...) sequence:expr])
    (pattern (~seq keyword:keyword guard:expr))))

(define (release-each release vs)
  (match vs
    ['() (void)]
    [(cons v more)
     (dynamic-wind void
                   (lambda () (release v))
                   (lambda () (release-each release more)))]))

(define-syntax-parser with-release
  [(_ () body:expr ...+)
   #'(let () body ...)]
  [(_ (first:release-clause more:release-clause ...) body:expr ...+)
   #'(let ([held #f])
       (dynamic-wind
        (lambda () (set! held first.acquire))
        (lambda () (let ([first.name held]) (with-release (more ...) body ...)))
        (lambda ()
          (define acquired held)
          (set! held #f)
          (when acquired
            (let ([first.name acquired])
              (first.release first.name))))))])

(define-syntax-parse-rule (with-releases ([name:id (clause:for-clause ...)
                                          acquire:expr release:expr])
                           body:expr ...+)
  (let ([acquired '()])
    (dynamic-wind
     void
     (lambda ()
       (for ((~@ . clause) ...)
         (set! acquired (cons acquire acquired)))
       (let ([name (reverse acquired)])
         body ...))
     (lambda ()
       (define pending acquired)
       (set! acquired '())
       (release-each release pending)))))

(define-syntax-parse-rule (with-release-pool ([own:id release:expr]) body:expr ...+)
  (let ([owned '()])
    (dynamic-wind
     void
     (lambda ()
       (let ([own (lambda (v) (set! owned (cons v owned)) v)])
         body ...))
     (lambda ()
       (define pending owned)
       (set! owned '())
       (release-each release pending)))))

(define-syntax-parse-rule (with-raw-buffer ([name:id count:expr ctype:expr] ...+) body:expr ...+)
  (with-release ([name (alloc-buffer count ctype) free-buffer] ...) body ...))

(define (c-string-bytes v)
  (cond
    [(string? v) (string->bytes/utf-8 v)]
    [(bytes? v) v]
    [(path? v) (path->bytes v)]
    [else (raise-argument-error '_string-list "(or/c string? bytes? path?)" v)]))

(define (utf-8-name->string v)
  (cond
    [(string? v) v]
    [else
     (define encoded (c-string-bytes v))
     (and (bytes-utf-8-length encoded #f) (bytes->string/utf-8 encoded))]))

(define utf-8-name/c
  (or/c string? (and/c (or/c bytes? path?) (flat-named-contract 'utf-8? utf-8-name->string))))

(define utf-8-names/c (listof utf-8-name/c))

;; The table's addresses point into its own block, which the collector never
;; moves (#143).
(define (strings->c-array strings)
  (define encoded (map c-string-bytes strings))
  (define table-size (* (length encoded) (ctype-sizeof _pointer)))
  (define block
    (malloc (for/fold ([size table-size]) ([utf-8 (in-list encoded)])
              (+ size (bytes-length utf-8) 1))
            'atomic-interior))
  (for/fold ([at table-size]) ([utf-8 (in-list encoded)] [i (in-naturals)])
    (define end (+ at (bytes-length utf-8)))
    (memcpy block at utf-8 (bytes-length utf-8))
    (ptr-set! block _byte 'abs end 0)
    (ptr-set! block _pointer i (ptr-add block at))
    (add1 end))
  block)

;; A _fun argument syntax, not a ctype: a callout retains the values it is
;; given, not what a ctype converts them to, so only this way does the block
;; outlive a collection during the call.
(define-fun-syntax _string-list
  (make-set!-transformer
   (syntax-parser
     [_:id #'(type: _gcpointer
              pre: (strings => (and (pair? strings) (strings->c-array strings))))])))

(module+ internal
  (provide strings->c-array))
