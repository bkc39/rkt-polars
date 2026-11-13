#lang racket/base

(module+ test
  (require rackunit
           racket/list
           racket/match
           (only-in (submod polars/private/column-pattern internal)
                    any-char
                    category-class
                    category-representatives
                    never-matches
                    regexp->rust))

  (define (claims? text ch)
    (match-define (list _ caret body)
      (regexp-match #px"^\\[(\\^?)((?:\\\\p\\{[A-Z][a-z]\\})+)\\]$" text))
    (define named?
      (member (string-titlecase (symbol->string (char-general-category ch)))
              (regexp-match* #px"\\{([A-Z][a-z])\\}" body #:match-select cadr)))
    (if (string=? caret "^") (not named?) (and named? #t)))

  (check-equal? (length category-representatives) 29)
  (check-false (check-duplicates (map car category-representatives)))
  (check-false (assq 'cs category-representatives))
  (for ([entry (in-list category-representatives)])
    (match-define (cons category ch) entry)
    (check-equal? (char-general-category ch) category))

  (for* ([rx (list #px"\\p{C}" #px"\\P{C}" #px"\\p{^C}" #px"\\P{^C}")]
         [entry (in-list category-representatives)])
    (match-define (cons category ch) entry)
    (check-equal? (claims? (regexp->rust rx) ch)
                  (regexp-match? rx (string ch))
                  (format "~a on ~a" (object-name rx) category)))

  (check-equal? (category-class #f '()) never-matches)
  (check-equal? (category-class #t '()) any-char)
  (check-equal? (category-class #f '(cc co)) "[\\p{Cc}\\p{Co}]")
  (check-equal? (category-class #t '(cc co)) "[^\\p{Cc}\\p{Co}]"))
