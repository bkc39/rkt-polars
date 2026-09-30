#lang racket/base

;; Polars-style rendering of a series to a string (used by the series wrapper's
;; prop:custom-write).  Operates on the raw FFI series (a wrapped series marshals
;; through), so this is a leaf with no dependency on the wrapper core.

(require racket/list
         racket/string
         polars/private/foreign)

(provide series->string)

(define (dtype->polars-label dt)
  (define (tu->label tu)
    (case tu
      [(milliseconds) "ms"]
      [(microseconds) "us"]
      [(nanoseconds)  "ns"]
      [else (format "~a" tu)]))
  (cond
    [(symbol? dt)
     (case dt
       [(int8) "i8"] [(int16) "i16"] [(int32) "i32"] [(int64) "i64"]
       [(uint8) "u8"] [(uint16) "u16"] [(uint32) "u32"] [(uint64) "u64"]
       [(float32) "f32"] [(float64) "f64"]
       [(string) "str"] [(boolean) "bool"]
       [(date) "date"] [(time) "time"]
       [(categorical) "cat"]
       [else (format "~a" dt)])]
    [(and (pair? dt) (eq? (car dt) 'enum)) "enum"]
    [(decimal-dtype? dt) (format "decimal[~a,~a]" (cadr dt) (caddr dt))]
    [(and (pair? dt) (eq? (car dt) 'datetime))
     (format "datetime[~a]" (tu->label (cadr dt)))]
    [(and (pair? dt) (eq? (car dt) 'duration))
     (format "duration[~a]" (tu->label (cadr dt)))]
    [else (format "~a" dt)]))

(define (value->cell v dt)
  (cond
    [(polars-null? v) "null"]
    [(string? v) (format "~s" v)]      ; quoted, like Polars
    [(symbol? v) (format "~s" (symbol->string v))]
    [(and (decimal-dtype? dt) (positive? (caddr dt))) (real->decimal-string v (caddr dt))]
    [else (format "~a" v)]))

;; Polars shows at most ~10 rows: the first 5, an ellipsis, then the last 5.
(define (row-indices len)
  (if (<= len 10)
      (range len)
      (append (range 0 5) (list 'ellipsis) (range (- len 5) len))))

(define (series->string s)
  (define len (series-len s))
  (define dt (series-dtype s))
  (define lines
    (for/list ([i (in-list (row-indices len))])
      (if (eq? i 'ellipsis)
          "\t…"
          (string-append "\t" (value->cell (series-ref s i) dt)))))
  (string-append
   (format "shape: (~a,)\n" len)
   (format "Series: '~a' [~a]\n" (series-name s) (dtype->polars-label dt))
   "[\n"
   (string-join lines "\n")
   "\n]"))

(module+ test
  ;; series->string operates on the raw FFI series, so build them directly here
  ;; (printing is a leaf — no dependency on the wrapper core).
  (require rackunit racket/list
           (only-in polars/private/foreign
                    series-cast series-new-i32 series-new-i64 series-new-str polars-null))
  (define ints (series-new-i32 "ints" '(1 2 3 4)))
  (check-true (regexp-match? #rx"shape: \\(4,\\)" (series->string ints)))
  (check-true (regexp-match? #rx"Series: 'ints' \\[i32\\]" (series->string ints)))
  (define big (series-new-i64 "big" (range 100)))
  (check-true (regexp-match? #rx"…" (series->string big)))
  (define withnull (series-new-i32 "withnull" (list 10 polars-null 30)))
  (check-true (regexp-match? #rx"null" (series->string withnull)))
  (define bears (series-new-str "bears" '("Polar" "Brown")))
  (check-equal? (series->string (series-cast bears 'categorical))
                "shape: (2,)\nSeries: 'bears' [cat]\n[\n\t\"Polar\"\n\t\"Brown\"\n]")
  (check-true (regexp-match? #rx"\\[enum\\]"
                             (series->string (series-cast bears '(enum Brown Polar)))))
  (check-true (regexp-match? (regexp-quote "\t\"a\\u0000b\"\n")
                             (series->string (series-new-str "nul" '("a\u0000b"))))))
