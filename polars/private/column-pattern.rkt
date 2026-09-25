#lang racket/base

(require racket/bool
         racket/match
         racket/string)

(provide ->column-pattern)

(define (->column-pattern v)
  (if (regexp? v)
      (string-append "^(?s).*(?:" (regexp->rust v) ").*$")
      v))

(define rx-token #px"\\\\.|\\[\\^?\\]?[^]]*\\]|\\(\\?[-ims]+:|.")
(define px-token
  (pregexp (string-append "\\\\[pP]\\{[^}]*\\}|\\\\."
                          "|\\[\\^?\\]?(?:\\[:[a-z]+:\\]|\\\\.|[^]])*\\]"
                          "|\\(\\?[-ims]+:|\\{[0-9]*,?[0-9]*\\}|.")))
(define px-class-item #px"\\[:[a-z]+:\\]|\\\\.|.")

(define ascii-classes (hash "d" "0-9" "w" "a-zA-Z0-9_" "s" " \\t\\n\\f\\r"))
(define outside-specials "\\.+*?()|[]{}^$#&-~")
(define class-specials "\\[]^-&~")

(define (escape c specials)
  (if (string-contains? specials c) (string-append "\\" c) c))

(define (regexp->rust rx)
  (define px? (pregexp? rx))
  (string-append*
   (for/list ([token (in-list (regexp-match* (if px? px-token rx-token) (object-name rx)))])
     (match token
       [(regexp #px"^\\\\([pP])\\{(\\^?)([^}]*)\\}$" (list _ p caret name)) (property p caret name)]
       [(regexp #rx"^\\\\(.)$" (list _ c)) (translate-escape c px? #f)]
       [(regexp #rx"^\\[") (char-class token px?)]
       [(regexp #rx"^\\(\\?([-ims]+):$" (list _ flags)) (mode-group flags)]
       [(regexp #rx"^{,(.*)$" (list _ rest)) (string-append "{0," rest)]
       [(or "{" "}" "]") (string-append "\\" token)]
       [_ token]))))

(define (translate-escape c px? in-class?)
  (match c
    [_ #:when (not px?) (if (regexp-match? #px"^(?:\\p{L}|\\p{N})$" c) c (escape c outside-specials))]
    [(or "d" "w" "s")
     (define cls (hash-ref ascii-classes c))
     (if in-class? cls (string-append "[" cls "]"))]
    [(or "D" "W" "S") (string-append "[^" (hash-ref ascii-classes (string-downcase c)) "]")]
    [(or "b" "B") (string-append "(?-u:\\" c ")")]
    [(regexp #rx"^[0-9]$") (string-append "\\" c)]
    [_ (escape c (if in-class? class-specials outside-specials))]))

(define (property p caret name)
  (string-append (if (xor (string=? p "P") (string=? caret "^")) "\\P{" "\\p{")
                 (case name [("L&") "LC"] [(".") "Any"] [else name])
                 "}"))

(define (char-class token px?)
  (match-define (list _ negated body) (regexp-match #rx"^\\[(\\^?)(.*)\\]$" token))
  (define items (if px? (regexp-match* px-class-item body) (regexp-match* #rx"." body)))
  (string-append "[" negated (string-append* (class-items items px?)) "]"))

(define (class-items items px?)
  (define (single? item)
    (or (= (string-length item) 1)
        (and px? (regexp-match? #px"^\\\\[^[:alnum:]]$" item))))
  (match items
    ['() '()]
    [(list* lo "-" hi rest)
     #:when (and (single? lo) (single? hi))
     (list* (class-item lo px?) "-" (class-item hi px?) (class-items rest px?))]
    [(cons item rest) (cons (class-item item px?) (class-items rest px?))]))

(define (class-item item px?)
  (match item
    [(regexp #rx"^\\[:") item]
    [(regexp #rx"^\\\\(.)$" (list _ c)) #:when px? (translate-escape c #t #t)]
    [_ (escape item class-specials)]))

(define (mode-group flags)
  (define-values (fold multi)
    (for/fold ([fold #f] [multi #f]) ([flag (in-list (regexp-match* #rx"-?[ims]" flags))])
      (match flag
        ["i" (values 'on multi)]
        ["-i" (values 'off multi)]
        [(or "m" "-s") (values fold 'on)]
        [(or "s" "-m") (values fold 'off)])))
  (define on (string-append (if (eq? fold 'on) "i" "") (case multi [(on) "m"] [(off) "s"] [else ""])))
  (define off (string-append (if (eq? fold 'off) "i" "") (case multi [(on) "s"] [(off) "m"] [else ""])))
  (string-append "(?" on (if (string=? off "") "" (string-append "-" off)) ":"))
