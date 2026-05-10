#lang racket/base

;; Expr string namespace wrappers.

(require ffi/unsafe
         ffi/unsafe/alloc
         polars/private/expr-core)

(provide expr-str-contains expr-str-starts-with expr-str-ends-with
         expr-str-to-lowercase expr-str-to-uppercase
         expr-str-replace expr-str-replace-all expr-str-extract
         expr-str-strip-chars expr-str-strip-chars-start expr-str-strip-chars-end
         expr-str-strip-prefix expr-str-strip-suffix)

(define-compat expr-str-contains/raw
  (_fun _Expr-ptr _Expr-ptr _uint8 -> _Expr-ptr)
  #:c-id expr_str_contains
  #:wrap (allocator expr-drop))

(define (expr-str-contains e pat #:strict [strict #t])
  (expr-str-contains/raw e (->expr pat) (if strict 1 0)))

(define-compat expr-str-starts-with/raw
  (_fun _Expr-ptr _Expr-ptr -> _Expr-ptr)
  #:c-id expr_str_starts_with
  #:wrap (allocator expr-drop))

(define (expr-str-starts-with e prefix)
  (expr-str-starts-with/raw e (->expr prefix)))

(define-compat expr-str-ends-with/raw
  (_fun _Expr-ptr _Expr-ptr -> _Expr-ptr)
  #:c-id expr_str_ends_with
  #:wrap (allocator expr-drop))

(define (expr-str-ends-with e suffix)
  (expr-str-ends-with/raw e (->expr suffix)))

(define-compat expr-str-to-lowercase
  (_fun _Expr-ptr -> _Expr-ptr)
  #:c-id expr_str_to_lowercase
  #:wrap (allocator expr-drop))

(define-compat expr-str-to-uppercase
  (_fun _Expr-ptr -> _Expr-ptr)
  #:c-id expr_str_to_uppercase
  #:wrap (allocator expr-drop))

(define-compat expr-str-replace/raw
  (_fun _Expr-ptr _Expr-ptr _Expr-ptr _uint8 -> _Expr-ptr)
  #:c-id expr_str_replace
  #:wrap (allocator expr-drop))

(define (expr-str-replace e pat value #:literal [literal #f])
  (expr-str-replace/raw e (->expr pat) (->expr value) (if literal 1 0)))

(define-compat expr-str-replace-all/raw
  (_fun _Expr-ptr _Expr-ptr _Expr-ptr _uint8 -> _Expr-ptr)
  #:c-id expr_str_replace_all
  #:wrap (allocator expr-drop))

(define (expr-str-replace-all e pat value #:literal [literal #f])
  (expr-str-replace-all/raw e (->expr pat) (->expr value) (if literal 1 0)))

(define-compat expr-str-extract/raw
  (_fun _Expr-ptr _Expr-ptr _size -> _Expr-ptr)
  #:c-id expr_str_extract
  #:wrap (allocator expr-drop))

(define (expr-str-extract e pat #:group-index [group-index 1])
  (unless (exact-nonnegative-integer? group-index)
    (error 'expr-str-extract
           "group index must be an exact nonnegative integer, got ~v"
           group-index))
  (expr-str-extract/raw e (->expr pat) group-index))

(define-compat expr-str-strip-chars/raw
  (_fun _Expr-ptr _Expr-ptr -> _Expr-ptr)
  #:c-id expr_str_strip_chars
  #:wrap (allocator expr-drop))

(define-compat expr-str-strip-chars/whitespace
  (_fun _Expr-ptr -> _Expr-ptr)
  #:c-id expr_str_strip_chars_whitespace
  #:wrap (allocator expr-drop))

(define (expr-str-strip-chars e [chars #f])
  (if chars
      (expr-str-strip-chars/raw e (->expr chars))
      (expr-str-strip-chars/whitespace e)))

(define-compat expr-str-strip-chars-start/raw
  (_fun _Expr-ptr _Expr-ptr -> _Expr-ptr)
  #:c-id expr_str_strip_chars_start
  #:wrap (allocator expr-drop))

(define-compat expr-str-strip-chars-start/whitespace
  (_fun _Expr-ptr -> _Expr-ptr)
  #:c-id expr_str_strip_chars_start_whitespace
  #:wrap (allocator expr-drop))

(define (expr-str-strip-chars-start e [chars #f])
  (if chars
      (expr-str-strip-chars-start/raw e (->expr chars))
      (expr-str-strip-chars-start/whitespace e)))

(define-compat expr-str-strip-chars-end/raw
  (_fun _Expr-ptr _Expr-ptr -> _Expr-ptr)
  #:c-id expr_str_strip_chars_end
  #:wrap (allocator expr-drop))

(define-compat expr-str-strip-chars-end/whitespace
  (_fun _Expr-ptr -> _Expr-ptr)
  #:c-id expr_str_strip_chars_end_whitespace
  #:wrap (allocator expr-drop))

(define (expr-str-strip-chars-end e [chars #f])
  (if chars
      (expr-str-strip-chars-end/raw e (->expr chars))
      (expr-str-strip-chars-end/whitespace e)))

(define-compat expr-str-strip-prefix/raw
  (_fun _Expr-ptr _Expr-ptr -> _Expr-ptr)
  #:c-id expr_str_strip_prefix
  #:wrap (allocator expr-drop))

(define (expr-str-strip-prefix e prefix)
  (expr-str-strip-prefix/raw e (->expr prefix)))

(define-compat expr-str-strip-suffix/raw
  (_fun _Expr-ptr _Expr-ptr -> _Expr-ptr)
  #:c-id expr_str_strip_suffix
  #:wrap (allocator expr-drop))

(define (expr-str-strip-suffix e suffix)
  (expr-str-strip-suffix/raw e (->expr suffix)))
