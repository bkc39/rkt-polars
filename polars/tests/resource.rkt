#lang racket/base

(module+ test
  (require rackunit
           (for-syntax racket/base)
           racket/match
           racket/runtime-path
           (only-in racket/file delete-directory/files file->string make-temporary-directory)
           (only-in racket/list append-map)
           (only-in ffi/unsafe
                    _fun _int64 _pointer _size _string/utf-8 _void cast function-ptr ptr-ref
                    ptr-set!)
           (only-in polars/private/resource
                    _string-list with-raw-buffer with-release with-release-pool with-releases)
           (only-in (submod polars/private/resource internal) strings->c-array)
           (only-in polars/tests/gc-pressure call-with-collections)
           (only-in polars/tests/test-helpers polars-sources))

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

  (set! released '())
  (check-equal? (with-releases ([tags ([i (in-range 3)]) (* 10 i) release!]) tags) '(0 10 20))
  (check-equal? released '(0 10 20))

  (set! released '())
  (check-exn #rx"at 2"
             (lambda ()
               (with-releases ([tags ([i (in-range 3)])
                                     (if (= i 2) (error 'test "at ~a" i) i)
                                     release!])
                 tags)))
  (check-equal? released '(0 1))

  (set! released '())
  (check-exn #rx"boom"
             (lambda () (with-releases ([tags ([i (in-range 2)]) i release!]) (error 'test "boom"))))
  (check-equal? released '(0 1))

  (set! released '())
  (check-equal? (let/ec k (with-releases ([tags ([i (in-range 2)]) i release!]) (k 'escaped)))
                'escaped)
  (check-equal? released '(0 1))

  (set! released '())
  (check-equal? (with-releases ([tags ([i (in-list '())]) i release!]) tags) '())
  (check-equal? released '())

  (define ((release-raising-on n) tag)
    (release! tag)
    (when (eqv? tag n) (error 'test "release ~a" tag)))

  (set! released '())
  (check-exn #rx"release 2"
             (lambda ()
               (with-releases ([tags ([i (in-range 4)]) i (release-raising-on 2)]) tags)))
  (check-equal? released '(0 1 2 3))

  (set! released '())
  (check-equal? (with-releases ([pairs ([i (in-range 4)] #:when (even? i) [j (in-range 1)])
                                       (cons i j)
                                       release!])
                  pairs)
                '((0 . 0) (2 . 0)))
  (check-equal? released '((0 . 0) (2 . 0)))

  (set! released '())
  (check-equal? (with-release-pool ([own release!]) (list (own 'a) (own 'b))) '(a b))
  (check-equal? released '(a b))

  (set! released '())
  (check-exn #rx"boom"
             (lambda () (with-release-pool ([own release!]) (own 'a) (error 'test "boom"))))
  (check-equal? released '(a))

  (set! released '())
  (check-exn #rx"release 1"
             (lambda ()
               (with-release-pool ([own (release-raising-on 1)])
                 (for ([i (in-range 3)]) (own i)))))
  (check-equal? released '(0 1 2))

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

  (define-runtime-path resource-module "../private/resource.rkt")
  (define raw-allocation #px"\\((?:malloc|free)\\s")
  (define (offenders pattern sources)
    (for/list ([f (in-list sources)]
               #:unless (equal? f (simplify-path resource-module))
               #:when (regexp-match? pattern (file->string f)))
      f))
  (check-equal? (offenders raw-allocation (polars-sources)) '()
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

  (define (offending-forms data)
    (define forms (append-map forms-in data))
    (pointer-stores forms (pointer-aliases forms)))
  (check-equal? (offending-forms
                 '((define _name _string/utf-8) (define _held (make-ctype _name #f #f))
                   (_list i _held) (_vector io _bytes) (_ptr i _path) (_array _file 2)
                   (_box _symbol) (_list-struct _int _gcpointer)
                   (define-cstruct _S ((n _int) (s _string)))
                   (define-cstruct _T ([r _racket]))
                   (define-series-constructors str _string* "")))
                '((_list i _held) (_vector io _bytes) (_ptr i _path) (_array _file 2) (_box _symbol)
                  (_list-struct _int _gcpointer) (define-cstruct _S ((n _int) (s _string)))
                  (define-cstruct _T ((r _racket))) (define-series-constructors str _string* "")))
  (check-equal? (offending-forms
                 '((_fun _string _bytes -> _void) (_list i _Expr-ptr) (_list o _string 3)
                   (_list i _string-list) (define-cstruct _P ((p _pointer)))
                   (define (f _string) (_list i _int)) '(_list i _string)))
                '())

  (define (source-forms sources)
    (parameterize ([read-accept-reader #t]
                   [read-accept-lang #t])
      (for/list ([f (in-list sources)])
        (cons f (forms-in (call-with-input-file f read))))))
  (define (pointer-store-offenders file-forms)
    (define aliases (pointer-aliases (append-map cdr file-forms)))
    (for*/list ([file+forms (in-list file-forms)]
                [form (in-list (pointer-stores (cdr file+forms) aliases))])
      (list (car file+forms) form)))
  (define polars-forms (source-forms (polars-sources)))
  (check > (length polars-forms) 30)
  (check-equal? (pointer-store-offenders polars-forms)
                '()
                "a string or Racket object stored by address in Racket memory: use _string-list")

  (define planted-root (make-temporary-directory "rkt-polars-audit-~a"))
  (for ([dir (in-list '("private" "tests"))])
    (make-directory (build-path planted-root dir)))
  (define planted (build-path planted-root "tests" "planted.rkt"))
  (with-output-to-file planted
    (lambda ()
      (displayln "#lang racket/base")
      (displayln (format "(define (planted-buffer) (~a 16))" 'malloc))
      (write '(define planted-type (_list i _string)))))
  (define planted-sources (polars-sources planted-root))
  (check-equal? (offenders raw-allocation planted-sources) (list (simplify-path planted)))
  (check-equal? (pointer-store-offenders (source-forms planted-sources))
                (list (list (simplify-path planted) '(_list i _string))))
  (delete-directory/files planted-root))
