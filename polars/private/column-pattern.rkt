#lang racket/base

(require racket/bool
         racket/list
         racket/match
         racket/string)

(provide ->column-pattern)

(define (->column-pattern v)
  (if (regexp? v)
      (string-append "^(?s).*(?:" (regexp->rust v) ").*$")
      v))

(define posix-classes
  (hash "alpha" "a-zA-Z" "upper" "A-Z" "lower" "a-z" "digit" "0-9" "xdigit" "0-9a-fA-F"
        "alnum" "a-zA-Z0-9" "word" "a-zA-Z0-9_" "blank" " \\t" "space" " \\t\\n\\f\\r"
        "graph" "!-~" "print" "\\t -~" "cntrl" "\\x00-\\x1F" "ascii" "\\x00-\\x7F"))
(define posix-class (string-append "\\[:(?:" (string-join (hash-keys posix-classes) "|") "):\\]"))

(define rx-token #px"\\\\.|\\[\\^?\\]?[^]]*\\]|\\(\\?[-ims]+:|.")
(define px-token
  (pregexp (string-append "\\\\[pP]\\{[^}]*\\}|\\\\."
                          "|\\[\\^?\\]?(?:" posix-class "|\\\\.|[^]])*\\]"
                          "|\\(\\?[-ims]+:|\\{[0-9]*,?[0-9]*\\}|.")))
(define px-class-item (pregexp (string-append posix-class "|\\\\.|.")))

(define ascii-classes (hash "d" "0-9" "w" "a-zA-Z0-9_" "s" " \\t\\n\\f\\r"))
(define outside-specials "\\.+*?()|[]{}^$#&-~")
(define class-specials "\\[]^-&~")

(define (escape c specials)
  (cond [(string=? c (string #\nul)) "\\x00"]
        [(string-contains? specials c) (string-append "\\" c)]
        [else c]))

(define (case-variants c)
  (define ch (string-ref c 0))
  (remove-duplicates
   (map string (list ch (char-upcase ch) (char-downcase ch) (char-foldcase ch)))))

(define (regexp->rust rx)
  (define px? (pregexp? rx))
  (let loop ([tokens (regexp-match* (if px? px-token rx-token) (object-name rx))]
             [folds '(#f)]
             [out '()])
    (match tokens
      ['() (string-append* (reverse out))]
      [(cons (regexp #rx"^\\(\\?([-ims]+):$" (list _ flags)) rest)
       (define-values (text fold?) (mode-group flags (car folds)))
       (loop rest (cons fold? folds) (cons text out))]
      [(cons "(" rest) (loop rest (cons (car folds) folds) (cons "(" out))]
      [(cons ")" rest) (loop rest (cdr folds) (cons ")" out))]
      [(cons token rest) (loop rest folds (cons (translate-token token px? (car folds)) out))])))

(define (translate-token token px? fold?)
  (match token
    [(regexp #px"^\\\\([pP])\\{(\\^?)([^}]*)\\}$" (list _ p caret name)) (property p caret name)]
    [(regexp #rx"^\\\\(.)$" (list _ c)) (translate-escape c px? fold?)]
    ["\\" "\\x00"]
    [(regexp #rx"^\\[") (char-class token px? fold?)]
    ["{}" "{0}"]
    [(regexp #rx"^{,(.*)$" (list _ rest)) (string-append "{0," rest)]
    [(regexp #rx"^{.") token]
    [(or "." "^" "$" "|" "*" "+" "?") token]
    [_ (literal token fold?)]))

(define (literal c fold?)
  (match (if fold? (case-variants c) (list c))
    [(list only) (escape only outside-specials)]
    [variants (string-append "[" (class-chars variants) "]")]))

(define (class-chars chars)
  (string-append* (for/list ([c (in-list chars)]) (escape c class-specials))))

(define (translate-escape c px? fold?)
  (match c
    [_ #:when (not px?) (literal c fold?)]
    [(or "d" "w" "s") (string-append "[" (hash-ref ascii-classes c) "]")]
    [(or "D" "W" "S") (string-append "[^" (hash-ref ascii-classes (string-downcase c)) "]")]
    [(or "b" "B") (string-append "(?-u:\\" c ")")]
    [(regexp #rx"^[0-9]$") (string-append "\\" c)]
    [_ (literal c fold?)]))

(define (property p caret name)
  (define negated? (xor (string=? p "P") (string=? caret "^")))
  (match name
    ["L&" (string-append (if negated? "[^" "[") "\\p{Ll}\\p{Lu}\\p{Lt}\\p{Lm}]")]
    [(or "Cs" ".") (if negated? "(?s:.)" "[a&&b]")]
    [_ (string-append (if negated? "\\P{" "\\p{") name "}")]))

(define (char-class token px? fold?)
  (match-define (list _ negated body) (regexp-match #rx"^\\[(\\^?)(.*)\\]$" token))
  (define items (regexp-match* (if px? px-class-item #rx".") body))
  (string-append "[" negated (string-append* (class-items items px? fold?)) "]"))

(define (class-items items px? fold?)
  (define (single item)
    (match item
      [(regexp #rx"^.$") item]
      [(regexp #px"^\\\\([^[:alnum:]])$" (list _ c)) #:when px? c]
      [_ #f]))
  (match items
    ['() '()]
    [(list* (app single (? string? lo)) "-" (app single (? string? hi)) rest)
     (cons (class-range lo hi fold?) (class-items rest px? fold?))]
    [(cons item rest) (cons (class-item item px? fold?) (class-items rest px? fold?))]))

(define (class-item item px? fold?)
  (match item
    [(regexp #rx"^\\[:([a-z]+):\\]$" (list _ name)) (hash-ref posix-classes name)]
    [(regexp #rx"^\\\\(.)$" (list _ c))
     #:when px?
     (match c
       [(or "d" "w" "s") (hash-ref ascii-classes c)]
       [(or "D" "W" "S") (string-append "[^" (hash-ref ascii-classes (string-downcase c)) "]")]
       [_ (class-chars (if fold? (case-variants c) (list c)))])]
    [_ (class-chars (if fold? (case-variants item) (list item)))]))

(define (class-range lo hi fold?)
  (define lo-i (char->integer (string-ref lo 0)))
  (define hi-i (char->integer (string-ref hi 0)))
  (define folded
    (if fold?
        (sort (remove-duplicates
               (for*/list ([i (in-range lo-i (add1 hi-i))]
                           #:unless (<= #xD800 i #xDFFF)
                           [v (in-list (case-variants (string (integer->char i))))]
                           [j (in-value (char->integer (string-ref v 0)))]
                           #:unless (<= lo-i j hi-i))
                 j))
              <)
        '()))
  (string-append (escape lo class-specials) "-" (escape hi class-specials)
                 (string-append* (map run->class (runs folded)))))

(define (runs codes)
  (match codes
    ['() '()]
    [(cons code rest)
     (match (runs rest)
       [(cons (cons (== (add1 code)) hi) more) (cons (cons code hi) more)]
       [later (cons (cons code code) later)])]))

(define (run->class run)
  (match-define (cons lo hi) run)
  (define (ch i) (escape (string (integer->char i)) class-specials))
  (if (= lo hi) (ch lo) (string-append (ch lo) "-" (ch hi))))

(define (mode-group flags fold?)
  (define-values (fold multi)
    (for/fold ([fold fold?] [multi #f]) ([flag (in-list (regexp-match* #rx"-?[ims]" flags))])
      (match flag
        ["i" (values #t multi)]
        ["-i" (values #f multi)]
        [(or "m" "-s") (values fold 'on)]
        [(or "s" "-m") (values fold 'off)])))
  (values (case multi [(on) "(?m-s:"] [(off) "(?s-m:"] [else "(?:"]) fold))
