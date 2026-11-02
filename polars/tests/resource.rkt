#lang racket/base

(module+ test
  (require rackunit
           (for-syntax racket/base)
           racket/match
           (only-in racket/file file->string)
           (only-in racket/list append-map)
           (only-in ffi/unsafe
                    _fun _int64 _pointer _size _string/utf-8 _void cast function-ptr ptr-ref
                    ptr-set!)
           (only-in polars/private/resource
                    _str _str-list _str/null _string-list with-raw-buffer with-release
                    with-release-pool with-releases)
           (only-in (submod polars/private/resource internal)
                    str-block->string str-block->strings string->str-block strings->c-array
                    strings->str-block)
           (only-in polars/tests/gc-pressure call-with-collections)
           (only-in polars/tests/generic/test-fixtures nul-names)
           (only-in polars/tests/test-helpers
                    module-text polars-dir polars-sources read-source with-planted-sources))

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
  (check-equal? (let ([v 1]) (with-release ([v (add1 v) release!]) v)) 2)
  (check-equal? released '(2))

  (check-equal? (let ([words 3])
                  (with-raw-buffer ([words words _int64])
                    (ptr-set! words _int64 2 7)
                    (ptr-ref words _int64 2)))
                7)

  (set! released '())
  (check-equal? (with-release ([a 'a release!]) (set! a 'z) a) 'z)
  (check-equal? released '(a))

  (set! released '())
  (check-equal? (with-release ([a 'a (lambda (v) (release! (list a v)))]) 'ok) 'ok)
  (check-equal? released '((a a)))

  (set! released '())
  (check-equal? (with-release ([a 1 release!] [b (add1 a) release!]) b) 2)
  (check-equal? released '(1 2))

  (set! released '())
  (check-exn #rx"^test: b$"
             (lambda () (with-release ([a 'a release!] [b (error 'test "b") release!]) 'not-reached)))
  (check-equal? released '(a))

  (set! released '())
  (define re-enter #f)
  (check-equal? (call-with-continuation-prompt
                 (lambda ()
                   (with-release ([a 'a release!])
                     (call-with-composable-continuation (lambda (k) (set! re-enter k)))
                     a)))
                'a)
  (check-exn #rx"^with-release: cannot re-enter the extent after its release$"
             (lambda () (call-with-continuation-prompt (lambda () (re-enter #f)))))
  (check-equal? released '(a))

  (set! released '())
  (define escaped (with-release ([a 'a release!]) (lambda () a)))
  (check-equal? (escaped) #f)
  (check-equal? released '(a))

  (set! released '())
  (check-equal? (let ([tags 10])
                  (with-releases ([tags ([i (in-range 2)]) (+ tags i) release!]) tags))
                '(10 11))

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

  (define str-lists
    (list '() '("") nul-names '("é" "東京 😀" "" "abcdefgh" "abcdefghi")
          (for/list ([i (in-range 300)]) (format "column ~a é 東京 😀" i))))
  (define-values (str-blocks block-collections)
    (call-with-collections
     (lambda ()
       (for*/list ([_ (in-range 200)] [xs (in-list str-lists)])
         (cons (strings->str-block xs) (map string->str-block xs))))))
  (check > block-collections 0)
  (collect-garbage)
  (check-equal? (for/list ([built (in-list str-blocks)])
                  (cons (str-block->strings (car built)) (map str-block->string (cdr built))))
                (for*/list ([_ (in-range 200)] [xs (in-list str-lists)]) (cons xs xs)))

  (define called-back '())
  (define ((call-back read) block)
    (collect-garbage)
    (set! called-back (cons (and block (read block)) called-back)))
  (define read-strings (function-ptr (call-back str-block->strings) (_fun _pointer -> _void)))
  (define read-string (function-ptr (call-back str-block->string) (_fun _pointer -> _void)))
  (define call-with-str-list (cast read-strings _pointer (_fun _str-list -> _void)))
  (define call-with-str (cast read-string _pointer (_fun _str -> _void)))
  (define call-with-str/null (cast read-string _pointer (_fun _str/null -> _void)))
  (for ([xs (in-list str-lists)])
    (call-with-str-list xs)
    (for-each call-with-str xs))
  (define (list-block-read xs)
    (match xs
      ['() #f]
      [_ xs]))
  (check-equal? (reverse called-back)
                (for*/list ([xs (in-list str-lists)]
                            [read (in-list (cons (list-block-read xs) xs))])
                  read))
  (set! called-back '())
  (call-with-str-list (list #"bytes" (string->path "a/path") "東京"))
  (call-with-str #"a\0b")
  (call-with-str/null #f)
  (call-with-str/null "x")
  (check-equal? (reverse called-back) '(("bytes" "a/path" "東京") "a\0b" #f "x"))
  (check-exn #rx"^_str-list: contract violation\n  expected: utf-8-name/c\n  given: 'b"
             (lambda () (call-with-str-list '("a" b))))
  (check-exn #rx"^_str-list: contract violation\n  expected: \\(listof utf-8-name/c\\)"
             (lambda () (call-with-str-list 'b)))
  (check-exn #rx"^_str: contract violation\n  expected: utf-8-name/c\n  given: #\"\\\\377\""
             (lambda () (call-with-str #"\377")))
  (check-exn #rx"^_str: contract violation" (lambda () (call-with-str/null 'b)))
  (check-equal? (reverse called-back) '(("bytes" "a/path" "東京") "a\0b" #f "x"))

  (define resource-module (simplify-path (build-path polars-dir "private" "resource.rkt")))
  (define raw-allocation #px"\\((?:malloc|free)\\s")
  (define (offenders pattern sources)
    (for/list ([f (in-list sources)]
               #:unless (equal? f resource-module)
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
    (for/list ([f (in-list sources)])
      (cons f (forms-in (read-source f)))))
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

  (define (mentions? form type)
    (for/or ([inner (in-list (forms-in form))]) (memq type inner)))
  (define (fun-result type)
    (match (member '-> type)
      [(list* '-> (list _ ': result) _) result]
      [(list* '-> result _) result]
      [_ #f]))
  (define (c-string-crossing form)
    (match form
      [(list* (or '_fun 'define-series-constructors) _) #:when (mentions? form '_rsstring)
       '_rsstring]
      [(list* 'define-compat _ (? list? type) _)
       (define result (fun-result type))
       (and (memq result '(_string _string/utf-8 _string*/utf-8)) result)]
      [_ #f]))
  (define (c-string-crossings file-forms)
    (for*/list ([file+forms (in-list file-forms)]
                [form (in-list (cdr file+forms))]
                [type (in-value (c-string-crossing form))]
                #:when type)
      (list (car file+forms) type)))
  (check-equal? (c-string-crossings (source-forms (polars-sources #:dirs '("private"))))
                '()
                "a C string crosses the boundary: use _str, _str-list, _rsstr or _rsstr-list")
  (with-planted-sources (root ["private/planted.rkt"
                               (module-text
                                '(define-compat x (_fun _pointer -> _rsstring))
                                '(define-compat y (_fun _pointer -> (r : _rsstring) -> r))
                                '(define-series-constructors s _rsstring "")
                                ''(_fun -> _rsstring)
                                '(define-compat z (_fun _pointer -> _string))
                                '(define-compat w (_fun _string -> (r : _string/utf-8) -> r))
                                '(define-compat v (_fun -> _string*/utf-8) #:c-id v)
                                '(define-compat kept (_fun _string -> _void)))])
    (define planted (simplify-path (build-path root "private" "planted.rkt")))
    (check-equal? (c-string-crossings (source-forms (polars-sources root #:dirs '("private"))))
                  (for/list ([type '(_rsstring _rsstring _rsstring _string _string/utf-8
                                     _string*/utf-8)])
                    (list planted type))))

  (define planted-text
    (format "#lang racket/base\n(define (planted-buffer) (~a 16))\n~s"
            'malloc '(define planted-type (_list i _string))))
  (with-planted-sources (root ["tests/planted.rkt" planted-text]
                              ["tests/resource.rkt" (format "#lang racket/base\n(~a 16)" 'malloc)])
    (define planted-sources (polars-sources root))
    (define (planted name) (simplify-path (build-path root "tests" name)))
    (check-equal? (sort (offenders raw-allocation planted-sources) path<?)
                  (sort (list (planted "planted.rkt") (planted "resource.rkt")) path<?))
    (check-equal? (pointer-store-offenders (source-forms planted-sources))
                  (list (list (planted "planted.rkt") '(_list i _string)))))

  (define (test-submodules forms)
    (for/list ([form (in-list forms)]
               #:when (match form
                        [(list* (or 'module 'module* 'module+) 'test _) #t]
                        [_ #f]))
      form))
  (define (inline-test-offenders sources)
    (for/list ([f (in-list sources)]
               #:unless (null? (test-submodules (forms-in (read-source f)))))
      f))
  (check-equal? (inline-test-offenders (polars-sources #:dirs '("private")))
                '()
                "a test submodule under polars/private: move it to the mirrored file under polars/tests")
  (with-planted-sources (root ["private/bracket.rkt" "#lang racket/base\n[module+ test 1]"]
                              ["private/spaced.rkt" "#lang racket/base\n( module+ test 2)"]
                              ["private/split.rkt" "#lang racket/base\n(module+\n  test 3)"]
                              ["private/star.rkt" "#lang racket/base\n(module* test #f 4)"]
                              ["private/nested.rkt"
                               "#lang racket/base\n(module+ internal (module test racket/base 5))"]
                              ["private/mentions.rkt"
                               (string-append "#lang racket/base\n;; (module+ test)\n"
                                              "#| (module+ test) |#\n#;(module+ test)\n"
                                              "(define s \"(module+ test)\")\n(module+ test-x 6)")])
    (check-equal? (map (lambda (f) (let-values ([(_dir name _must-be-dir?) (split-path f)])
                                     (path->string name)))
                       (sort (inline-test-offenders (polars-sources root #:dirs '("private")))
                             path<?))
                  '("bracket.rkt" "nested.rkt" "spaced.rkt" "split.rkt" "star.rkt"))))
