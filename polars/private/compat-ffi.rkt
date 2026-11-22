#lang racket/base

(require ffi/unsafe
         ffi/unsafe/atomic
         ffi/unsafe/define
         ffi/unsafe/define/conventions
         racket/match
         syntax/parse/define
         (only-in polars/private/native-library compat-library missing-export)
         (only-in polars/private/resource with-release)
         (only-in (submod polars/private/resource internal) str-block->string str-block->strings)
         (for-syntax racket/base))

(provide (except-out (all-defined-out)
                     block-reader c-string-argument c-string/null-argument define-compat/ffi
                     named-binding result-only))

(define-ffi-definer define-compat/ffi
  compat-library
  #:make-c-id convention:hyphen->underscore
  #:default-make-fail missing-export)

(define ((named-binding name wrap) callout)
  (define value (wrap callout))
  (if (procedure? value) (procedure-rename value name) value))

(define-syntax-parse-rule (define-compat name:id type:expr
                            (~alt (~optional (~seq #:c-id (~var c-id id #:role "the C symbol"))
                                             #:name "the #:c-id option")
                                  (~optional (~seq #:wrap wrap:expr)
                                             #:name "the #:wrap option"
                                             #:defaults ([wrap #'values])))
                            ...)
  (define-compat/ffi name type (~? (~@ #:c-id c-id)) #:wrap (named-binding 'name wrap)))

(define-compat str-block-drop
  (_fun _pointer -> _void))

(define-compat str-block-drop-count
  (_fun -> _size))

(define ((result-only who) v)
  (raise-argument-error who "a result, never an argument" v))

;; Atomic, so a thread killed in the conversion, which skips with-release's
;; post thunk, is killed only after the drop.
(define ((block-reader read) p)
  (call-as-atomic
   (lambda () (with-release ([block p str-block-drop]) (and block (read block))))))

(define _rsstr
  (make-ctype _pointer (result-only '_rsstr) (block-reader str-block->string)))

(define _rsstr-list
  (make-ctype _pointer (result-only '_rsstr-list) (block-reader str-block->strings)))

(define (c-string-argument v)
  (match v
    [(and (? string?) (not (regexp #rx"\0"))) v]
    [_ (raise-argument-error '_c-string "a string without a NUL" v)]))

(define (c-string/null-argument v)
  (and v (c-string-argument v)))

(define _c-string (make-ctype _string/utf-8 c-string-argument #f))

(define _c-string/null (make-ctype _string/utf-8 c-string/null-argument #f))

(module+ internal
  (provide block-reader))
