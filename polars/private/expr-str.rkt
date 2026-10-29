#lang racket/base

;; Expr string namespace wrappers.

(require ffi/unsafe
         ffi/unsafe/alloc
         (only-in polars/private/c-integer size/c)
         (only-in racket/contract/base ->* any/c contract-out flat-contract-predicate)
         polars/private/expr-core
         (only-in polars/private/foreign
                  _c-string call/foreign-error call/polars-reason polars-null)
         (only-in polars/private/resource _str/null utf-8-name/c))

(provide expr-str-contains expr-str-starts-with expr-str-ends-with
         expr-str-to-lowercase expr-str-to-uppercase
         expr-str-replace expr-str-replace-all
         expr-str-strip-chars expr-str-strip-chars-start expr-str-strip-chars-end
         expr-str-strip-prefix expr-str-strip-suffix
         expr-str-len-bytes expr-str-len-chars
         expr-str-slice expr-str-head expr-str-tail
         expr-str-find expr-str-find-literal expr-str-count-matches
         expr-str->date expr-str->datetime expr-str->time
         parse-datetime
         (contract-out
          [expr-str-extract (->* (Expr-ptr? any/c) (#:group-index size/c) Expr-ptr?)]))

(define-compat expr-str-contains/raw
  (_fun _Expr-ptr _Expr-ptr _uint8 -> _Expr-ptr)
  #:c-id expr_str_contains
  #:wrap (allocator expr-drop))

(define (expr-str-contains e pat #:strict [strict #t])
  (expr-str-contains/raw e (->expr/who 'expr-str-contains pat) (if strict 1 0)))

(define-compat expr-str-starts-with/raw
  (_fun _Expr-ptr _Expr-ptr -> _Expr-ptr)
  #:c-id expr_str_starts_with
  #:wrap (allocator expr-drop))

(define (expr-str-starts-with e prefix)
  (expr-str-starts-with/raw e (->expr/who 'expr-str-starts-with prefix)))

(define-compat expr-str-ends-with/raw
  (_fun _Expr-ptr _Expr-ptr -> _Expr-ptr)
  #:c-id expr_str_ends_with
  #:wrap (allocator expr-drop))

(define (expr-str-ends-with e suffix)
  (expr-str-ends-with/raw e (->expr/who 'expr-str-ends-with suffix)))

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
  (expr-str-replace/raw e (->expr/who 'expr-str-replace pat) (->expr/who 'expr-str-replace value)
                        (if literal 1 0)))

(define-compat expr-str-replace-all/raw
  (_fun _Expr-ptr _Expr-ptr _Expr-ptr _uint8 -> _Expr-ptr)
  #:c-id expr_str_replace_all
  #:wrap (allocator expr-drop))

(define (expr-str-replace-all e pat value #:literal [literal #f])
  (expr-str-replace-all/raw e (->expr/who 'expr-str-replace-all pat)
                            (->expr/who 'expr-str-replace-all value) (if literal 1 0)))

(define-compat expr-str-extract/raw
  (_fun _Expr-ptr _Expr-ptr _size -> _Expr-ptr)
  #:c-id expr_str_extract
  #:wrap (allocator expr-drop))

(define (expr-str-extract e pat #:group-index [group-index 1])
  (expr-str-extract/raw e (->expr/who 'expr-str-extract pat) group-index))

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
      (expr-str-strip-chars/raw e (->expr/who 'expr-str-strip-chars chars))
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
      (expr-str-strip-chars-start/raw e (->expr/who 'expr-str-strip-chars-start chars))
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
      (expr-str-strip-chars-end/raw e (->expr/who 'expr-str-strip-chars-end chars))
      (expr-str-strip-chars-end/whitespace e)))

(define-compat expr-str-strip-prefix/raw
  (_fun _Expr-ptr _Expr-ptr -> _Expr-ptr)
  #:c-id expr_str_strip_prefix
  #:wrap (allocator expr-drop))

(define (expr-str-strip-prefix e prefix)
  (expr-str-strip-prefix/raw e (->expr/who 'expr-str-strip-prefix prefix)))

(define-compat expr-str-strip-suffix/raw
  (_fun _Expr-ptr _Expr-ptr -> _Expr-ptr)
  #:c-id expr_str_strip_suffix
  #:wrap (allocator expr-drop))

(define (expr-str-strip-suffix e suffix)
  (expr-str-strip-suffix/raw e (->expr/who 'expr-str-strip-suffix suffix)))

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

(define (expr-str-slice e offset [len polars-null])
  (expr-str-slice/raw e (->expr/who 'expr-str-slice offset)
                      (->expr/who 'expr-str-slice (or len polars-null))))

(define-compat expr-str-head/raw
  (_fun _Expr-ptr _Expr-ptr -> _Expr-ptr)
  #:c-id expr_str_head
  #:wrap (allocator expr-drop))

(define (expr-str-head e n)
  (expr-str-head/raw e (->expr/who 'expr-str-head n)))

(define-compat expr-str-tail/raw
  (_fun _Expr-ptr _Expr-ptr -> _Expr-ptr)
  #:c-id expr_str_tail
  #:wrap (allocator expr-drop))

(define (expr-str-tail e n)
  (expr-str-tail/raw e (->expr/who 'expr-str-tail n)))

(define-compat expr-str-find/raw
  (_fun _Expr-ptr _Expr-ptr _uint8 -> _Expr-ptr)
  #:c-id expr_str_find
  #:wrap (allocator expr-drop))

(define (expr-str-find e pat #:strict [strict #t])
  (expr-str-find/raw e (->expr/who 'expr-str-find pat) (if strict 1 0)))

(define-compat expr-str-find-literal/raw
  (_fun _Expr-ptr _Expr-ptr -> _Expr-ptr)
  #:c-id expr_str_find_literal
  #:wrap (allocator expr-drop))

(define (expr-str-find-literal e pat)
  (expr-str-find-literal/raw e (->expr/who 'expr-str-find-literal pat)))

(define-compat expr-str-count-matches/raw
  (_fun _Expr-ptr _Expr-ptr _uint8 -> _Expr-ptr)
  #:c-id expr_str_count_matches
  #:wrap (allocator expr-drop))

(define (expr-str-count-matches e pat #:literal [literal #f])
  (expr-str-count-matches/raw e (->expr/who 'expr-str-count-matches pat) (if literal 1 0)))

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

(define (flag b) (if b 1 0))

(define utf-8-name? (flat-contract-predicate utf-8-name/c))

(define (check-strptime-options who format strict exact cache)
  (unless (or (not format) (utf-8-name? format))
    (error who "format must be a UTF-8 name or #f, got ~v" format))
  (unless (boolean? strict)
    (error who "strict must be a boolean, got ~v" strict))
  (unless (boolean? exact)
    (error who "exact must be a boolean, got ~v" exact))
  (unless (boolean? cache)
    (error who "cache must be a boolean, got ~v" cache)))

(define-compat expr-str->date/raw
  (_fun _Expr-ptr _str/null _uint8 _uint8 _uint8 -> _Expr-ptr/null)
  #:c-id expr_str_to_date_v2
  #:wrap (allocator expr-drop))

(define (expr-str->date e
                        #:format [format #f]
                        #:strict [strict #t]
                        #:exact [exact #t]
                        #:cache [cache #t])
  (expr-str->date/who 'expr-str->date e format strict exact cache))

(define (expr-str->date/who who e format strict exact cache)
  (check-strptime-options who format strict exact cache)
  (call/polars-reason who
                      (lambda ()
                        (expr-str->date/raw e format (flag strict) (flag exact) (flag cache)))))

(define-compat expr-str->datetime/raw
  (_fun _Expr-ptr _str/null _int32 _uint8 _uint8 _uint8 -> _Expr-ptr/null)
  #:c-id expr_str_to_datetime_v2
  #:wrap (allocator expr-drop))

(define-compat expr-str->datetime-tz/raw
  (_fun _Expr-ptr _str/null _int32 _c-string _c-string _uint8 _uint8 _uint8 -> _Expr-ptr/null)
  #:c-id expr_str_to_datetime_tz_v2
  #:wrap (allocator expr-drop))

(define (expr-str->datetime e
                            #:format [format #f]
                            #:unit [unit 'microseconds]
                            #:strict [strict #t]
                            #:exact [exact #t]
                            #:cache [cache #t])
  (parse-datetime 'expr-str->datetime e format unit #f 'raise strict exact cache))

(define (parse-datetime who e format unit time-zone ambiguous strict exact cache)
  (check-strptime-options who format strict exact cache)
  (define code (time-unit-symbol->code who unit))
  (if time-zone
      (call/foreign-error who
                          (lambda ()
                            (expr-str->datetime-tz/raw e format code
                                                       time-zone (symbol->string ambiguous)
                                                       (flag strict) (flag exact) (flag cache)))
                          "cannot parse into the time zone ~s" time-zone)
      (call/polars-reason who
                          (lambda ()
                            (expr-str->datetime/raw e format code
                                                    (flag strict) (flag exact) (flag cache))))))

(define-compat expr-str->time/raw
  (_fun _Expr-ptr _str/null _uint8 _uint8 _uint8 -> _Expr-ptr/null)
  #:c-id expr_str_to_time_v2
  #:wrap (allocator expr-drop))

(define (expr-str->time e
                        #:format [format #f]
                        #:strict [strict #t]
                        #:exact [exact #t]
                        #:cache [cache #t])
  (expr-str->time/who 'expr-str->time e format strict exact cache))

(define (expr-str->time/who who e format strict exact cache)
  (check-strptime-options who format strict exact cache)
  (call/polars-reason who
                      (lambda ()
                        (expr-str->time/raw e format (flag strict) (flag exact) (flag cache)))))

(module+ internal
  (provide expr-str->date/who expr-str->datetime-tz/raw expr-str->time/who))
