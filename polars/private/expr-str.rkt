#lang racket/base

;; Expr string namespace wrappers.

(require ffi/unsafe
         ffi/unsafe/alloc
         polars/private/expr-core)

(provide expr-str-contains expr-str-starts-with expr-str-ends-with
         expr-str-to-lowercase expr-str-to-uppercase
         expr-str-replace expr-str-replace-all expr-str-extract
         expr-str-strip-chars expr-str-strip-chars-start expr-str-strip-chars-end
         expr-str-strip-prefix expr-str-strip-suffix
         expr-str-len-bytes expr-str-len-chars
         expr-str-slice expr-str-head expr-str-tail
         expr-str-find expr-str-find-literal expr-str-count-matches
         expr-str-to-date expr-str-to-datetime expr-str-to-time)

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

(define-compat expr-str-len-bytes
  (_fun _Expr-ptr -> _Expr-ptr)
  #:c-id expr_str_len_bytes
  #:wrap (allocator expr-drop))

(define-compat expr-str-len-chars
  (_fun _Expr-ptr -> _Expr-ptr)
  #:c-id expr_str_len_chars
  #:wrap (allocator expr-drop))

(define-compat expr-str-slice/raw
  (_fun _Expr-ptr _Expr-ptr _Expr-ptr -> _Expr-ptr)
  #:c-id expr_str_slice
  #:wrap (allocator expr-drop))

(define (expr-str-slice e offset length)
  (expr-str-slice/raw e (->expr offset) (->expr length)))

(define-compat expr-str-head/raw
  (_fun _Expr-ptr _Expr-ptr -> _Expr-ptr)
  #:c-id expr_str_head
  #:wrap (allocator expr-drop))

(define (expr-str-head e n)
  (expr-str-head/raw e (->expr n)))

(define-compat expr-str-tail/raw
  (_fun _Expr-ptr _Expr-ptr -> _Expr-ptr)
  #:c-id expr_str_tail
  #:wrap (allocator expr-drop))

(define (expr-str-tail e n)
  (expr-str-tail/raw e (->expr n)))

(define-compat expr-str-find/raw
  (_fun _Expr-ptr _Expr-ptr _uint8 -> _Expr-ptr)
  #:c-id expr_str_find
  #:wrap (allocator expr-drop))

(define (expr-str-find e pat #:strict [strict #t])
  (expr-str-find/raw e (->expr pat) (if strict 1 0)))

(define-compat expr-str-find-literal/raw
  (_fun _Expr-ptr _Expr-ptr -> _Expr-ptr)
  #:c-id expr_str_find_literal
  #:wrap (allocator expr-drop))

(define (expr-str-find-literal e pat)
  (expr-str-find-literal/raw e (->expr pat)))

(define-compat expr-str-count-matches/raw
  (_fun _Expr-ptr _Expr-ptr _uint8 -> _Expr-ptr)
  #:c-id expr_str_count_matches
  #:wrap (allocator expr-drop))

(define (expr-str-count-matches e pat #:literal [literal #f])
  (expr-str-count-matches/raw e (->expr pat) (if literal 1 0)))

(define compat-time-unit/nanoseconds 1)
(define compat-time-unit/microseconds 2)
(define compat-time-unit/milliseconds 3)

(define (time-unit-symbol->code who unit)
  (case unit
    [(nanoseconds) compat-time-unit/nanoseconds]
    [(microseconds) compat-time-unit/microseconds]
    [(milliseconds) compat-time-unit/milliseconds]
    [else (error who
                 "unknown time unit ~v (expected 'nanoseconds, 'microseconds, or 'milliseconds)"
                 unit)]))

(define (check-strptime-options who format strict exact cache)
  (when (and format (not (string? format)))
    (error who "format must be a string or #f, got ~v" format))
  (unless (boolean? strict)
    (error who "strict must be a boolean, got ~v" strict))
  (unless (boolean? exact)
    (error who "exact must be a boolean, got ~v" exact))
  (unless (boolean? cache)
    (error who "cache must be a boolean, got ~v" cache)))

(define-compat expr-str-to-date/raw
  (_fun _Expr-ptr _string _uint8 _uint8 _uint8 _uint8 -> _Expr-ptr)
  #:c-id expr_str_to_date
  #:wrap (allocator expr-drop))

(define (expr-str-to-date e
                          #:format [format #f]
                          #:strict [strict #t]
                          #:exact [exact #t]
                          #:cache [cache #t])
  (check-strptime-options 'expr-str-to-date format strict exact cache)
  (expr-str-to-date/raw e
                        (or format "")
                        (if format 1 0)
                        (if strict 1 0)
                        (if exact 1 0)
                        (if cache 1 0)))

(define-compat expr-str-to-datetime/raw
  (_fun _Expr-ptr _string _uint8 _int32 _uint8 _uint8 _uint8 -> _Expr-ptr)
  #:c-id expr_str_to_datetime
  #:wrap (allocator expr-drop))

(define (expr-str-to-datetime e
                              #:format [format #f]
                              #:unit [unit 'microseconds]
                              #:strict [strict #t]
                              #:exact [exact #t]
                              #:cache [cache #t])
  (check-strptime-options 'expr-str-to-datetime format strict exact cache)
  (expr-str-to-datetime/raw e
                            (or format "")
                            (if format 1 0)
                            (time-unit-symbol->code 'expr-str-to-datetime unit)
                            (if strict 1 0)
                            (if exact 1 0)
                            (if cache 1 0)))

(define-compat expr-str-to-time/raw
  (_fun _Expr-ptr _string _uint8 _uint8 _uint8 _uint8 -> _Expr-ptr)
  #:c-id expr_str_to_time
  #:wrap (allocator expr-drop))

(define (expr-str-to-time e
                          #:format [format #f]
                          #:strict [strict #t]
                          #:exact [exact #t]
                          #:cache [cache #t])
  (check-strptime-options 'expr-str-to-time format strict exact cache)
  (expr-str-to-time/raw e
                        (or format "")
                        (if format 1 0)
                        (if strict 1 0)
                        (if exact 1 0)
                        (if cache 1 0)))
