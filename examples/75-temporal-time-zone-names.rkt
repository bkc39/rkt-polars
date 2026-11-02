#lang racket/base

;; time-zone-name/c: the shape every verb that takes a zone's name checks.
;;
;; A zone's name is a non-empty string without a NUL. The contract checks the
;; shape alone: a well-formed name polars does not know passes it, and the verb
;; then reports polars' reason. A name that fails it is refused under the verb
;; the caller named, before any call into polars.
;;
;; Inside `nix develop`:
;;   racket examples/75-temporal-time-zone-names.rkt

(require gregor
         polars)

(define candidates
  (list "Europe/Brussels" "UTC" "" (string-append "UTC" (string #\nul) "x") "Asia/Kathmando"))
(for ([name (in-list candidates)])
  (printf "~s: ~a\n" name (time-zone-name/c name)))

(define clocks (series (list (datetime 2021 3 27 9) (datetime 2021 3 28 9)) #:name "clock"))
(define utc (dt-replace-time-zone clocks "UTC"))

(printf "~s\n" (series->list (dt-convert-time-zone utc "Europe/Brussels")))
(printf "~a\n" (with-handlers ([exn:fail? exn-message])
                 (dt-convert-time-zone utc "Asia/Kathmando")))
(printf "~a\n" (with-handlers ([exn:fail:contract? exn-message])
                 (dt-convert-time-zone utc "")))
(printf "~a\n" (with-handlers ([exn:fail:contract? exn-message])
                 (cast clocks (list 'datetime 'microseconds (string-append "UTC" (string #\nul) "x")))))
