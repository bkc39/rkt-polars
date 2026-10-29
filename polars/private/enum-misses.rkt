#lang racket/base

(require (only-in json read-json)
         racket/match
         (only-in racket/list remove-duplicates)
         (only-in racket/string string-join))

(provide enum-cast-reason enum-misses-message enum-misses-reason enum-misses-shown)

(define enum-misses-shown 10)

(define enum-misses-strict-shown 3)

(define tagged-payload #rx"^\u0001enum-misses\u0001(.*)$")

(define strict-cast-failure
  (pregexp
   (string-append "^conversion from `(?:str|cat|enum)` to `enum` failed in column '[^']*' "
                  "for ([0-9]+) out of ([0-9]+) values: "
                  "\\[((?:\"[^\"\u0000]*\"(?:, (?:…|[.]{3}) |, )?)+)\\]"
                  "(?:\n\nEnsure that all values in the input column are present in the categories"
                  " of the enum datatype[.]|\n\nDid not show all failed cases as there were too"
                  " many[.])?$")))

(define strict-cast-values (pregexp "^\"([^\"]*)\"(, (?:…|[.]{3}) |, |$)"))

(define (spell value)
  (cond
    [(for/or ([c (in-string value)]) (char-iso-control? c)) (format "~s" value)]
    [else (format "~s" (string->symbol value))]))

(define (misses-message noun-count missing target listed more [counted ""])
  (define noun (if (= noun-count 1) "value" "values"))
  (define verb (if (= missing 1) "is" "are"))
  (define spelled (string-join (map spell listed)))
  (define tail (if (positive? more) (format "~a, and ~a more~a" spelled more counted) spelled))
  (format "~a of ~a ~a ~a not in ~a: ~a" missing noun-count noun verb target tail))

(define (enum-misses-message dtype missing total named distinct)
  (misses-message total missing (format "~v" dtype) named (- distinct (length named))))

(define (read-payload text)
  (with-handlers ([exn:fail:read? (lambda (_) #f)])
    (define in (open-input-string text))
    (define payload (read-json in))
    (and (eof-object? (read-json in)) payload)))

(define (enum-misses-reason reason)
  (match (regexp-match tagged-payload reason)
    [(list _ (app read-payload
                  (hash-table ['categories (list (? string? categories) ...)]
                              ['missing (? exact-nonnegative-integer? missing)]
                              ['total (? exact-nonnegative-integer? total)]
                              ['distinct (? exact-nonnegative-integer? distinct)]
                              ['shown (list (? string? shown) ...)])))
     (enum-misses-message (cons 'enum (map string->symbol categories)) missing total shown
                          distinct)]
    [_ #f]))

(define (shown-values listing)
  (let loop ([rest listing] [shown '()] [cut? #f])
    (match (regexp-match strict-cast-values rest)
      [(list whole value separator)
       (define more (substring rest (string-length whole)))
       (define taken (cons value shown))
       (cond
         [(equal? separator "") (and (equal? more "") (cons (reverse taken) cut?))]
         [cut? #f]
         [else (loop more taken (not (equal? separator ", ")))])]
      [_ #f])))

(define (polars-shown shown missing)
  (match shown
    [(cons taken cut?)
     #:when (and (= (length taken) (min missing enum-misses-strict-shown))
                 (eq? cut? (> missing enum-misses-strict-shown)))
     (if cut? (reverse (cdr (reverse taken))) taken)]
    [_ #f]))

(define (enum-cast-reason reason)
  (match (regexp-match strict-cast-failure reason)
    [(list _ (app string->number missing) (app string->number total) (app shown-values shown))
     #:when (<= 1 missing total)
     (match (polars-shown shown missing)
       [(? list? listed)
        (misses-message total missing "the enum" (remove-duplicates listed)
                        (- missing (length listed)) " rows")]
       [_ #f])]
    [_ #f]))
