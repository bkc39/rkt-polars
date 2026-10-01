#lang racket/base

;; Polars-style rendering of a series to a string (used by the series wrapper's
;; prop:custom-write).  Operates on the raw FFI series (a wrapped series marshals
;; through), so this is a leaf with no dependency on the wrapper core.

(require (only-in gregor
                  ->date ->nanoseconds ->time ->year date->iso8601 date? datetime?)
         (only-in gregor/period period-ref)
         (only-in gregor/time time? time->iso8601)
         (only-in racket/format ~r)
         racket/list
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

(define (clock->cell t)
  (define ns (->nanoseconds t))
  (define whole (car (string-split (time->iso8601 t) ".")))
  (define digits
    (cond [(zero? ns) 0]
          [(zero? (remainder ns 1000000)) 3]
          [(zero? (remainder ns 1000)) 6]
          [else 9]))
  (if (zero? digits)
      whole
      (string-append whole "." (substring (~r ns #:min-width 9 #:pad-string "0") 0 digits))))

(define (duration->cell v unit)
  (define-values (sizes zero fraction-labels)
    (case unit
      [(nanoseconds) (values '(86400000000000 3600000000000 60000000000 1000000000)
                             "0ns" '("ns" "µs" "ms"))]
      [(milliseconds) (values '(86400000 3600000 60000 1000) "0ms" '("ms" "" ""))]
      [else (values '(86400000000 3600000000 60000000 1000000) "0µs" '("µs" "ms" ""))]))
  (define (whole-parts)
    (for/list ([size (in-list sizes)]
               [above (in-list (cons #f sizes))]
               [label (in-list '("d" "h" "m" "s"))]
               #:unless (zero? (quotient (if above (remainder v above) v) size)))
      (string-append (number->string (quotient (if above (remainder v above) v) size))
                     label
                     (if (zero? (remainder v size)) "" " "))))
  (define (fraction-part)
    (define f (remainder v (last sizes)))
    (cond
      [(zero? f) ""]
      [(not (zero? (remainder f 1000))) (format "~a~a" f (first fraction-labels))]
      [(not (zero? (remainder f 1000000))) (format "~a~a" (quotient f 1000) (second fraction-labels))]
      [else (format "~a~a" (quotient f 1000000) (third fraction-labels))]))
  (if (zero? v)
      zero
      (string-append (string-append* (whole-parts)) (fraction-part))))

(define (date->cell d)
  (if (> (->year d) 9999)
      (string-append "+" (date->iso8601 d))
      (date->iso8601 d)))

(define (value->cell v dt)
  (cond
    [(polars-null? v) "null"]
    [(and (pair? dt) (eq? (car dt) 'duration)) (duration->cell (period-ref v (cadr dt)) (cadr dt))]
    [(date? v) (date->cell v)]
    [(time? v) (clock->cell v)]
    [(datetime? v) (string-append (date->cell (->date v)) " " (clock->cell (->time v)))]
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
  (define (cells s) (cdddr (string-split (series->string s) #rx"\n\t?")))
  (check-equal? (cells (series-cast (series-new-i32 "d" '(15706 -1 2932897 -719893)) 'date))
                '("2013-01-01" "1969-12-31" "+10000-01-01" "-0001-01-01" "]"))
  (check-equal? (cells (series-cast (series-new-i64 "t" '(0 1500000000 1000 1)) 'time))
                '("00:00:00" "00:00:01.500" "00:00:00.000001" "00:00:00.000000001" "]"))
  (check-equal? (cells (series-cast (series-new-i64 "dt" (list 1500 -1 polars-null))
                                    '(datetime milliseconds)))
                '("1970-01-01 00:00:01.500" "1969-12-31 23:59:59.999" "null" "]"))
  (check-equal? (cells (series-cast (series-new-i64 "d" (list 0 5400000000 129600000000 -1500
                                                              86400000001 polars-null))
                                    '(duration microseconds)))
                '("0µs" "1h 30m" "1d 12h" "-1500µs" "1d 1µs" "null" "]"))
  (check-equal? (cells (series-cast (series-new-i64 "d" '(1500 61000000000)) '(duration nanoseconds)))
                '("1500ns" "1m 1s" "]"))
  (check-equal? (cells (series-cast (series-new-i64 "d" '(1500 0)) '(duration milliseconds)))
                '("1s 500ms" "0ms" "]")))
