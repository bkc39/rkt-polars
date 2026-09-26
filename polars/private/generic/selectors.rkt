#lang racket/base

(require racket/contract
         (only-in polars/private/expr Expr-ptr? expr-all expr-exclude multi-column-expr?))

(provide (contract-out
          [all (-> Expr-ptr?)]
          [exclude (->* (multi-column-expr? (or/c string? regexp?))
                        #:rest (listof (or/c string? regexp?))
                        Expr-ptr?)]))

(define all expr-all)

(define (exclude e name . names)
  (expr-exclude e (cons name names)))

(module+ test
  (require rackunit
           (only-in gregor datetime)
           (only-in threading ~>)
           (prefix-in contracted: (submod ".."))
           polars/private/generic/core
           polars/private/generic/operators
           polars/private/generic/reductions
           polars/private/generic/reshape
           polars/private/generic/test-fixtures)

  (define people
    (dataframe
     (list (series '("Alice Archer" "Ben Brown" "Chloe Cooper" "Daniel Donovan")
                   #:name "name")
           (series (list (datetime 1997 1 10) (datetime 1985 2 15)
                         (datetime 1983 3 22) (datetime 1981 4 30))
                   #:name "birthdate")
           (series '(57.9 72.5 53.6 83.1) #:name "weight")
           (series '(1.56 1.77 1.65 1.75) #:name "height"))))
  (define people/date (with-columns people (cast "birthdate" 'date)))
  (define iris
    (dataframe (list (series '(5.1 4.9) #:name "sepal_length")
                     (series '(3.5 3.0) #:name "sepal_width")
                     (series '(1.4 1.3) #:name "petal_length")
                     (series '(0.2 0.2) #:name "petal_width")
                     (series '("setosa" "setosa") #:name "species"))))
  (define ints-only (dataframe (list (series '(1 2) #:name "a" #:dtype 'i32))))

  (check-equal? (column-names (select people (all))) (column-names people))
  (check-equal? (format "~a" (select people (all))) (format "~a" people))
  (check-pred lazyframe? (select (lazy people) (all)))
  (check-equal? (format "~a" (~> people lazy (select (all)) collect))
                (format "~a" people))

  (check-equal? (column-names (select ops-df (exclude (all) "group")))
                '("value" "cost"))
  (check-equal? (format "~a" (select ops-df (exclude (all) "group")))
                (format "~a" (drop ops-df "group")))
  (check-equal? (column-names (select ops-df (exclude (all) "group" "cost")))
                '("value"))
  (check-equal? (column-names (select ops-df (~> (all) (exclude "group") (exclude "cost"))))
                '("value"))
  (check-equal? (column-names (select ops-df (exclude (all) "nope")))
                '("group" "value" "cost"))
  (check-equal? (column-names (select iris (exclude (all) #rx"^sepal_")))
                '("petal_length" "petal_width" "species"))
  (check-equal? (column-names (select people (exclude (col 'float64) "height")))
                '("weight"))
  (check-equal? (column-names (~> ops-df (group-by "group") (agg (sum (exclude (all) "cost")))))
                '("group" "value"))

  (check-equal? (column-names (select people (col 'float64))) '("weight" "height"))
  (check-equal? (column-names (select people (col 'f64))) '("weight" "height"))
  (check-equal? (column-names (select people (col 'string))) '("name"))
  (check-equal? (column-names (select people (col 'str))) '("name"))
  (check-equal? (column-names (select people/date (col 'date))) '("birthdate"))
  (check-equal? (column-names (select people (col '(datetime milliseconds)))) '("birthdate"))
  (check-equal? (column-names (select people (col (~> people (ref "birthdate") dtype))))
                '("birthdate"))
  (check-equal? (column-names (select people (col 'datetime))) '())
  (check-equal? (shape (select ints-only (col 'float64))) '(0 0))

  (check-equal? (column-names (select iris (col #rx"^sepal_")))
                '("sepal_length" "sepal_width"))
  (check-equal? (column-names (select iris (col #rx"_width$")))
                '("sepal_width" "petal_width"))
  (check-equal? (column-names (select iris (col #rx"tal")))
                '("petal_length" "petal_width"))
  (check-equal? (column-names (select iris (col #rx"^species$"))) '("species"))
  (check-equal? (column-names (select iris (col #rx"length|species")))
                '("sepal_length" "petal_length" "species"))
  (check-equal? (column-names (select iris (col #px"^[sp]e.*_length$")))
                '("sepal_length" "petal_length"))
  (check-equal? (column-names (select iris (col #rx"zzz"))) '())
  (check-equal? (column-names (select iris (col "^sepal_.*$")))
                '("sepal_length" "sepal_width"))

  (let ([out (select iris (p* (col #rx"^sepal_") 2))])
    (check-equal? (column-names out) '("sepal_length" "sepal_width"))
    (check-equal? (ref (ref out "sepal_length") 0) 10.2))
  (let ([out (select people (p* (col 'float64) 1.1))])
    (check-equal? (column-names out) '("weight" "height"))
    (check-= (ref (ref out "weight") 0) (* 57.9 1.1) 1e-9))
  (check-exn #rx"^lazyframe-collect: .*duplicate.*'x'"
             (lambda () (select people (~> (col 'float64) (p* 2) (alias "x")))))
  (check-pred Expr-ptr? (col #px"(?=a)"))
  (check-exn #rx"^lazyframe-collect: .*\\(\\?=a\\)"
             (lambda () (select iris (col #px"(?=a)"))))
  (check-pred Expr-ptr? (exclude (all) #px"(?=a)"))
  (check-exn #rx"^lazyframe-collect: .*\\(\\?=a\\)"
             (lambda () (select iris (exclude (all) #px"(?=a)"))))
  (check-exn #rx"^lazyframe-collect: .*\\(a\\)\\\\1"
             (lambda () (select iris (col #px"(a)\\1"))))

  (define odd-names
    '("d" "q1" "aa" "a" "a{2}" "w_x" "back\\slash" "br[ack]et" "amp&and" "tilde~x"
      "Sepal" "\u0663" "\u00e9t\u00e9" "two words" "nb\u00A0sp" "line\nbreak" "+-" "p]q"
      ",./" "x-y" "b\\.c" "e\\]f"
      "T_\u212A" "\u017F" "\u03C2" "\u03C3" "\u03A3" "\u00DF" "\u1E9E" "\u0130" "\u0131"
      "i" "I" "ABC" "\u02B0" "tab\there" "v\vt" "del\177" "bell\a"
      "pa" "!" ":" "k" "K" "\u00C9" "AB" "temp_\u00B0C" "\u00A9 owner"
      "pua_\uE000"))
  (define odd (dataframe (for/list ([name (in-list odd-names)]) (series '(0) #:name name))))
  (define (racket-matches rx)
    (for/list ([name (in-list odd-names)] #:when (regexp-match? rx name)) name))
  (define odd-patterns
    (list #rx"\\d" #rx"\\w" #rx"a{2}" #rx"(a)\\1" #rx"\\." #rx"p]"
          #rx"[\\d]" #rx"[]a]" #rx"[&~]" #rx"[[:alpha:]]" #rx"[+-/]"
          #rx"." #rx"^line.break$" #rx"(?i:sepal)" #rx"^q[0-9]$"
          #rx"(?m:^break)" #rx"(?m:line.break)" #rx"(?s:line.break)"
          #rx"(?-s:line.break)" #rx"(?i-m:SEPAL)" #rx"[\\]]"
          #px"\\d" #px"\\D" #px"\\w" #px"\\s" #px"\\S" #px"a{2}" #px"^a{,1}$"
          #px"[[:digit:]]" #px"[\\d&]" #px"[^\\w]" #px"\\p{Ll}" #px"\\p{^Ll}"
          #px"\\bw" #px"e\\B" #px"^.*$" #px"[+-/]" #px"\\P{^Lu}"
          #px"\\p{L&}" #px"c{1,}?" #px"[\\S]" #px"\\\\\\." #px"[\\]]"
          #px"[\\.-z]"
          #rx"(?i:k)" #rx"(?i:s)" #rx"(?i:\u03C3)" #rx"(?i:\u00DF)"
          #rx"(?i:\u0130)" #rx"(?i:\u0131)" #rx"(?i:i)" #rx"(?i:[^k])"
          #rx"(?i:[a-z])" #rx"(?i:a(?-i:B))" #rx"(?i:ab)c" #px"(?i:\\w)"
          #px"(?i:\\W)" #px"(?i:[[:upper:]])" #px"(?i:\\p{Lu})"
          #px"(?i:[[:lower:]])" #px"[[:space:]]" #px"[[:print:]]"
          #px"[^[:print:]]" #px"[[:cntrl:]]" #px"[[:graph:]]" #px"[[:blank:]]"
          #px"[[:punct:][a]" #px"\\p{Cs}" #px"\\P{Cs}" #px"\\p{.}"
          #px"^a{}$" (regexp "x|\0?") (regexp "a\\")
          #rx"(?i:\\k)" #px"(?i:\\\u00E9)" #rx"(?i:\\a\\b)"
          #px"\\p{C}" #px"\\P{C}" #px"\\p{^C}"))
  (for ([rx (in-list odd-patterns)])
    (define matched (racket-matches rx))
    (check-equal? (column-names (select odd (col rx))) matched (format "col ~s" rx))
    (check-equal? (column-names (select odd (exclude (all) rx)))
                  (for/list ([name (in-list odd-names)] #:unless (member name matched)) name)
                  (format "exclude ~s" rx)))

  (check-exn #rx"^exclude: contract violation\n  expected: multi-column-expr\\?\n  given: 5"
             (lambda () (contracted:exclude 5 "a")))
  (check-exn #rx"^exclude: contract violation\n  expected: multi-column-expr\\?"
             (lambda () (contracted:exclude (col "value") "cost")))
  (check-exn #rx"^exclude: contract violation\n  expected: multi-column-expr\\?"
             (lambda () (contracted:exclude (sum "value") "cost")))
  (check-exn #rx"^exclude: contract violation\n  expected: \\(or/c string\\? regexp\\?\\)\n  given: 'a"
             (lambda () (contracted:exclude (all) 'a)))
  (check-exn exn:fail:contract:arity? (lambda () (contracted:exclude (all))))
  (check-exn exn:fail:contract:arity? (lambda () (contracted:all 1)))
  (check-exn #rx"^col: contract violation" (lambda () (col 'nope))))
