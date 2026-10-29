#lang racket/base

;; Polars-style rendering of a series to a string (used by the series wrapper's
;; prop:custom-write).  Operates on the raw FFI series (a wrapped series marshals
;; through), so this is a leaf with no dependency on the wrapper core.

(require (only-in gregor
                  ->date ->nanoseconds ->time ->year date->iso8601 date? datetime? moment?)
         (only-in gregor/period period-ref)
         (only-in gregor/time time? time->iso8601)
         (only-in racket/format ~r)
         racket/list
         racket/string
         (only-in polars/private/expr
                  expr-all expr-drop expr-dt-strftime lazyframe-collect/raw lazyframe-select)
         (only-in (submod polars/private/expr internal) call-with-plan)
         (only-in polars/private/resource with-release)
         polars/private/foreign
         (only-in (submod polars/private/foreign internal) series-slice/who)
         (only-in threading ~>>))

(provide series->printed series->string)

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
    [(zoned-datetime-dtype? dt)
     (format "datetime[~a, ~a]" (tu->label (cadr dt)) (caddr dt))]
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

(struct unreadable (reason))

(define (cannot-print reason #:kind [kind #f])
  (format "#<~acannot print: ~a>" (if kind (format "~a: " kind) "") reason))

(define (call/cannot-print thunk #:kind [kind #f])
  (with-handlers ([exn:fail? (lambda (e) (cannot-print (exn-message e) #:kind kind))])
    (thunk)))

(define binary-shown-bytes 60)

(define (byte->cell b)
  (if (<= #x21 b #x7e)
      (string (integer->char b))
      (string-append "\\x" (~r b #:base 16 #:min-width 2 #:pad-string "0"))))

(define (bytes->cell v)
  (define shown (min (bytes-length v) binary-shown-bytes))
  (string-append "b\""
                 (~>> (subbytes v 0 shown) bytes->list (map byte->cell) string-append*)
                 (if (< shown (bytes-length v)) "\"…" "\"")))

(define (value->cell v dt [abbreviation #f])
  (cond
    [(polars-null? v) "null"]
    [(unreadable? v) (cannot-print (unreadable-reason v))]
    [(bytes? v) (bytes->cell v)]
    [(and (pair? dt) (eq? (car dt) 'duration)) (duration->cell (period-ref v (cadr dt)) (cadr dt))]
    [(date? v) (date->cell v)]
    [(time? v) (clock->cell v)]
    [(or (datetime? v) (moment? v))
     (string-append (date->cell (->date v)) " " (clock->cell (->time v))
                    (if abbreviation (string-append " " abbreviation) ""))]
    [(string? v) (format "~s" v)]      ; quoted, like Polars
    [(symbol? v) (format "~s" (symbol->string v))]
    [(and (decimal-dtype? dt) (positive? (caddr dt))) (real->decimal-string v (caddr dt))]
    [else (format "~a" v)]))

;; Polars shows at most ~10 rows: the first 5, an ellipsis, then the last 5.
(define (row-indices len)
  (if (<= len 10)
      (range len)
      (append (range 0 5) (list 'ellipsis) (range (- len 5) len))))

(define (zone-abbreviations s start count)
  (define collected
    (with-release ([rows (series-slice/who 'series s start count) series-drop]
                   [frame (dataframe-new (list rows)) dataframe-drop]
                   [all (expr-all) expr-drop]
                   [zone (expr-dt-strftime all "%Z") expr-drop])
      (call-with-plan frame
                      (lambda (source) (lazyframe-select source (list zone)))
                      lazyframe-collect/raw)))
  (cond
    [collected
     (with-release ([out collected dataframe-drop]
                    [names (dataframe-column out (dataframe-column-name out 0)) series-drop])
       (for/list ([i (in-range count)])
         (series-ref names i)))]
    [(= count 1) (list #f)]
    [else (append-map (lambda (i) (zone-abbreviations s i 1)) (range start (+ start count)))]))

(define (shown-abbreviations s dt len shown)
  (cond
    [(not (zoned-datetime-dtype? dt)) (make-list shown #f)]
    [(<= len 10) (zone-abbreviations s 0 len)]
    [else (append (zone-abbreviations s 0 5) (list #f) (zone-abbreviations s (- len 5) 5))]))

(define (cell s dt i abbreviation)
  (call/cannot-print
   (lambda ()
     (cond
       [(eq? i 'ellipsis) "…"]
       [(eq? dt 'binary)
        (value->cell (series-ref-bytes 'series->string s i (add1 binary-shown-bytes)) dt)]
       [else (value->cell (series-value 'series->string s i #:unreadable unreadable)
                          dt abbreviation)]))))

(define (series->printed s)
  (call/cannot-print (lambda () (series->string s)) #:kind 'series))

(define (series->string s)
  (define len (series-len s))
  (define dt (series-dtype s))
  (define indices (row-indices len))
  (define lines
    (for/list ([i (in-list indices)]
               [abbreviation (in-list (shown-abbreviations s dt len (length indices)))])
      (string-append "\t" (cell s dt i abbreviation) "\n")))
  (string-append
   (format "shape: (~a,)\n" len)
   (format "Series: '~a' [~a]\n" (series-name s) (dtype->polars-label dt))
   "[\n"
   (string-append* lines)
   "]"))

(module+ internal
  (provide cell))
