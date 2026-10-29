#lang racket/base

(require (only-in ffi/unsafe
                  _gcpointer _int64 ctype-sizeof define-fun-syntax free malloc memcpy ptr-ref
                  ptr-set!)
         (only-in ffi/unsafe/alloc allocator deallocator)
         (only-in racket/contract/base and/c flat-named-contract listof or/c)
         (only-in racket/list last)
         (only-in racket/match match match-define)
         syntax/parse/define
         (for-syntax racket/base syntax/parse))

(provide _str
         _str-list
         _str/null
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
   #'(let ([acquire (lambda () first.acquire)]
           [held #f]
           [entered? #f])
       (let ([first.name #f])
         (dynamic-wind
          (lambda ()
            (when entered?
              (error 'with-release "cannot re-enter the extent after its release"))
            (set! entered? #t)
            (set! held (acquire))
            (set! first.name held))
          (lambda () (with-release (more ...) body ...))
          (lambda ()
            (define acquired held)
            (set! held #f)
            (set! first.name #f)
            (when acquired
              (let ([first.name acquired])
                (first.release first.name)))))))])

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

(define (name->bytes v)
  (if (path? v) (path->bytes v) v))

(define (utf-8-name->string v)
  (cond
    [(string? v) v]
    [else
     (define encoded (name->bytes v))
     (and (bytes-utf-8-length encoded #f) (bytes->string/utf-8 encoded))]))

(define utf-8-name/c
  (or/c string? (and/c (or/c bytes? path?) (flat-named-contract 'utf-8? utf-8-name->string))))

(define utf-8-names/c (listof utf-8-name/c))

;; A _fun argument syntax, not a ctype: a callout retains the values it is
;; given, not what a ctype converts them to, so only this way does the block
;; outlive a collection during the call.
(define-syntax-parse-rule (define-block-argument name:id encode:id)
  (define-fun-syntax name
    (make-set!-transformer
     (syntax-parser
       [_:id #'(type: _gcpointer pre: (v => (encode v)))]))))

(define word-size (ctype-sizeof _int64))

(define (padded-words byte-count)
  (quotient (+ byte-count word-size -1) word-size))

(define (name-bytes who v)
  (cond
    [(string? v) (string->bytes/utf-8 v)]
    [(and (or (bytes? v) (path? v)) (utf-8-name->string v)) (name->bytes v)]
    [else (raise-argument-error who "utf-8-name/c" v)]))

(define (str-block words second)
  (define block (malloc (* words word-size) 'atomic-interior))
  (ptr-set! block _int64 0 words)
  (ptr-set! block _int64 1 second)
  block)

(define (string->str-block v)
  (define utf-8 (name-bytes '_str v))
  (define len (bytes-length utf-8))
  (define block (str-block (+ 2 (padded-words len)) len))
  (memcpy block (* 2 word-size) utf-8 len)
  block)

(define (strings->str-block vs)
  (define encoded (for/list ([v (in-list vs)]) (name-bytes '_str-list v)))
  (define count (length encoded))
  (define data (+ 3 count))
  (define offsets
    (for/fold ([starts '()] [at 0] #:result (reverse (cons at starts)))
              ([utf-8 (in-list encoded)])
      (values (cons at starts) (+ at (bytes-length utf-8)))))
  (define block (str-block (+ data (padded-words (last offsets))) count))
  (for ([offset (in-list offsets)] [i (in-naturals 2)])
    (ptr-set! block _int64 i offset))
  (for ([utf-8 (in-list encoded)] [start (in-list offsets)])
    (memcpy block (+ (* data word-size) start) utf-8 (bytes-length utf-8)))
  block)

(define (str-block->string block)
  (define len (ptr-ref block _int64 1))
  (define utf-8 (make-bytes len))
  (memcpy utf-8 0 block (* 2 word-size) len)
  (bytes->string/utf-8 utf-8))

(define (str-block->strings block)
  (define count (ptr-ref block _int64 1))
  (define offsets (for/list ([i (in-range 2 (+ 3 count))]) (ptr-ref block _int64 i)))
  (define utf-8 (make-bytes (last offsets)))
  (memcpy utf-8 0 block (* (+ 3 count) word-size) (bytes-length utf-8))
  (match-define (cons _ ends) offsets)
  (for/list ([start (in-list offsets)] [end (in-list ends)])
    (bytes->string/utf-8 utf-8 #f start end)))

(define (str/null-argument v)
  (and v (string->str-block v)))

(define (str-list-argument vs)
  (match vs
    ['() #f]
    [(? list?) (strings->str-block vs)]
    [_ (raise-argument-error '_str-list "(listof utf-8-name/c)" vs)]))

(define-block-argument _str string->str-block)
(define-block-argument _str/null str/null-argument)
(define-block-argument _str-list str-list-argument)

(module+ internal
  (provide str-block->string
           str-block->strings
           string->str-block
           strings->str-block))
