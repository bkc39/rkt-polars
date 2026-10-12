#lang racket/base

(require (only-in ffi/unsafe
                  _byte _gcpointer _pointer ctype-sizeof define-fun-syntax free malloc memcpy
                  ptr-add ptr-set!)
         (only-in ffi/unsafe/alloc allocator deallocator)
         syntax/parse/define
         (for-syntax racket/base syntax/parse))

(provide _string-list
         with-raw-buffer
         with-release)

;; The finalizer allocator registers backs up a thread killed inside the
;; extent, whose dynamic-wind post thunks never run; free-buffer unregisters it.
(define free-buffer ((deallocator) free))
(define alloc-buffer
  ((allocator free-buffer) (lambda (count ctype) (malloc (max count 1) ctype 'raw))))

(define-syntax-parser with-release
  [(_ () body:expr ...+)
   #'(let () body ...)]
  [(_ ([name:id acquire:expr release:expr] more ...) body:expr ...+)
   #'(let ([name #f])
       (dynamic-wind
        (lambda () (set! name acquire))
        (lambda () (with-release (more ...) body ...))
        (lambda ()
          (when name
            (release name)
            (set! name #f)))))])

(define-syntax-parse-rule (with-raw-buffer ([name:id count:expr ctype:expr] ...+) body:expr ...+)
  (with-release ([name (alloc-buffer count ctype) free-buffer] ...) body ...))

(define (c-string-bytes v)
  (cond
    [(string? v) (string->bytes/utf-8 v)]
    [(bytes? v) v]
    [(path? v) (path->bytes v)]
    [else (raise-argument-error '_string-list "(or/c string? bytes? path?)" v)]))

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

(module+ test
  (require rackunit
           racket/match
           racket/runtime-path
           (only-in racket/file file->string)
           (only-in racket/list append-map last)
           (only-in ffi/unsafe
                    _fun _int64 _pointer _size _string/utf-8 _void cast function-ptr ptr-ref
                    ptr-set!)
           (only-in polars/private/gc-pressure call-with-collections))

  (define released '())
  (define (release! tag) (set! released (cons tag released)))

  (set! released '())
  (check-equal? (with-release ([a 'a release!] [b 'b release!]) (list a b)) '(a b))
  (check-equal? released '(a b))

  (set! released '())
  (check-exn #rx"boom"
             (lambda () (with-release ([a 'a release!]) (error 'test "boom"))))
  (check-equal? released '(a))

  (set! released '())
  (check-equal? (let/ec k (with-release ([a 'a release!]) (k 'escaped) 'not-reached))
                'escaped)
  (check-equal? released '(a))

  (set! released '())
  (check-equal? (with-release ([a #f release!] [b 'b release!]) (list a b)) '(#f b))
  (check-equal? released '(b))

  (check-equal? (with-raw-buffer ([words 3 _int64])
                  (for ([i (in-range 3)]) (ptr-set! words _int64 i (* 10 i)))
                  (for/list ([i (in-range 3)]) (ptr-ref words _int64 i)))
                '(0 10 20))
  (check-equal? (with-raw-buffer ([empty 0 _int64]) 'zero-length-ok) 'zero-length-ok)

  (define tables '())
  (define (read-back table count)
    (collect-garbage)
    (set! tables
          (cons (and table (for/list ([i (in-range count)]) (ptr-ref table _string/utf-8 i)))
                tables)))
  (define read-back-pointer (function-ptr read-back (_fun _pointer _size -> _void)))
  (define call-read-back
    (cast read-back-pointer _pointer (_fun (strings : _string-list) (_size = (length strings))
                                           -> _void)))
  (call-read-back '())
  (call-read-back '("" "a" "東京 😀"))
  (check-equal? tables '(("" "a" "東京 😀") #f))
  (call-read-back (list #"bytes" (string->path "a/path") "東京"))
  (check-equal? (car tables) '("bytes" "a/path" "東京"))
  (define column-names
    (list* "" "a" (for/list ([i (in-range 300000)]) (format "column ~a é 東京 😀" i))))
  (define-values (table collections)
    (call-with-collections (lambda () (strings->c-array column-names))))
  (check > collections 1)
  (collect-garbage)
  (check-equal? (for/list ([i (in-range (length column-names))]) (ptr-ref table _string/utf-8 i))
                column-names)
  (check-exn #rx"^_string-list: contract violation\n  expected: \\(or/c string\\? bytes\\? path\\?\\)\n  given: 'b"
             (lambda () (strings->c-array '("a" b))))

  (define-runtime-path private-dir ".")
  (define (offenders pattern)
    (for/list ([f (in-directory private-dir)]
               #:when (regexp-match? #rx"[.]rkt$" (path->string f))
               #:unless (equal? (last (explode-path f)) (string->path "resource.rkt"))
               #:when (regexp-match? pattern (file->string f)))
      f))
  (check-equal? (offenders #px"\\((?:malloc|free)\\s") '()
                "raw malloc/free outside polars/private/resource.rkt: use with-raw-buffer")

  (define (forms-in datum)
    (cond
      [(and (pair? datum) (eq? (car datum) 'quote)) '()]
      [(list? datum) (cons datum (append-map forms-in datum))]
      [(pair? datum) (append-map forms-in (let spread ([p datum])
                                            (if (pair? p) (cons (car p) (spread (cdr p))) (list p))))]
      [(vector? datum) (append-map forms-in (vector->list datum))]
      [else '()]))

  (define (pointer-ctype? type aliases)
    (match type
      [(? symbol?)
       (or (memq type aliases)
           (regexp-match? #px"^_(?:string|bytes|path|file|symbol|gcpointer|racket|scheme)(?:[*/]\\S*)?$"
                          (symbol->string type)))]
      [(list* 'make-ctype base _) (pointer-ctype? base aliases)]
      [_ #f]))

  (define (pointer-aliases forms)
    (let grow ([aliases '()])
      (define more
        (for/list ([form (in-list forms)]
                   #:when (match form
                            [(list 'define (? symbol? name) type)
                             (and (not (memq name aliases)) (pointer-ctype? type aliases))]
                            [_ #f]))
          (cadr form)))
      (if (null? more) aliases (grow (append more aliases)))))

  (define (pointer-stores forms aliases)
    (define (pointer? type) (pointer-ctype? type aliases))
    (for/list ([form (in-list forms)]
               #:when (match form
                        [(list* (or '_list '_vector '_ptr) (or 'i 'io) type _) (pointer? type)]
                        [(list* (or '_array '_array/list '_array/vector '_box) type _) (pointer? type)]
                        [(list* '_list-struct types) (ormap pointer? types)]
                        [(list* 'define-cstruct _ (? list? fields) _)
                         (for/or ([field (in-list fields)])
                           (match field
                             [(list* _ type _) (pointer? type)]
                             [_ #f]))]
                        [(list* 'define-series-constructors _ type _) (pointer? type)]
                        [_ #f]))
      form))

  (define (offending-forms text)
    (define forms (append-map forms-in (for/list ([datum (in-port read (open-input-string text))])
                                         datum)))
    (pointer-stores forms (pointer-aliases forms)))
  (check-equal? (offending-forms
                 (string-append "(define _name _string/utf-8) (define _held (make-ctype _name #f #f))"
                                "(_list i _held) (_vector io _bytes) (_ptr i _path) (_array _file 2)"
                                "(_box _symbol) (_list-struct _int _gcpointer)"
                                "(define-cstruct _S ((n _int) (s _string)))"
                                "(define-cstruct _T ([r _racket]))"
                                "(define-series-constructors str _string* \"\")"))
                '((_list i _held) (_vector io _bytes) (_ptr i _path) (_array _file 2) (_box _symbol)
                  (_list-struct _int _gcpointer) (define-cstruct _S ((n _int) (s _string)))
                  (define-cstruct _T ((r _racket))) (define-series-constructors str _string* "")))
  (check-equal? (offending-forms
                 (string-append "(_fun _string _bytes -> _void) (_list i _Expr-ptr) (_list o _string 3)"
                                "(_list i _string-list) (define-cstruct _P ((p _pointer)))"
                                "(define (f _string) (_list i _int)) '(_list i _string)"))
                '())

  (define private-forms
    (parameterize ([read-accept-reader #t]
                   [read-accept-lang #t])
      (for/list ([f (in-directory private-dir)]
                 #:when (regexp-match? #rx"[.]rkt$" (path->string f)))
        (cons f (forms-in (call-with-input-file f read))))))
  (check > (length private-forms) 30)
  (define private-aliases (pointer-aliases (append-map cdr private-forms)))
  (check-equal? (for*/list ([file+forms (in-list private-forms)]
                            [form (in-list (pointer-stores (cdr file+forms) private-aliases))])
                  (list (car file+forms) form))
                '()
                "a string or Racket object stored by address in Racket memory: use _string-list"))
