#lang racket/base

;; Polars compiles a column pattern with Rust's regex crate. A Racket regexp is
;; rewritten into that syntax with the same meaning on a column name.

(provide ->column-pattern)

(define (->column-pattern v)
  (if (regexp? v)
      (string-append "^(?s).*(?:" (regexp->rust v) ").*$")
      v))

(define px-classes (hash #\d "0-9" #\w "a-zA-Z0-9_" #\s " \\t\\n\\f\\r"))
(define outside-specials (string->list "\\.+*?()|[]{}^$#&-~"))
(define class-specials (string->list "\\[]^-&~"))

(define (escape c specials)
  (if (memv c specials) (string #\\ c) (string c)))

(define (regexp->rust rx)
  (define px? (pregexp? rx))
  (define src (object-name rx))
  (define n (string-length src))
  (define (at i) (and (< i n) (string-ref src i)))
  (define (index-of c from)
    (for/first ([i (in-range from n)] #:when (char=? (string-ref src i) c)) i))
  (define out (open-output-string))
  (define (emit . ss) (for-each (lambda (s) (write-string s out)) ss))

  (define (property i)
    (define close (index-of #\} i))
    (define body (substring src (+ i 2) close))
    (define negated? (and (positive? (string-length body)) (char=? (string-ref body 0) #\^)))
    (define name
      (let ([s (if negated? (substring body 1) body)])
        (cond [(string=? s "L&") "LC"] [(string=? s ".") "Any"] [else s])))
    (values (string-append (if (eq? negated? (char=? (string-ref src i) #\P)) "\\p{" "\\P{")
                           name "}")
            (add1 close)))

  (define (range-item i)
    (define c (string-ref src i))
    (cond
      [(and px? (char=? c #\[) (eqv? (at (add1 i)) #\:))
       (define close (+ 2 (index-of #\: (+ i 2))))
       (values (substring src i close) close #f)]
      [(and px? (char=? c #\\))
       (define e (string-ref src (add1 i)))
       (cond
         [(hash-ref px-classes (char-downcase e) #f)
          => (lambda (cls)
               (values (if (char-upper-case? e) (string-append "[^" cls "]") cls) (+ i 2) #f))]
         [(memv e '(#\p #\P))
          (define-values (text next) (property (add1 i)))
          (values text next #f)]
         [else (values (escape e class-specials) (+ i 2) #t)])]
      [else (values (escape c class-specials) (add1 i) #t)]))

  (define (range i)
    (define negated? (eqv? (at i) #\^))
    (emit (if negated? "[^" "["))
    (let loop ([i (if negated? (add1 i) i)] [first? #t])
      (cond
        [(and (not first?) (char=? (string-ref src i) #\])) (emit "]") (add1 i)]
        [else
         (define-values (lo next single?) (range-item i))
         (cond
           [(and single? (eqv? (at next) #\-) (not (eqv? (at (add1 next)) #\])))
            (define-values (hi after _) (range-item (add1 next)))
            (emit lo "-" hi)
            (loop after #f)]
           [else (emit lo) (loop next #f)])])))

  (define (mode-group i)
    (define colon
      (let find ([k (+ i 2)])
        (cond [(eqv? (at k) #\:) k]
              [(memv (at k) '(#\i #\m #\s #\-)) (find (add1 k))]
              [else #f])))
    (and (eqv? (at (add1 i)) #\?) colon (> colon (+ i 2))
         (let loop ([k (+ i 2)] [fold 'unset] [multi 'unset] [off? #f])
           (define c (string-ref src k))
           (cond
             [(char=? c #\:)
              (define on (string-append (if (eq? fold 'on) "i" "")
                                        (case multi [(on) "m"] [(off) "s"] [else ""])))
              (define off (string-append (if (eq? fold 'off) "i" "")
                                         (case multi [(on) "s"] [(off) "m"] [else ""])))
              (emit "(?" on (if (string=? off "") "" (string-append "-" off)) ":")
              (add1 k)]
             [(char=? c #\-) (loop (add1 k) fold multi #t)]
             [(char=? c #\i) (loop (add1 k) (if off? 'off 'on) multi #f)]
             [(char=? c #\m) (loop (add1 k) fold (if off? 'off 'on) #f)]
             [else (loop (add1 k) fold (if off? 'on 'off) #f)]))))

  (let loop ([i 0])
    (when (< i n)
      (define c (string-ref src i))
      (loop
       (cond
         [(char=? c #\\)
          (define e (string-ref src (add1 i)))
          (cond
            [(not px?)
             (emit (if (or (char-alphabetic? e) (char-numeric? e))
                       (string e)
                       (escape e outside-specials)))
             (+ i 2)]
            [(hash-ref px-classes (char-downcase e) #f)
             => (lambda (cls) (emit (if (char-upper-case? e) "[^" "[") cls "]") (+ i 2))]
            [(memv e '(#\b #\B)) (emit "(?-u:\\" (string e) ")") (+ i 2)]
            [(memv e '(#\p #\P))
             (define-values (text next) (property (add1 i)))
             (emit text)
             next]
            [(char-numeric? e) (emit "\\" (string e)) (+ i 2)]
            [else (emit (escape e outside-specials)) (+ i 2)])]
         [(char=? c #\[) (range (add1 i))]
         [(and (char=? c #\() (mode-group i))]
         [(and px? (char=? c #\{))
          (define close (index-of #\} i))
          (define body (substring src (add1 i) close))
          (emit "{" (if (regexp-match? #rx"^," body) "0" "") body "}")
          (add1 close)]
         [(memv c '(#\{ #\} #\])) (emit "\\" (string c)) (add1 i)]
         [else (emit (string c)) (add1 i)]))))
  (get-output-string out))

(module+ test
  (require rackunit)
  (define (rust rx) (regexp->rust rx))
  (check-equal? (->column-pattern "^a$") "^a$")
  (check-equal? (->column-pattern #rx"^sepal_") "^(?s).*(?:^sepal_).*$")
  (check-equal? (rust #rx"\\d") "d")
  (check-equal? (rust #rx"\\.") "\\.")
  (check-equal? (rust #rx"(a)\\1") "(a)1")
  (check-equal? (rust #rx"a{2}") "a\\{2\\}")
  (check-equal? (rust #rx"k]") "k\\]")
  (check-equal? (rust #rx"[\\d]") "[\\\\d]")
  (check-equal? (rust #rx"[]a]") "[\\]a]")
  (check-equal? (rust #rx"[^]a]") "[^\\]a]")
  (check-equal? (rust #rx"[&~]") "[\\&\\~]")
  (check-equal? (rust #rx"[[:alpha:]]") "[\\[:alpha:]\\]")
  (check-equal? (rust #rx"[+-/]") "[+-/]")
  (check-equal? (rust #rx"[a-z-]") "[a-z\\-]")
  (check-equal? (rust #px"\\d+") "[0-9]+")
  (check-equal? (rust #px"\\D\\W\\S") "[^0-9][^a-zA-Z0-9_][^ \\t\\n\\f\\r]")
  (check-equal? (rust #px"[\\d&]") "[0-9\\&]")
  (check-equal? (rust #px"[^\\w]") "[^a-zA-Z0-9_]")
  (check-equal? (rust #px"[\\S]") "[[^ \\t\\n\\f\\r]]")
  (check-equal? (rust #px"[[:digit:]x]") "[[:digit:]x]")
  (check-equal? (rust #px"\\bw\\B") "(?-u:\\b)w(?-u:\\B)")
  (check-equal? (rust #px"\\p{Ll}\\p{^Ll}\\P{^Lu}\\p{L&}") "\\p{Ll}\\P{Ll}\\p{Lu}\\p{LC}")
  (check-equal? (rust #px"a{2}b{,3}c{1,}?") "a{2}b{0,3}c{1,}?")
  (check-equal? (rust #px"(a)\\1") "(a)\\1")
  (check-equal? (rust #px"\\\\\\.") "\\\\\\.")
  (check-equal? (rust #rx"(?i:a)(?m:b)(?s:c)(?-s:d)(?i-m:e)(?:f)(?=g)")
                "(?i:a)(?m-s:b)(?s-m:c)(?m-s:d)(?is-m:e)(?:f)(?=g)"))
