#lang racket/base

(require (only-in racket/contract/base -> contract-out or/c)
         racket/match
         (only-in polars/private/expr lazyframe-join)
         (only-in (submod polars/private/foreign internal)
                  dataframe-hstack/who dataframe-join-asof/who dataframe-join/who
                  dataframe-vstack/who)
         (only-in polars/private/join-options asof-keys frame-join-asof/c frame-join/c join-keys)
         (only-in polars/private/generic/core
                  dataframe? lazyframe? series? wrap-dataframe wrap-lazyframe))

(provide (contract-out
          [join (frame-join/c (or/c dataframe? lazyframe?) same-kind/c same-kind/c 'join/c)]
          [join-asof (frame-join-asof/c dataframe? 'join-asof/c)]
          [vstack (-> dataframe? dataframe? dataframe?)]
          [hstack (-> dataframe? series? ... dataframe?)]))

(define (same-kind/c left)
  (if (dataframe? left) dataframe? lazyframe?))

(define (join left right
              #:on [on #f] #:left-on [left-on #f] #:right-on [right-on #f]
              #:how [how 'inner])
  (match left
    [(? dataframe?)
     (define-values (lon ron) (join-keys how on left-on right-on))
     (wrap-dataframe (dataframe-join/who 'join left right lon ron how))]
    [_ (wrap-lazyframe
        (lazyframe-join left right #:on on #:left-on left-on #:right-on right-on #:how how))]))

(define (join-asof left right
                   #:on [on #f] #:left-on [left-on #f] #:right-on [right-on #f]
                   #:by [by #f] #:left-by [left-by #f] #:right-by [right-by #f]
                   #:strategy [strategy 'backward] #:tolerance [tolerance #f])
  (define-values (lon ron lby rby) (asof-keys on left-on right-on by left-by right-by))
  (wrap-dataframe
   (dataframe-join-asof/who 'join-asof left right lon ron lby rby strategy tolerance)))

(define (vstack top bottom)
  (wrap-dataframe (dataframe-vstack/who 'vstack top bottom)))

(define (hstack d . columns)
  (wrap-dataframe (dataframe-hstack/who 'hstack d columns)))

(module+ test
  (require rackunit
           (only-in threading ~>)
           (only-in polars/private/foreign dataframe-join polars-null)
           polars/private/generic/core
           (only-in polars/private/generic/ordering sort)
           (only-in polars/private/generic/reshape collect head lazy)
           (only-in polars/private/generic/test-fixtures column)
           (prefix-in contracted: (submod "..")))

  (define usr (dataframe (list (series '(1 2 3 4) #:name "uid" #:dtype 'i32)
                               (series '("alice" "bob" "carol" "dora") #:name "name"))))
  (define ord (dataframe (list (series '(1 2 2 5) #:name "uid" #:dtype 'i32)
                               (series '(10 20 30 40) #:name "amount" #:dtype 'i32))))
  (check-equal? (height (join usr ord #:on '("uid") #:how 'inner)) 3)
  (check-equal? (height (join usr ord #:on '("uid") #:how 'left)) 5)
  (check-equal? (height (join (head usr 2) (head ord 2) #:how 'cross)) 4)
  (check-equal? (sort (column-names (join usr ord #:on '("uid") #:how 'inner)) string<?)
                '("amount" "name" "uid"))
  (check-equal? (height (~> usr lazy (join (lazy ord) #:on '("uid") #:how 'inner) collect)) 3)
  (check-equal? (height (~> usr lazy (join (lazy ord) #:on '("uid") #:how 'semi) collect)) 2)
  (check-equal? (height (~> usr lazy (join (lazy ord) #:on '("uid") #:how 'anti) collect)) 2)
  (let ([crossed (join (dataframe (list (series '("a" "b") #:name "l")))
                       (dataframe (list (series '(1 2) #:name "r")))
                       #:how 'cross)])
    (check-equal? (map list (column crossed "l") (column crossed "r"))
                  '(("a" 1) ("a" 2) ("b" 1) ("b" 2))))

  (define (keyed-rows d)
    (define sorted (sort d '("uid" "amount")))
    (for/list ([name (in-list (column-names sorted))])
      (cons name (column sorted name))))
  (define joined-by-string (keyed-rows (contracted:join usr ord #:on '("uid") #:how 'left)))
  (for ([key (list #"uid" (string->path "uid"))])
    (check-equal? (keyed-rows (contracted:join usr ord #:on (list key) #:how 'left))
                  joined-by-string)
    (check-equal? (keyed-rows (contracted:join usr ord #:left-on (list key) #:right-on '("uid")
                                               #:how 'left))
                  joined-by-string)
    (check-equal? (keyed-rows (collect (contracted:join (lazy usr) (lazy ord) #:on (list key)
                                                        #:how 'left)))
                  joined-by-string)
    (check-equal? (keyed-rows (wrap-dataframe (dataframe-join usr ord #:on (list key) #:how 'left)))
                  joined-by-string))
  (let ([ticks (dataframe (list (series '(1 3 5) #:name "t") (series '("a" "a" "b") #:name "g")))]
        [marks (dataframe (list (series '(1 2 4) #:name "t") (series '("a" "b" "b") #:name "g")
                                (series '(10 20 40) #:name "o")))])
    (check-equal? (column (contracted:join-asof ticks marks #:on "t" #:by '("g")) "o") '(10 10 40))
    (for ([key (list #"t" (string->path "t"))])
      (check-equal? (column (contracted:join-asof ticks marks #:on key) "o") '(10 20 40))
      (check-equal? (column (contracted:join-asof ticks marks #:left-on key #:right-on "t") "o")
                    '(10 20 40)))
    (for ([key (list #"g" (string->path "g"))])
      (check-equal? (column (contracted:join-asof ticks marks #:on "t" #:by (list key)) "o")
                    '(10 10 40))
      (check-equal? (column (contracted:join-asof ticks marks #:on "t"
                                                  #:left-by (list key) #:right-by '("g"))
                            "o")
                    '(10 10 40))))

  (define more (dataframe (list (series '(5 6) #:name "uid" #:dtype 'i32)
                                (series '("eve" "frank") #:name "name"))))
  (check-equal? (height (vstack usr more)) 6)
  (check-equal? (column-names (vstack usr more)) '("uid" "name"))
  (let ([stacked (vstack (dataframe (list (series '(1 2) #:name "x")))
                         (dataframe (list (series (list polars-null 4) #:name "x"))))])
    (check-equal? (column stacked "x") (list 1 2 polars-null 4)))
  (check-equal? (column-names (hstack usr (series '(10 20 30 40) #:name "extra")))
                '("uid" "name" "extra"))
  (check-equal? (shape (hstack (dataframe '()) (series '(1 2 3) #:name "a"))) '(3 1))

  (let ([obs (dataframe (list (series '(1 3 5) #:name "time" #:dtype 'i32)
                              (series '(100 300 500) #:name "reading" #:dtype 'i32)))]
        [cal (dataframe (list (series '(1 2 4) #:name "time" #:dtype 'i32)
                              (series '(10 20 40) #:name "offset" #:dtype 'i32)))])
    (check-equal? (height (join-asof obs cal #:on "time" #:strategy 'backward)) 3)
    (check-equal? (column (join-asof obs cal #:on "time" #:tolerance 0) "offset")
                  (list 10 polars-null polars-null)))

  (define top (dataframe (list (series '(1 2) #:name "v"))))
  (check-equal? (column-names (hstack top (series '(10 20) #:name "w"))) '("v" "w"))
  (define keyed-left (dataframe (list (series '("a" "b") #:name "k") (series '(1 2) #:name "v"))))
  (define keyed-right (dataframe (list (series '("a" "c") #:name "k")
                                       (series '(10 30) #:name "w"))))
  (check-equal? (column (join keyed-left keyed-right #:on '("k") #:how 'inner) "w") '(10))
  (let ([by-bytes (contracted:join keyed-left keyed-right #:on '(#"k") #:how 'inner)])
    (check-equal? (map (lambda (name) (cons name (column by-bytes name))) (column-names by-bytes))
                  '(("k" "a") ("v" 1) ("w" 10))))
  (define readings (dataframe (list (series '(1 3 5) #:name "t")
                                    (series '(100 300 500) #:name "v"))))
  (define offsets (dataframe (list (series '(1 2 4) #:name "t")
                                   (series '(10 20 40) #:name "o"))))
  (check-equal? (column (join-asof readings offsets #:on "t") "o") '(10 20 40))
  (check-equal? (column (join-asof readings offsets #:on "t" #:tolerance 0) "o")
                (list 10 polars-null polars-null))

  (define (polars-failure? e) (and (exn:fail? e) (not (exn:fail:contract? e))))
  (define ints-x (dataframe (list (series '(1) #:name "x"))))
  (define strs-x (dataframe (list (series '("s") #:name "x"))))
  (define pair-xy (dataframe (list (series '(1) #:name "x") (series '(2) #:name "y"))))
  (define nulls-x (dataframe (list (series (list polars-null) #:name "x" #:dtype 'null))))
  (define refusals
    (list
     (list (lambda () (contracted:hstack top (series '(10) #:name "w"))) polars-failure?
           #rx"^hstack: [^\n]*height")
     (list (lambda () (contracted:join keyed-left (dataframe (list (series '(1 2) #:name "k")))
                                       #:on '("k")))
           polars-failure?
           #rx"^join: datatypes of join keys don't match - `k`: str on left does not match `k`: i64")
     (list (lambda () (contracted:join keyed-left keyed-right)) exn:fail:contract?
           #rx"^join: contract violation\n  must supply #:on, or #:left-on and #:right-on\n")
     (list (lambda () (contracted:join-asof readings offsets #:on "t" #:left-by '("v")))
           exn:fail:contract?
           #rx"^join-asof: contract violation\n  must supply both #:left-by and #:right-by\n")
     (list (lambda () (contracted:vstack nulls-x ints-x)) polars-failure?
           #rx"^vstack: type Int64 is incompatible with expected type Null: failed to vstack column 'x'$")
     (list (lambda () (contracted:vstack ints-x strs-x)) polars-failure?
           #rx"^vstack: type String is incompatible with expected type Int64: failed to vstack column 'x'$")
     (list (lambda () (contracted:vstack ints-x (dataframe (list (series '(1) #:name "y")))))
           polars-failure?
           #rx"^vstack: [^\n]*unable to vstack, column names don't match: \"x\" and \"y\"$")
     (list (lambda () (contracted:vstack ints-x 5)) exn:fail:contract?
           #rx"^vstack: contract violation\n  expected: dataframe\\?\n  given: 5\n")
     (list (lambda () (contracted:hstack ints-x (series '(2) #:name "x"))) polars-failure?
           #rx"^hstack: [^\n]*'x'")
     (list (lambda () (contracted:hstack ints-x (series '(2 3) #:name "y"))) polars-failure?
           #rx"^hstack: [^\n]*height")
     (list (lambda () (contracted:hstack ints-x (list (series '(2) #:name "y"))))
           exn:fail:contract? #rx"^hstack: contract violation\n  expected: series\\?\n  given: '\\(")
     (list (lambda () (contracted:hstack ints-x 5)) exn:fail:contract?
           #rx"^hstack: contract violation\n  expected: series\\?\n  given: 5\n")
     (list (lambda () (contracted:hstack ints-x strs-x)) exn:fail:contract?
           #rx"^hstack: contract violation\n  expected: series\\?\n  given: ")
     (list (lambda () (contracted:join ints-x strs-x #:on '("x"))) polars-failure?
           #rx"^join: datatypes of join keys don't match - `x`: i64 on left does not match `x`: str")
     (list (lambda () (contracted:join ints-x ints-x #:on '("y"))) polars-failure?
           #rx"^join: [^\n]*\"y\"")
     (list (lambda () (contracted:join pair-xy pair-xy #:left-on '("x" "y") #:right-on '("x")))
           polars-failure?
           #rx"^join: the number of columns given as join key \\(left: 2, right:1\\) should be equal$")
     (list (lambda () (~> pair-xy lazy
                          (contracted:join (lazy pair-xy) #:left-on '("x" "y") #:right-on '("x"))
                          collect))
           polars-failure?
           #rx"^collect: [^\n]*the number of columns given as join key \\(left: 2, right:1\\) should be equal$")
     (list (lambda () (contracted:join ints-x ints-x #:on '("x") #:how 'sideways))
           exn:fail:contract? #rx"^join: contract violation\n  expected: [^\n]*inner[^\n]*\n  given: 'sideways\n")
     (list (lambda () (contracted:join ints-x ints-x)) exn:fail:contract?
           #rx"^join: contract violation\n  must supply #:on, or #:left-on and #:right-on\n")
     (list (lambda () (contracted:join ints-x ints-x #:left-on '("x"))) exn:fail:contract?
           #rx"^join: contract violation\n  must supply #:on, or #:left-on and #:right-on\n")
     (list (lambda () (contracted:join ints-x 5 #:on '("x"))) exn:fail:contract?
           #rx"^join: contract violation\n  expected: dataframe\\?\n  given: 5\n")
     (list (lambda () (contracted:join ints-x (lazy ints-x) #:on '("x"))) exn:fail:contract?
           #rx"^join: contract violation\n  expected: dataframe\\?\n  given: #<lazyframe")
     (list (lambda () (contracted:join (lazy ints-x) ints-x #:on '("x"))) exn:fail:contract?
           #rx"^join: contract violation\n  expected: lazyframe\\?\n  given: ")
     (list (lambda () (contracted:join 5 ints-x #:on '("x"))) exn:fail:contract?
           #rx"^join: contract violation\n  expected: \\(or/c dataframe\\? lazyframe\\?\\)\n  given: 5\n")
     (list (lambda () (contracted:join ints-x ints-x #:on "x")) exn:fail:contract?
           #rx"^join: contract violation\n  expected: [^\n]*non-empty-listof \\(or/c string\\? bytes\\? path\\?\\)[^\n]*\n  given: \"x\"\n")
     (list (lambda () (contracted:join ints-x ints-x #:on '(x))) exn:fail:contract?
           #rx"^join: contract violation\n  expected: [^\n]*\n  given: '\\(x\\)\n")
     (list (lambda () (contracted:join ints-x ints-x #:left-on '(5) #:right-on '("x")))
           exn:fail:contract? #rx"^join: contract violation\n  expected: [^\n]*\n  given: '\\(5\\)\n")
     (list (lambda () (contracted:join (lazy ints-x) (lazy ints-x) #:on (list 'x)))
           exn:fail:contract? #rx"^join: contract violation\n  expected: [^\n]*\n  given: '\\(x\\)\n")
     (list (lambda () (contracted:join-asof ints-x ints-x #:on "x" #:by '(y))) exn:fail:contract?
           #rx"^join-asof: contract violation\n  expected: [^\n]*\n  given: '\\(y\\)\n")
     (list (lambda () (contracted:join (lazy ints-x) (lazy ints-x) #:on '())) exn:fail:contract?
           #rx"^join: contract violation\n  expected: [^\n]*non-empty-listof[^\n]*\n  given: '\\(\\)\n")
     (list (lambda () (contracted:join-asof ints-x ints-x #:on "nope")) polars-failure?
           #rx"^join-asof: [^\n]*\"nope\"")
     (list (lambda () (contracted:join-asof ints-x ints-x #:on "x" #:strategy 'sideways))
           exn:fail:contract?
           #rx"^join-asof: contract violation\n  expected: [^\n]*backward[^\n]*\n  given: 'sideways\n")
     (list (lambda () (contracted:join-asof ints-x ints-x #:on '("x"))) exn:fail:contract?
           #rx"^join-asof: contract violation\n  expected: \\(or/c #f \\(or/c string\\? bytes\\? path\\?\\)\\)\n  given: '\\(\"x\"\\)\n")
     (list (lambda () (contracted:join-asof ints-x 5 #:on "x")) exn:fail:contract?
           #rx"^join-asof: contract violation\n  expected: dataframe\\?\n  given: 5\n")
     (list (lambda () (contracted:join-asof ints-x ints-x)) exn:fail:contract?
           #rx"^join-asof: contract violation\n  must supply #:on, or #:left-on and #:right-on\n")
     (list (lambda () (contracted:join-asof ints-x ints-x #:on "x" #:by "y")) exn:fail:contract?
           #rx"^join-asof: contract violation\n  expected: \\(or/c #f \\(listof \\(or/c string\\? bytes\\? path\\?\\)\\)\\)\n  given: \"y\"\n")
     (list (lambda () (contracted:join-asof ints-x ints-x #:on "x" #:by '("y") #:left-by '("y")))
           exn:fail:contract?
           #rx"^join-asof: contract violation\n  supply either #:by or #:left-by and #:right-by, not both\n")
     (list (lambda () (contracted:join-asof ints-x ints-x #:on "x" #:left-by '("y")))
           exn:fail:contract?
           #rx"^join-asof: contract violation\n  must supply both #:left-by and #:right-by\n")
     (list (lambda () (contracted:join-asof pair-xy pair-xy #:on "x"
                                            #:left-by '("x" "y") #:right-by '("y")))
           exn:fail:contract?
           #rx"^join-asof: contract violation\n  #:left-by has 2 names and #:right-by 1; they must be equal\n")
     (list (lambda () (contracted:join-asof ints-x ints-x #:on "x" #:tolerance (expt 2 63)))
           exn:fail:contract?
           #rx"^join-asof: contract violation\n  expected: [^\n]*\n  given: 9223372036854775808\n")
     (list (lambda () (contracted:join-asof ints-x ints-x #:on "x" #:tolerance 'x))
           exn:fail:contract? #rx"^join-asof: contract violation\n  expected: [^\n]*\n  given: 'x\n")))
  (for ([refusal (in-list refusals)])
    (match-define (list thunk kind rx) refusal)
    (check-exn (lambda (e) (and (kind e) (regexp-match? rx (exn-message e)))) thunk
               (object-name rx))))
