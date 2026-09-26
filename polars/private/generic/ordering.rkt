#lang racket/base

(require (prefix-in base: (only-in racket/base sort))
         (only-in racket/contract/base
                  ->i contract-out flat-named-contract non-empty-listof none/c or/c
                  procedure-arity-includes/c rename-contract the-unsupplied-arg
                  unsupplied-arg?)
         (only-in polars/private/expr
                  Expr-ptr? expr-gather expr-rank expr-sort expr-sort-by lazyframe-sort)
         (only-in polars/private/foreign
                  dataframe-sort series-sort sort-flags-mismatch sort-flags/c)
         (only-in polars/private/generic/core
                  dataframe? lazyframe? series? wrap-dataframe wrap-lazyframe wrap-series)
         (only-in polars/private/generic/expr-util ->col-expr col-expr/c))

(provide (contract-out [sort sort/c] [sort-by sort-by/c])
         rank gather)

(define (sort-frame? x) (or (dataframe? x) (lazyframe? x)))

(define (->keys by) (if (list? by) by (list by)))

(define sortable/c
  (flat-named-contract 'sortable/c
                       (or/c dataframe? lazyframe? series? Expr-ptr? string? list?)))
(define sort-keys/c
  (flat-named-contract 'sort-keys/c (or/c string? (non-empty-listof string?))))
(define sort-by-keys/c
  (flat-named-contract 'sort-by-keys/c (or/c col-expr/c (non-empty-listof col-expr/c))))
(define frame-only/c (flat-named-contract 'frame-only/c none/c))
(define list-only/c (flat-named-contract 'list-only/c none/c))
(define frame-or-list-only/c (flat-named-contract 'frame-or-list-only/c none/c))
(define polars-only/c (flat-named-contract 'polars-only/c none/c))

(define (polars-flag/c x)
  (cond [(sort-frame? x) sort-flags/c]
        [(list? x) polars-only/c]
        [else boolean?]))

(define sort/c
  (rename-contract
   (->i ([x sortable/c])
        ([by (x) (cond [(sort-frame? x) sort-keys/c]
                       [(list? x) (procedure-arity-includes/c 2)]
                       [else frame-or-list-only/c])]
         #:descending [descending (x) (polars-flag/c x)]
         #:nulls-last [nulls-last (x) (polars-flag/c x)]
         #:maintain-order [maintain-order (x) (if (sort-frame? x) boolean? frame-only/c)]
         #:key [extract-key (x)
                            (if (list? x) (or/c #f (procedure-arity-includes/c 1)) list-only/c)]
         #:cache-keys? [cache-keys? (x) (if (list? x) boolean? list-only/c)])
        #:pre/desc (x by descending nulls-last)
        (cond [(and (sort-frame? x) (unsupplied-arg? by))
               "sorting a dataframe or lazyframe needs sort keys"]
              [(and (list? x) (unsupplied-arg? by))
               "racket/base sort needs a less-than? procedure"]
              [(sort-frame? x) (sort-flags-mismatch by descending nulls-last)]
              [else #t])
        [result (x) (cond [(dataframe? x) dataframe?]
                          [(lazyframe? x) lazyframe?]
                          [(series? x) series?]
                          [(list? x) list?]
                          [else Expr-ptr?])])
   'sort/c))

(define sort-by/c
  (rename-contract
   (->i ([x col-expr/c] #:by [by sort-by-keys/c])
        (#:descending [descending sort-flags/c]
         #:nulls-last [nulls-last sort-flags/c]
         #:maintain-order [maintain-order boolean?])
        #:pre/desc (by descending nulls-last)
        (sort-flags-mismatch by descending nulls-last)
        [result Expr-ptr?])
   'sort-by/c))

(define (sort x [by the-unsupplied-arg]
              #:descending [descending #f]
              #:nulls-last [nulls-last #f]
              #:maintain-order [maintain-order #f]
              #:key [extract-key #f]
              #:cache-keys? [cache-keys? #f])
  (cond
    [(dataframe? x)
     (wrap-dataframe
      (dataframe-sort x (->keys by) #:descending descending #:nulls-last nulls-last
                      #:maintain-order maintain-order))]
    [(lazyframe? x)
     (wrap-lazyframe
      (lazyframe-sort x (->keys by) #:descending descending #:nulls-last nulls-last
                      #:maintain-order maintain-order))]
    [(series? x)
     (wrap-series (series-sort x #:descending descending #:nulls-last nulls-last))]
    [(list? x)
     (if extract-key
         (base:sort x by #:key extract-key #:cache-keys? cache-keys?)
         (base:sort x by))]
    [else
     (expr-sort (->col-expr 'sort x) #:descending descending #:nulls-last nulls-last)]))

(define (sort-by x #:by by
                 #:descending [descending #f]
                 #:nulls-last [nulls-last #f]
                 #:maintain-order [maintain-order #f])
  (expr-sort-by (->col-expr 'sort-by x) #:by by #:descending descending
                #:nulls-last nulls-last #:maintain-order maintain-order))

;; rank: #:method 'average | 'min | 'max | 'dense | 'ordinal, #:descending, #:seed.
(define (rank x #:method [method 'average] #:descending [descending #f] #:seed [seed #f])
  (expr-rank (->col-expr 'rank x) #:method method #:descending descending #:seed seed))

;; gather: pick rows by position (an Expr, a Series, or a list of ints).
(define (gather x indices)
  (expr-gather (->col-expr 'gather x) indices))

(module+ test
  (require rackunit (only-in threading ~>)
           polars/private/generic/core
           polars/private/generic/reductions   ; alias
           polars/private/generic/reshape)     ; with-columns / select
  (define df (dataframe (list (series '(30 10 50 20 40) #:name "x" #:dtype 'i64)
                              (series '("b" "a" "b" "a" "b") #:name "g"))))
  ;; rank is length-preserving -> with-columns
  (define ranked (~> df (with-columns (alias (rank "x" #:method 'dense) "r"))))
  ;; x = (30 10 50 20 40) -> dense ranks (3 1 5 2 4)
  (check-equal? (for/list ([i (in-range 5)]) (ref (ref ranked #:columns "r") i))
                '(3 1 5 2 4))
  ;; sort-by / gather collapse or reorder -> select (all columns share a length)
  (define sorted (select df (alias (sort-by "x" #:by "x") "xs")))
  (check-equal? (for/list ([i (in-range 5)]) (ref (ref sorted #:columns "xs") i))
                '(10 20 30 40 50))
  (define gathered (select df (alias (gather "x" '(0 2 4)) "xg")))
  (check-equal? (for/list ([i (in-range 3)]) (ref (ref gathered #:columns "xg") i))
                '(30 50 40)))

(module+ test
  (require (only-in gregor datetime datetime<?)
           (only-in racket/contract exn:fail:contract:blame?)
           (only-in racket/list make-list range remove-duplicates take)
           (only-in racket/math nan?)
           (prefix-in contracted: (submod ".."))
           polars/private/generic/test-fixtures)

  (define (series-cells s) (for/list ([i (in-range (len s))]) (ref s i)))

  (define (frame-rows d)
    (define cols (for/list ([name (in-list (column-names d))])
                   (list->vector (series-cells (ref d #:columns name)))))
    (for/vector ([i (in-range (height d))])
      (for/vector ([c (in-list cols)]) (vector-ref c i))))

  (define (flag-lists k)
    (if (zero? k)
        '(())
        (for*/list ([b '(#f #t)] [rest (in-list (flag-lists (sub1 k)))]) (cons b rest))))

  (define sort-pools
    (hash 'int64 '(-2 -1 0 1 2)
          'int32 '(-2 -1 0 1 2)
          'float64 (list -1.5 0.0 2.25 +inf.0 -inf.0 +nan.0)
          'string '("" "a" "b" "B" "é")
          'boolean '(#t #f)
          'datetime (list (datetime 1999 12 31) (datetime 2020 1 1) (datetime 2020 1 1 12))))

  (define (random-sort-frame rng dtypes n density #:payload? [payload? #t])
    (define m (max n 1))
    (define (cell dtype)
      (define pool (hash-ref sort-pools dtype))
      (if (< (random rng) density) polars-null (list-ref pool (random (length pool) rng))))
    (define keys
      (for/list ([dtype (in-list dtypes)] [j (in-naturals)])
        (series (for/list ([_ (in-range m)]) (cell dtype)) #:name (format "k~a" j) #:dtype dtype)))
    (define rows (series (range m) #:name "row" #:dtype 'int64))
    (define d (dataframe (if payload? (append keys (list rows)) keys)))
    (if (zero? n) (head d 0) d))

  (define (sort-value-compare a b)
    (cond
      [(and (flonum? a) (nan? a)) (if (and (flonum? b) (nan? b)) 0 1)]
      [(and (flonum? b) (nan? b)) -1]
      [(real? a) (cond [(< a b) -1] [(< b a) 1] [else 0])]
      [(string? a) (cond [(string<? a b) -1] [(string<? b a) 1] [else 0])]
      [(boolean? a) (cond [(eq? a b) 0] [a 1] [else -1])]
      [else (cond [(datetime<? a b) -1] [(datetime<? b a) 1] [else 0])]))

  (define (sort-key-compare a b descending? nulls-last?)
    (cond
      [(and (polars-null? a) (polars-null? b)) 0]
      [(polars-null? a) (if nulls-last? 1 -1)]
      [(polars-null? b) (if nulls-last? -1 1)]
      [descending? (sort-value-compare b a)]
      [else (sort-value-compare a b)]))

  (define (reference-sort-order rows key-idxs descending nulls-last)
    (define (row<? i j)
      (let loop ([ks key-idxs] [ds descending] [ls nulls-last])
        (and (pair? ks)
             (let ([c (sort-key-compare (vector-ref (vector-ref rows i) (car ks))
                                        (vector-ref (vector-ref rows j) (car ks))
                                        (car ds) (car ls))])
               (or (negative? c) (and (zero? c) (loop (cdr ks) (cdr ds) (cdr ls))))))))
    (base:sort (range (vector-length rows)) row<?))

  (define (sort-result-ok? out expected rows key-idxs #:exact? exact? #:payload? payload?)
    (define got (frame-rows out))
    (define (payload-of row) (vector-ref row (sub1 (vector-length row))))
    (cond
      [exact? (equal? got (list->vector expected))]
      [else
       (and (= (vector-length got) (length expected))
            (for*/and ([(g e) (in-parallel got expected)] [k (in-list key-idxs)])
              (equal? (vector-ref g k) (vector-ref e k)))
            (or (not payload?)
                (let ([ids (for/list ([g (in-vector got)]) (payload-of g))])
                  (and (equal? ids (remove-duplicates ids))
                       (for/and ([g (in-vector got)] [id (in-list ids)])
                         (equal? g (vector-ref rows id)))))))]))

  (define (sort-law-case d dtypes payload?)
    (define k (length dtypes))
    (define keys (for/list ([j (in-range k)]) (format "k~a" j)))
    (define key-idxs (range k))
    (define rows (frame-rows d))
    (define n (vector-length rows))
    (for* ([ds (in-list (flag-lists k))] [ls (in-list (flag-lists k))] [exact? '(#t #f)])
      (define expected
        (for/list ([i (in-list (reference-sort-order rows key-idxs ds ls))]) (vector-ref rows i)))
      (define why (format "~s" (list dtypes n ds ls exact?)))
      (define (ok? out [m n])
        (sort-result-ok? out (take expected m) rows key-idxs #:exact? exact? #:payload? payload?))
      (check-true (ok? (sort d keys #:descending ds #:nulls-last ls #:maintain-order exact?)) why)
      (check-true (ok? (collect (sort (lazy d) keys #:descending ds #:nulls-last ls
                                      #:maintain-order exact?)))
                  why)
      (let ([m (quotient (add1 n) 2)])
        (check-true (ok? (~> d lazy (sort keys #:descending ds #:nulls-last ls
                                          #:maintain-order exact?)
                             (head m) collect)
                         m)
                    why)))
    (for* ([d1 '(#f #t)] [l1 '(#f #t)])
      (check-equal? (frame-rows (sort d keys #:descending d1 #:nulls-last l1 #:maintain-order #t))
                    (frame-rows (sort d keys #:descending (make-list k d1)
                                      #:nulls-last (make-list k l1) #:maintain-order #t))))
    (define (schema x) (for/list ([name (in-list (column-names x))])
                         (list name (dtype (ref x #:columns name)))))
    (check-equal? (schema (sort d keys #:descending #t #:nulls-last #t)) (schema d))
    (check-equal? (schema (collect (sort (lazy d) keys #:descending #t #:nulls-last #t))) (schema d))
    (check-equal? (frame-rows d) rows))

  (define (sort-column-laws d dtypes)
    (define rows (frame-rows d))
    (for* ([j (in-range (length dtypes))] [ds '(#f #t)] [ls '(#f #t)])
      (define name (format "k~a" j))
      (define expected (for/list ([i (in-list (reference-sort-order rows (list j) (list ds) (list ls)))])
                         (vector-ref (vector-ref rows i) j)))
      (define why (format "~s" (list (list-ref dtypes j) (vector-length rows) ds ls)))
      (define s (ref d #:columns name))
      (define one (select d name))
      (define (col-of out) (column out name))
      (check-equal? (series-cells (sort s #:descending ds #:nulls-last ls)) expected why)
      (check-equal? (series-cells (sort (sort s #:descending ds) #:descending ds #:nulls-last ls))
                    expected why)
      (check-equal? (col-of (select d (sort name #:descending ds #:nulls-last ls))) expected why)
      (check-equal? (col-of (~> d lazy (select (sort (col name) #:descending ds #:nulls-last ls))
                                collect))
                    expected why)
      (check-equal? (col-of (select (sort d name #:descending ds)
                                    (sort name #:descending ds #:nulls-last ls)))
                    expected why)
      (check-equal? (col-of (sort one name #:descending ds #:nulls-last ls)) expected why)
      (check-equal? (col-of (sort (sort one name #:descending ds) name
                                  #:descending ds #:nulls-last ls))
                    expected why)
      (check-equal? (col-of (~> d lazy (sort name #:descending ds #:nulls-last ls)
                                (select name) collect))
                    expected why)
      (check-equal? (col-of (~> (sort d name #:descending ds) lazy
                                (sort name #:descending ds #:nulls-last ls)
                                (select name) collect))
                    expected why)))

  (define (sort-by-laws d k)
    (define keys (for/list ([j (in-range k)]) (format "k~a" j)))
    (define rows (frame-rows d))
    (for* ([ds (in-list (flag-lists k))] [ls (in-list (flag-lists k))])
      (define order (reference-sort-order rows (range k) ds ls))
      (define why (format "~s" (list k (vector-length rows) ds ls)))
      (check-equal? (column (select d (sort-by "row" #:by keys #:descending ds #:nulls-last ls
                                               #:maintain-order #t))
                            "row")
                    order why)
      (check-equal? (column (select d (sort-by (col "row") #:by (map col keys) #:descending ds
                                               #:nulls-last ls #:maintain-order #t))
                            "row")
                    order why)
      (for ([j (in-range k)] [key (in-list keys)])
        (check-equal? (column (select d (sort-by key #:by keys #:descending ds #:nulls-last ls)) key)
                      (for/list ([i (in-list order)]) (vector-ref (vector-ref rows i) j))
                      why))))

  (define nl-df (dataframe (list (series (list 3 polars-null 1 polars-null 2) #:name "a")
                                 (series (list "x" "y" polars-null "x" "y") #:name "b"))))
  (check-equal? (column (sort nl-df "a") "a") (list polars-null polars-null 1 2 3))
  (check-equal? (column (sort nl-df "a" #:descending #t) "a") (list polars-null polars-null 3 2 1))
  (check-equal? (column (sort nl-df "a" #:nulls-last #t) "a") (list 1 2 3 polars-null polars-null))
  (check-equal? (column (sort nl-df "a" #:descending #t #:nulls-last #t) "a")
                (list 3 2 1 polars-null polars-null))
  (let ([d (sort nl-df '("b" "a") #:descending '(#f #t) #:nulls-last '(#t #f))])
    (check-equal? (column d "a") (list polars-null 3 polars-null 2 1))
    (check-equal? (column d "b") (list "x" "x" "y" "y" polars-null)))
  (check-equal? (column (sort nl-df "a" #:nulls-last '(#t)) "a")
                (column (sort nl-df '("a") #:nulls-last #t) "a"))
  (check-equal? (series-cells (sort (ref nl-df #:columns "a") #:descending #t #:nulls-last #t))
                (list 3 2 1 polars-null polars-null))
  (check-equal? (column (select nl-df (sort "a" #:descending #t #:nulls-last #t)) "a")
                (list 3 2 1 polars-null polars-null))
  (check-equal? (column (select nl-df (sort (col "a") #:descending #t)) "a")
                (list polars-null polars-null 3 2 1))
  (let ([d (with-columns nl-df (alias (sort "a") "s"))])
    (check-equal? (column-names d) '("a" "b" "s"))
    (check-equal? (column d "a") (column nl-df "a"))
    (check-equal? (column d "s") (list polars-null polars-null 1 2 3)))
  (let* ([g (dataframe (list (series '("a" "a" "b" "b" "c") #:name "g")
                             (series (list 1 polars-null 3 4 polars-null) #:name "v")))]
         [out (~> g (group-by "g")
                  (agg (alias (first (sort "v" #:descending #t #:nulls-last #t)) "top_nl")
                       (alias (first (sort "v" #:descending #t)) "top_nf")
                       (alias (max "v") "max")))])
    (check-equal? (for/hash ([k (in-list (column out "g"))] [nl (in-list (column out "top_nl"))]
                             [nf (in-list (column out "top_nf"))] [m (in-list (column out "max"))])
                    (values k (list nl nf m)))
                  (hash "a" (list 1 polars-null 1)
                        "b" (list 4 4 4)
                        "c" (list polars-null polars-null polars-null))))
  (let* ([delays (for/list ([i (in-range 300)])
                   (if (zero? (modulo i 7)) polars-null (- (modulo (* i 37) 211) 100)))]
         [d (dataframe (list (series delays #:name "delay") (series (range 300) #:name "id")))]
         [want (lambda (k) (take (base:sort (filter number? delays) >) k))])
    (for ([k '(1 5 60)])
      (check-equal? (column (~> d (sort "delay" #:descending #t #:nulls-last #t) (head k)) "delay")
                    (want k))
      (check-equal? (column (~> (select d "delay") (sort "delay" #:descending #t #:nulls-last #t)
                                (head k))
                            "delay")
                    (want k))))

  (define ranked-lazy
    (~> ops-df lazy
        (group-by "group")
        (agg (alias (sum (col "value")) "sum_value"))
        (sort "sum_value" #:descending #t)
        collect))
  (check-equal? (column ranked-lazy "group") '("b" "a" "c"))
  (check-equal? (column ranked-lazy "sum_value") '(37 35 18))
  (check-equal? (column (sort ops-df '("group" "value") #:descending '(#f #t)) "value")
                '(25 10 30 7 18))
  (check-equal? (series-cells (sort v64)) '(7 10 18 25 30))
  (check-equal? (series-cells (sort v64 #:descending #t)) '(30 25 18 10 7))

  (define-syntax-rule (check-blame rx call)
    (check-exn (lambda (e) (and (exn:fail:contract:blame? e) (regexp-match? rx (exn-message e))))
               (lambda () call)))
  (define lengths-rx "the length of #:nulls-last \\(1\\) does not match the number of sort keys \\(2\\)")
  (check-blame #rx"^sort: contract violation.*expected: sortable/c" (contracted:sort 42))
  (check-blame #rx"^sort: contract violation.*racket/base sort needs a less-than\\? procedure"
               (contracted:sort '(3 1 2)))
  (check-blame #rx"^sort: contract violation.*expected: polars-only/c"
               (contracted:sort '(3 1 2) < #:descending #t))
  (check-blame #rx"^sort: contract violation.*expected: polars-only/c"
               (contracted:sort '(3 1 2) < #:nulls-last #t))
  (check-blame #rx"^sort: contract violation.*expected: frame-only/c"
               (contracted:sort '(3 1 2) < #:maintain-order #t))
  (check-blame #rx"^sort: contract violation.*procedure-arity-includes/c 2"
               (contracted:sort '(3 1 2) "x"))
  (for ([frame (list ops-df (lazy ops-df))])
    (check-blame #rx"^sort: contract violation.*sorting a dataframe or lazyframe needs sort keys"
                 (contracted:sort frame)))
  (for ([by (list '() 'group (col "group"))])
    (check-blame #rx"^sort: contract violation.*expected: sort-keys/c" (contracted:sort ops-df by)))
  (check-blame (pregexp (string-append "^sort: contract violation.*" lengths-rx))
               (contracted:sort ops-df '("group" "value") #:nulls-last '(#t)))
  (check-blame #rx"^sort: contract violation.*#:descending \\(2\\) does not match the number of sort keys \\(1\\)"
               (contracted:sort ops-df "value" #:descending '(#t #f)))
  (check-blame #rx"^sort: contract violation.*\\(1\\) does not match the number of sort keys \\(2\\)"
               (contracted:sort (lazy ops-df) '("group" "value") #:descending '(#t)))
  (check-blame #rx"^sort: contract violation.*expected: sort-flags/c"
               (contracted:sort ops-df "value" #:nulls-last 1))
  (check-blame #rx"^sort: contract violation.*expected: boolean\\?"
               (contracted:sort ops-df "value" #:maintain-order 'yes))
  (check-blame #rx"^sort: contract violation.*expected: list-only/c"
               (contracted:sort ops-df "value" #:key car))
  (check-blame #rx"^sort: contract violation.*expected: list-only/c" (contracted:sort v64 #:key car))
  (check-blame #rx"^sort: contract violation.*expected: frame-or-list-only/c"
               (contracted:sort v64 "value"))
  (check-blame #rx"^sort: contract violation.*expected: frame-or-list-only/c"
               (contracted:sort (col "value") "x"))
  (check-blame #rx"^sort: contract violation.*expected: frame-only/c"
               (contracted:sort v64 #:maintain-order #t))
  (check-blame #rx"^sort: contract violation.*expected: frame-only/c"
               (contracted:sort "value" #:maintain-order #t))
  (check-blame #rx"^sort: contract violation.*expected: boolean\\?"
               (contracted:sort v64 #:nulls-last '(#t)))
  (check-blame #rx"^sort: contract violation.*expected: boolean\\?"
               (contracted:sort (col "value") #:descending '(#t)))
  (check-blame #rx"^sort-by: contract violation.*col-expr/c" (contracted:sort-by 5 #:by "x"))
  (check-blame #rx"^sort-by: contract violation.*sort-by-keys/c" (contracted:sort-by "x" #:by '()))
  (check-blame (pregexp (string-append "^sort-by: contract violation.*" lengths-rx))
               (contracted:sort-by "x" #:by '("a" "b") #:nulls-last '(#t)))
  (check-blame #rx"^sort-by: contract violation.*sort-flags/c"
               (contracted:sort-by "x" #:by "a" #:descending 'yes))
  (check-blame #rx"^sort-by: contract violation.*boolean\\?"
               (contracted:sort-by "x" #:by "a" #:maintain-order 1))

  (let-values ([(required accepted) (procedure-keywords contracted:sort)])
    (check-equal? required '())
    (check-equal? accepted '(#:cache-keys? #:descending #:key #:maintain-order #:nulls-last)))
  (let-values ([(required accepted) (procedure-keywords contracted:sort-by)])
    (check-equal? required '(#:by))
    (check-equal? accepted '(#:by #:descending #:maintain-order #:nulls-last)))
  (check-equal? (contracted:sort '((3 . a) (1 . b) (3 . c)) < #:key car) '((1 . b) (3 . a) (3 . c)))
  (check-equal? (contracted:sort '((3 . a) (1 . b) (3 . c)) < #:key car #:cache-keys? #t)
                '((1 . b) (3 . a) (3 . c)))
  (check-equal? (contracted:sort '() <) '())
  (check-equal? (contracted:sort '(3 1 2) <) '(1 2 3))

  (check-exn (lambda (e) (and (not (exn:fail:contract:blame? e))
                              (regexp-match? #rx"^dataframe-sort: failed to sort .*nope"
                                             (exn-message e))))
             (lambda () (contracted:sort ops-df "nope")))
  (define lazy-missing (contracted:sort (lazy ops-df) "nope"))
  (check-pred lazyframe? lazy-missing)
  (check-exn #rx"^lazyframe-collect: failed to collect the query: .*nope"
             (lambda () (collect lazy-missing)))

  (define dtypes '(int64 int32 float64 string boolean datetime))
  (for* ([dtype (in-list dtypes)] [shape (in-list '((0 7) (1/4 1) (3/4 23) (1 5)))])
    (define d (random-sort-frame (vector->pseudo-random-generator (vector 82 95 88 1 2 3))
                                 (list dtype) (cadr shape) (car shape)))
    (sort-law-case d (list dtype) #t)
    (sort-law-case (select d "k0") (list dtype) #f)
    (sort-column-laws d (list dtype))
    (sort-by-laws d 1))
  (define rng (vector->pseudo-random-generator (vector 4 8 15 16 23 42)))
  (for* ([k '(2 3)] [i (in-range 10)])
    (define ks (for/list ([_ (in-range k)]) (list-ref dtypes (random (length dtypes) rng))))
    (define n (if (zero? i) 0 (list-ref '(0 1 2 5 17 40) (random 6 rng))))
    (define d (random-sort-frame rng ks n (list-ref '(0 1/4 3/4 1) (random 4 rng))))
    (sort-law-case d ks #t)
    (sort-column-laws d ks)
    (sort-by-laws d k)))
