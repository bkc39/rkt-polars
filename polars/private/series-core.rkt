#lang racket/base

(require ffi/unsafe
         ffi/unsafe/alloc
         (only-in racket/contract/base [-> ->/c] any/c contract-out)
         racket/match
         (only-in polars/private/compat-dtype ->compat-dtype _CompatDType compat-dtype->datum
                  datetime-zone/c enum-dtype? time-unit-symbol->code zoned-datetime-dtype?)
         (only-in polars/private/compat-ffi _c-string _c-string/null _rsstr define-compat)
         (only-in polars/private/owned Series-ptr? _Series-ptr _Series-ptr/null)
         (only-in polars/private/reason call/foreign-error call/polars-reason)
         (only-in (submod polars/private/owned internal) series-drop)
         (only-in polars/private/resource _str _str-list with-raw-buffer with-release))

(provide (except-out (all-defined-out) named series-cast series-rename/who series-strings)
         (contract-out
          [series-cast (->/c any/c datetime-zone/c Series-ptr?)]))

(define-compat series-empty
  (_fun -> _Series-ptr)
  #:wrap (allocator series-drop))

(define-compat series-name
  (_fun _Series-ptr -> _rsstr)
  #:c-id series_name_v2)

(define-compat series-dtype/raw
  (_fun _Series-ptr -> _CompatDType)
  #:c-id series_dtype)

(define-compat series-enum-categories/raw
  (_fun _Series-ptr -> _Series-ptr/null)
  #:c-id series_enum_categories_v2
  #:wrap (allocator series-drop))

(define (series-enum-categories s)
  (with-release ([names (call/polars-reason 'series-enum-categories
                                            (lambda () (series-enum-categories/raw s)))
                        series-drop])
    (map string->symbol (series-strings names 0 (series-len names)))))

(define-compat series-time-zone
  (_fun _Series-ptr -> _rsstr)
  #:c-id series_time_zone_v2)

(define (series-dtype series)
  (match (compat-dtype->datum (series-dtype/raw series))
    ['enum (cons 'enum (series-enum-categories series))]
    [(list 'datetime unit 'zoned) (list 'datetime unit (series-time-zone series))]
    [dtype dtype]))

(define-compat series-rename/raw
  (_fun _Series-ptr _str -> _int32)
  #:c-id series_rename_v2)

(define (series-rename/who who s name)
  (call/foreign-error who (lambda () (series-rename/raw s name)) #:ok? zero?)
  (void))

(define (series-rename s name)
  (series-rename/who 'series-rename s name))

(define ((named who name) s)
  (series-rename/who who s name)
  s)

(define-compat series-len
  (_fun _Series-ptr -> _size))

(define-compat series-null-count
  (_fun _Series-ptr -> _size))

(define-compat series-str-byte-len
  (_fun _Series-ptr _size _size -> _int64))

;; The buffers are GC memory the collector may move: never #:blocking?.
(define-compat series-copy-str
  (_fun _Series-ptr _size _size _bytes _size _pointer _size _bytes _size -> _int64))

;; By length, not as a C string, which would end at a NUL a value holds. A
;; null row reads as ""; a series that is not a String one as #f.
(define (series-strings s start count)
  (define size (series-str-byte-len s start count))
  (cond
    [(negative? size) #f]
    [else
     (define buf (make-bytes size))
     (with-raw-buffer ([offsets (add1 count) _int64])
       (and (not (negative? (series-copy-str s start count buf size offsets (add1 count) #f 0)))
            (for/list ([i (in-range count)])
              (bytes->string/utf-8 buf #f
                                   (ptr-ref offsets _int64 i)
                                   (ptr-ref offsets _int64 (add1 i))))))]))

(define-compat series-cast/c
  (_fun _Series-ptr _CompatDType -> _Series-ptr/null)
  #:c-id series_cast
  #:wrap (allocator series-drop))

(define-compat series-cast-enum/raw
  (_fun _Series-ptr _str-list -> _Series-ptr/null)
  #:c-id series_cast_enum_v2
  #:wrap (allocator series-drop))

(define (series-cast-enum who s dtype)
  (call/foreign-error who
                      (lambda () (series-cast-enum/raw s (map symbol->string (cdr dtype))))
                      "cannot convert to ~v" dtype))

(define-compat series-cast-datetime-tz/raw
  (_fun _Series-ptr _int32 _c-string -> _Series-ptr/null)
  #:c-id series_cast_datetime_tz
  #:wrap (allocator series-drop))

(define (series-cast-datetime-tz who s dtype)
  (match-define (list _ unit zone) dtype)
  (call/foreign-error who
                      (lambda ()
                        (series-cast-datetime-tz/raw s (time-unit-symbol->code unit) zone))
                      "cannot convert to ~v" dtype))

(define (series-cast-to who s dtype)
  (cond
    [(enum-dtype? dtype) (series-cast-enum who s dtype)]
    [(zoned-datetime-dtype? dtype) (series-cast-datetime-tz who s dtype)]
    [else (call/foreign-error who (lambda () (series-cast/c s (->compat-dtype dtype)))
                              "cannot cast to ~s" dtype)]))

(define (series-cast s dtype)
  (series-cast-to 'series-cast s dtype))

(define-compat series-dt-convert-time-zone/raw
  (_fun _Series-ptr _c-string -> _Series-ptr/null)
  #:c-id series_dt_convert_time_zone
  #:wrap (allocator series-drop))

(define (series-dt-convert-time-zone who s zone)
  (call/foreign-error who
                      (lambda () (series-dt-convert-time-zone/raw s zone))
                      "cannot convert to the time zone ~s" zone))

(define-compat series-dt-replace-time-zone/raw
  (_fun _Series-ptr _c-string/null _c-string _c-string -> _Series-ptr/null)
  #:c-id series_dt_replace_time_zone
  #:wrap (allocator series-drop))

(define (series-dt-replace-time-zone who s zone ambiguous non-existent)
  (call/foreign-error who
                      (lambda ()
                        (series-dt-replace-time-zone/raw s zone (symbol->string ambiguous)
                                                         (symbol->string non-existent)))
                      "~a" (replace-zone-failure zone)))

(define (replace-zone-failure zone)
  (if zone
      (format "cannot replace the time zone with ~s" zone)
      "cannot unset the time zone"))

(module+ internal
  (provide named series-rename/who series-strings))
