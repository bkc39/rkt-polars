#lang racket/base

(module+ test
  (require rackunit
           racket/match
           (only-in (submod polars/private/column-pattern internal) regexp->rust))

  (define representatives
    (hash 'cc #\nul 'cf #\u00AD 'cn #\uFFFF 'co #\uE000
          'll #\a 'lu #\A 'lt #\u01C5 'lm #\u02B0 'lo #\u05D0
          'mn #\u0300 'mc #\u0903 'me #\u0488
          'nd #\0 'nl #\u2160 'no #\u00B2
          'pc #\_ 'pd #\- 'ps #\( 'pe #\) 'pi #\u00AB 'pf #\u00BB 'po #\!
          'sm #\+ 'sc #\$ 'sk #\^ 'so #\u00A9
          'zs #\space 'zl #\u2028 'zp #\u2029))

  (define (claims? text ch)
    (match-define (list _ caret body)
      (regexp-match #px"^\\[(\\^?)((?:\\\\p\\{[A-Z][a-z]\\})+)\\]$" text))
    (define named?
      (member (string-titlecase (symbol->string (char-general-category ch)))
              (regexp-match* #px"\\{([A-Z][a-z])\\}" body #:match-select cadr)))
    (if (string=? caret "^") (not named?) (and named? #t)))

  (for ([(category ch) (in-hash representatives)])
    (check-equal? (char-general-category ch) category))

  (for* ([rx (list #px"\\p{C}" #px"\\P{C}" #px"\\p{^C}")]
         [(category ch) (in-hash representatives)])
    (check-equal? (claims? (regexp->rust rx) ch)
                  (regexp-match? rx (string ch))
                  (format "~a on ~a" (object-name rx) category))))
