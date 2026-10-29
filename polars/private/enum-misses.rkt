#lang racket/base

(require (only-in json read-json)
         racket/match
         (only-in racket/string string-join))

(provide enum-misses-message enum-misses-reason enum-misses-shown)

(define enum-misses-shown 10)

(define tagged-payload #rx"^\u0001enum-misses\u0001(.*)$")

(define (spell value)
  (cond
    [(for/or ([c (in-string value)]) (char-iso-control? c)) (format "~s" value)]
    [else (format "~s" (string->symbol value))]))

(define (enum-misses-message dtype missing total named distinct)
  (define noun (if (= total 1) "value" "values"))
  (define verb (if (= missing 1) "is" "are"))
  (define listed (string-join (map spell named)))
  (define more (- distinct (length named)))
  (define tail (if (positive? more) (format "~a, and ~a more" listed more) listed))
  (format "~a of ~a ~a ~a not in ~v: ~a" missing total noun verb dtype tail))

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
