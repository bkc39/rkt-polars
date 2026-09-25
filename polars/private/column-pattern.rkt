#lang racket/base

(require racket/bool
         racket/list
         racket/match
         racket/promise
         racket/string
         threading)

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
(define never-matches "[a&&b]")
(define any-char "(?s:.)")

(define (escape ch specials)
  (define s (string ch))
  (cond [(char=? ch #\nul) "\\x00"]
        [(string-contains? specials s) (string-append "\\" s)]
        [else s]))

(define (class-of negated? body)
  (string-append (if negated? "[^" "[") body "]"))

(define (class-chars chars)
  (string-append* (for/list ([ch (in-list chars)]) (escape ch class-specials))))

(define cased-chars
  (delay
    (for*/vector ([i (in-range #x110000)]
                  #:unless (<= #xD800 i #xDFFF)
                  [ch (in-value (integer->char i))]
                  #:unless (char=? ch (char-upcase ch) (char-downcase ch) (char-foldcase ch)))
      ch)))

(define (case-variants ch fold?)
  (if fold?
      (remove-duplicates (list ch (char-upcase ch) (char-downcase ch) (char-foldcase ch)))
      (list ch)))

(define (regexp->rust rx)
  (define px? (pregexp? rx))
  (for/fold ([folds '(#f)] [out '()] #:result (string-append* (reverse out)))
            ([token (in-list (regexp-match* (if px? px-token rx-token) (object-name rx)))])
    (match-define (cons fold? outer) folds)
    (match token
      [(regexp #rx"^\\(\\?([-ims]+):$" (list _ flags))
       (define-values (text inner-fold?) (mode-group flags fold?))
       (values (cons inner-fold? folds) (cons text out))]
      ["(" (values (cons fold? folds) (cons token out))]
      [")" (values outer (cons token out))]
      [_ (values folds (cons (translate-token token px? fold?) out))])))

(define (translate-token token px? fold?)
  (match token
    [(regexp #px"^\\\\([pP])\\{(\\^?)([^}]*)\\}$" (list _ p caret name)) (property p caret name)]
    [(regexp #rx"^\\\\(.)$" (list _ c)) (translate-escape c px?)]
    ["\\" "\\x00"]
    [(regexp #rx"^\\[") (char-class token px? fold?)]
    ["{}" "{0}"]
    [(regexp #rx"^{,(.*)$" (list _ rest)) (string-append "{0," rest)]
    [(regexp #rx"^{.") token]
    [(or "." "^" "$" "|" "*" "+" "?") token]
    [_ (literal (string-ref token 0) fold?)]))

(define (literal ch fold?)
  (match (case-variants ch fold?)
    [(list only) (escape only outside-specials)]
    [variants (class-of #f (class-chars variants))]))

(define (ascii-class c in-class?)
  (match c
    [(or "d" "w" "s")
     (define cls (hash-ref ascii-classes c))
     (if in-class? cls (class-of #f cls))]
    [(or "D" "W" "S") (class-of #t (hash-ref ascii-classes (string-downcase c)))]
    [_ #f]))

(define (translate-escape c px?)
  (cond
    [(not px?) (literal (string-ref c 0) #f)]
    [(ascii-class c #f)]
    [(member c '("b" "B")) (string-append "(?-u:\\" c ")")]
    [(regexp-match? #rx"^[0-9]$" c) (string-append "\\" c)]
    [else (literal (string-ref c 0) #f)]))

(define (property p caret name)
  (define negated? (xor (string=? p "P") (string=? caret "^")))
  (match name
    ["L&" (class-of negated? "\\p{Ll}\\p{Lu}\\p{Lt}\\p{Lm}")]
    ["C" (class-of negated? "\\p{Cc}\\p{Cf}\\p{Cn}\\p{So}")]
    [(or "Cs" ".") (if negated? any-char never-matches)]
    [_ (string-append (if negated? "\\P{" "\\p{") name "}")]))

(define (char-class token px? fold?)
  (match-define (list _ negated body) (regexp-match #rx"^\\[(\\^?)(.*)\\]$" token))
  (define items (regexp-match* (if px? px-class-item #rx".") body))
  (class-of (string=? negated "^") (string-append* (class-items items px? fold?))))

(define (class-items items px? fold?)
  (define (single item)
    (match item
      [(regexp #rx"^.$") (string-ref item 0)]
      [(regexp #px"^\\\\([^[:alnum:]])$" (list _ c)) #:when px? (string-ref c 0)]
      [_ #f]))
  (match items
    ['() '()]
    [(list* (app single (? char? lo)) "-" (app single (? char? hi)) rest)
     (cons (class-range lo hi fold?) (class-items rest px? fold?))]
    [(cons item rest) (cons (class-item item px? fold?) (class-items rest px? fold?))]))

(define (class-item item px? fold?)
  (match item
    [(regexp #rx"^\\[:([a-z]+):\\]$" (list _ name)) (hash-ref posix-classes name)]
    [(regexp #rx"^\\\\(.)$" (list _ c))
     #:when px?
     (or (ascii-class c #t) (class-chars (case-variants (string-ref c 0) fold?)))]
    [_ (class-chars (case-variants (string-ref item 0) fold?))]))

(define (class-range lo hi fold?)
  (define folded
    (if fold?
        (~> (for*/list ([ch (in-vector (force cased-chars))]
                        #:when (char<=? lo ch hi)
                        [v (in-list (case-variants ch #t))]
                        #:unless (char<=? lo v hi))
              (char->integer v))
            remove-duplicates
            (sort <))
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
  (define (ch i) (~> i integer->char (escape class-specials)))
  (if (= lo hi) (ch lo) (string-append (ch lo) "-" (ch hi))))

(define (mode-group flags outer-fold?)
  (define-values (fold? multi)
    (for/fold ([fold? outer-fold?] [multi #f])
              ([flag (in-list (regexp-match* #rx"-?[ims]" flags))])
      (match flag
        ["i" (values #t multi)]
        ["-i" (values #f multi)]
        [(or "m" "-s") (values fold? 'on)]
        [(or "s" "-m") (values fold? 'off)])))
  (values (case multi [(on) "(?m-s:"] [(off) "(?s-m:"] [else "(?:"]) fold?))
