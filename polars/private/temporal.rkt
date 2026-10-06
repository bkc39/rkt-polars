#lang racket/base

(module gregor-private racket/base
  (provide check-gregor-export)

  (define (exported-names exports)
    (for*/list ([phase+names (in-list exports)]
                #:when (eqv? (car phase+names) 0)
                [export (in-list (cdr phase+names))])
      (car export)))

  (define (provides? mod name)
    (cond
      [(with-handlers ([exn:fail? (lambda (_) #f)]) (module-declared? mod #t))
       (define-values (variables syntaxes) (module->exports mod))
       (memq name (append (exported-names variables) (exported-names syntaxes)))]
      [else #f]))

  (define (check-gregor-export mod name)
    (unless (provides? mod name)
      (error 'polars
             (string-append "~a no longer provides ~a, which reads a zoned datetime back"
                            " as a moment; see https://github.com/bkc39/rkt-polars/issues/172")
             mod name))))

(require (for-syntax racket/base 'gregor-private))

;; gregor's only constructor that attaches a zone's name to an offset tzinfo
;; did not compute is private (#172); a rename fails here, by name.
(begin-for-syntax
  (check-gregor-export 'gregor/private/moment-base 'make-moment))

(require (only-in gregor
                  ->datetime/utc ->hours ->jdn ->minutes ->nanoseconds ->posix ->seconds date
                  date? datetime? jdn->date moment? ->tzid posix->datetime)
         (only-in gregor/private/moment-base make-moment)
         (only-in gregor/period period? period-ref)
         (only-in gregor/time time time?)
         racket/match)

(provide days->date
         epoch->datetime
         epoch->moment
         nanoseconds->time
         offset-unit
         per-second
         temporal-encoder
         temporal-value-dtype
         temporal-values-dtype
         utc-offset
         zone-conflict)

(define unix-epoch-jdn 2440588)
(define ns/second 1000000000)
(define ns/day (* 86400 ns/second))

(define (per-second unit)
  (case unit
    [(nanoseconds) 1000000000]
    [(milliseconds) 1000]
    [else 1000000]))

(define (days->date days)
  (jdn->date (+ days unix-epoch-jdn)))

(define (epoch->datetime unit value)
  (posix->datetime (/ value (per-second unit))))

;; replace_time_zone(None) multiplies a nanosecond wall clock past i64 without
;; a check, so a wall clock is read from a microsecond view of the column,
;; which cannot overflow.
(define (offset-unit unit)
  (if (eq? unit 'nanoseconds) 'microseconds unit))

;; `clock` is the wall clock of `value`'s instant in (offset-unit unit), as
;; replace_time_zone(None) gives it. A cast to a coarser unit floors, and
;; offsets change on whole seconds, so the floored instant has value's offset.
(define (utc-offset unit value clock)
  (define view (per-second (offset-unit unit)))
  (/ (- clock (floor (/ (* value view) (per-second unit)))) view))

;; The offset is polars', not tzinfo's: tzinfo ignores the TZif footer and
;; some systems lack the backward-compatible zone names.
(define (epoch->moment unit value clock zone)
  (define offset (utc-offset unit value clock))
  (make-moment (posix->datetime (+ (/ value (per-second unit)) offset)) offset zone))

(define (nanoseconds->time value)
  (define-values (seconds nanosecond) (quotient/remainder value ns/second))
  (define-values (minutes second) (quotient/remainder seconds 60))
  (define-values (hour minute) (quotient/remainder minutes 60))
  (time hour minute second nanosecond))

(define (date->days d)
  (- (->jdn d) unix-epoch-jdn))

(define (time->nanoseconds t)
  (+ (* (+ (* (+ (* (->hours t) 60) (->minutes t)) 60) (->seconds t)) ns/second)
     (->nanoseconds t)))

(define (datetime->nanoseconds dt)
  (* (->posix dt) ns/second))

(define period-field-nanoseconds
  `((weeks . ,(* 7 ns/day)) (days . ,ns/day) (hours . ,(* 3600 ns/second))
    (minutes . ,(* 60 ns/second)) (seconds . ,ns/second) (milliseconds . 1000000)
    (microseconds . 1000) (nanoseconds . 1)))

(define (fixed-length-period? p)
  (and (period? p) (zero? (period-ref p 'years)) (zero? (period-ref p 'months))))

(define (period->nanoseconds p)
  (for/sum ([field (in-list period-field-nanoseconds)])
    (* (cdr field) (period-ref p (car field)))))

(define (ticks/unit unit)
  (quotient ns/second (per-second unit)))

(define (floor-nanoseconds->unit ns unit)
  (define k (ticks/unit unit))
  (quotient (- ns (modulo ns k)) k))

(define (truncate-nanoseconds->unit ns unit)
  (quotient ns (ticks/unit unit)))

(define (whole-microseconds? ns)
  (zero? (remainder ns 1000)))

(define (datetime-like? v)
  (or (datetime? v) (moment? v)))

(define (temporal-kind v)
  (cond
    [(date? v) 'date]
    [(time? v) 'time]
    [(datetime-like? v) 'datetime]
    [(fixed-length-period? v) 'duration]
    [else #f]))

(define (column-zone v)
  (and (moment? v) (or (->tzid v) "UTC")))

;; Two datetimes whose columns would differ in zone, as Python's is_in, which
;; finds no supertype for them, refuses; #f when every datetime agrees.
(define (zone-conflict vals)
  (define datetimes (filter datetime-like? vals))
  (cond
    [(pair? datetimes)
     (define zone (column-zone (car datetimes)))
     (for/first ([v (in-list (cdr datetimes))]
                 #:unless (equal? (column-zone v) zone))
       (list (car datetimes) v))]
    [else #f]))

(define (inferred-unit sub-microsecond? ->ns vals)
  (if (and (ormap sub-microsecond? vals) (andmap (lambda (v) (int64? (->ns v))) vals))
      'nanoseconds
      'microseconds))

(define (datetime-sub-microsecond? dt)
  (not (whole-microseconds? (->nanoseconds dt))))

(define (period-sub-microsecond? p)
  (not (whole-microseconds? (period-ref p 'nanoseconds))))

(define (temporal-values-dtype vals)
  (define kind (and (pair? vals) (temporal-kind (car vals))))
  (and kind
       (andmap (lambda (v) (eq? (temporal-kind v) kind)) vals)
       (case kind
         [(datetime)
          (list 'datetime
                (inferred-unit datetime-sub-microsecond? datetime->nanoseconds vals)
                (column-zone (car vals)))]
         [(duration)
          (list 'duration (inferred-unit period-sub-microsecond? period->nanoseconds vals))]
         [else kind])))

(define (temporal-value-dtype v)
  (temporal-values-dtype (list v)))

(define (int64? n)
  (<= (- (expt 2 63)) n (sub1 (expt 2 63))))

;; chrono's NaiveDate::MIN and MAX: polars formats every date and datetime
;; through chrono, which panics outside them.
(define chrono-jdn-range (cons (->jdn (date -262143 1 1)) (->jdn (date 262142 12 31))))

(define (printable? v)
  (<= (car chrono-jdn-range) (->jdn v) (cdr chrono-jdn-range)))

(define (utc-clock v)
  (if (moment? v) (->datetime/utc v) v))

(define (temporal-encoder who dtype)
  (define ((encoder accepts? what ->physical in-range?) v)
    (unless (accepts? v)
      (raise-arguments-error who (format "expected ~a for this dtype" what) "dtype" dtype "value" v))
    (define physical (->physical v))
    (unless (in-range? v physical)
      (raise-arguments-error who "value out of range for this dtype" "dtype" dtype "value" v))
    physical)
  (match dtype
    ['date (encoder date? "a gregor date" date->days (lambda (d _) (printable? d)))]
    ['time (encoder time? "a gregor time" time->nanoseconds (lambda (_t _ns) #t))]
    [(or 'datetime (list* 'datetime _))
     (define unit (if (pair? dtype) (cadr dtype) 'microseconds))
     (encoder datetime-like? "a gregor datetime or moment"
              (lambda (dt) (floor-nanoseconds->unit (datetime->nanoseconds dt) unit))
              (lambda (dt ticks) (and (printable? (utc-clock dt)) (int64? ticks))))]
    [(list* 'duration unit _)
     (encoder fixed-length-period? "a gregor period without years or months"
              (lambda (p) (truncate-nanoseconds->unit (period->nanoseconds p) unit))
              (lambda (_p ticks) (int64? ticks)))]))

(module+ test
  (require rackunit
           (only-in gregor
                    ->datetime/local ->utc-offset date datetime moment moment->iso8601/tzid
                    posix->moment)
           (only-in gregor/period days hours milliseconds months nanoseconds period weeks)
           (submod ".." gregor-private))

  (check-not-exn (lambda () (check-gregor-export 'gregor/private/moment-base 'make-moment)))
  (check-exn (regexp (string-append "^polars: gregor/private/moment-base no longer provides"
                                    " make-instant, .*/issues/172$"))
             (lambda () (check-gregor-export 'gregor/private/moment-base 'make-instant)))
  (check-exn #rx"^polars: gregor/private/moment-bass no longer provides make-moment, "
             (lambda () (check-gregor-export 'gregor/private/moment-bass 'make-moment)))

  (for ([days (list 0 -1 19724 -719528 2932896)])
    (check-equal? ((temporal-encoder 'test 'date) (days->date days)) days))
  (for ([ns (list 0 1 86399999999999 11045123456789)])
    (check-equal? ((temporal-encoder 'test 'time) (nanoseconds->time ns)) ns))
  (for* ([unit '(milliseconds microseconds nanoseconds)]
         [value (list* 0 -1 1 -1500 1500 1356998400123
                       (if (eq? unit 'nanoseconds) (list (- (expt 2 63)) (sub1 (expt 2 63))) '()))])
    (define encode (temporal-encoder 'test (list 'datetime unit #f)))
    (check-equal? (encode (epoch->datetime unit value)) value))
  (check-equal? (epoch->datetime 'milliseconds -1)
                (datetime 1969 12 31 23 59 59 999000000))
  (check-equal? (epoch->datetime 'nanoseconds 1500) (datetime 1970 1 1 0 0 0 1500))

  (define pre-epoch (datetime 1969 12 31 23 59 59 999500000))
  (check-equal? ((temporal-encoder 'test '(datetime milliseconds #f)) pre-epoch) -1)
  (check-equal? ((temporal-encoder 'test '(datetime microseconds #f)) pre-epoch) -500)
  (check-equal? ((temporal-encoder 'test 'datetime) (datetime 1970 1 1 0 0 1)) 1000000)

  (check-equal? ((temporal-encoder 'test '(duration milliseconds))
                 (period (weeks 1) (days 1) (hours 1) (milliseconds 5)))
                (+ (* 8 86400000) 3600000 5))
  (check-equal? ((temporal-encoder 'test '(duration microseconds)) (nanoseconds -1500)) -1)
  (check-equal? ((temporal-encoder 'test '(duration milliseconds)) (nanoseconds 1999999)) 1)

  (check-equal? (temporal-value-dtype (date 2024 1 2)) 'date)
  (check-equal? (temporal-value-dtype (nanoseconds->time 5)) 'time)
  (check-equal? (temporal-value-dtype (datetime 2024 1 2 3 4 5 6000))
                '(datetime microseconds #f))
  (check-equal? (temporal-value-dtype (datetime 2024 1 2 3 4 5 6001))
                '(datetime nanoseconds #f))
  (check-equal? (temporal-value-dtype (hours 1)) '(duration microseconds))
  (check-equal? (temporal-value-dtype (nanoseconds 1)) '(duration nanoseconds))
  (check-false (temporal-value-dtype (months 1)))
  (check-equal? (temporal-value-dtype (moment 2024 1 2 #:tz "UTC")) '(datetime microseconds "UTC"))
  (check-equal? (temporal-value-dtype (moment 2024 1 2 0 0 0 1 #:tz "Europe/Brussels"))
                '(datetime nanoseconds "Europe/Brussels"))
  (check-equal? (temporal-value-dtype (moment 2024 1 2 #:tz 3600)) '(datetime microseconds "UTC"))
  (check-equal? (temporal-value-dtype (moment 2024 1 2 #:tz "Etc/GMT-1"))
                '(datetime microseconds "Etc/GMT-1"))
  (define brussels (moment 2021 3 27 #:tz "Europe/Brussels"))
  (define kathmandu (moment 2021 3 27 #:tz "Asia/Kathmandu"))
  (define one-hour-east (moment 2021 3 27 #:tz 3600))
  (for ([vals (list (list brussels kathmandu) (list brussels one-hour-east)
                    (list brussels (datetime 2021 3 27)))]
        [zone (list "Europe/Brussels" "Europe/Brussels" "Europe/Brussels")])
    (check-equal? (temporal-values-dtype vals) (list 'datetime 'microseconds zone)))
  (check-equal? (temporal-values-dtype (list one-hour-east brussels))
                '(datetime microseconds "UTC"))
  (check-equal? (temporal-values-dtype (list (datetime 2021 3 27) brussels))
                '(datetime microseconds #f))
  (check-false (temporal-values-dtype (list brussels (date 2021 3 27))))
  (define instant (* 1616799600 1000000))
  (for ([dtype (list '(datetime microseconds "Europe/Brussels") '(datetime microseconds "UTC")
                     '(datetime microseconds #f))])
    (define encode (temporal-encoder 'test dtype))
    (for ([v (list brussels (moment 2021 3 27 4 45 #:tz "Asia/Kathmandu")
                   (moment 2021 3 27 #:tz 3600) (datetime 2021 3 26 23))])
      (check-equal? (encode v) instant)))
  (check-equal? ((temporal-encoder 'test '(datetime nanoseconds "UTC"))
                 (moment 1969 12 31 23 59 59 999999999 #:tz "UTC"))
                -1)
  (check-equal? ((temporal-encoder 'test '(datetime milliseconds "UTC"))
                 (moment 1969 12 31 23 59 59 999999999 #:tz "UTC"))
                -1)
  (for* ([unit '(milliseconds microseconds nanoseconds)]
         [zone '("Europe/Brussels" "America/New_York" "Asia/Kathmandu" "UTC")]
         [utc (list (datetime 2021 3 28 0 59 59 999000000) (datetime 2021 3 28 1)
                    (datetime 2021 10 31 0 30) (datetime 2021 10 31 1 30)
                    (datetime 2021 3 14 6 59 59) (datetime 2021 3 14 7)
                    (datetime 2021 11 7 5 30) (datetime 2021 11 7 6 30)
                    (datetime 1969 12 31 23 59 59 999000000))])
    (define naive (temporal-encoder 'test (list 'datetime unit #f)))
    (define wall-clock (temporal-encoder 'test (list 'datetime (offset-unit unit) #f)))
    (define value (naive utc))
    (define gregor-reading (posix->moment (->posix utc) zone))
    (define m (epoch->moment unit value (wall-clock (->datetime/local gregor-reading)) zone))
    (check-equal? m gregor-reading)
    (check-equal? (->tzid m) zone)
    (check-equal? (->datetime/utc m) utc)
    (check-equal? ((temporal-encoder 'test (list 'datetime unit zone)) m) value))
  (check-equal? (->nanoseconds (epoch->moment 'nanoseconds 1616799600123456789
                                              1616803200123456 "Europe/Brussels"))
                123456789)
  (check-equal? (map offset-unit '(nanoseconds microseconds milliseconds))
                '(microseconds microseconds milliseconds))
  (check-equal? (utc-offset 'nanoseconds -1 -1) 0)
  (check-equal? (utc-offset 'nanoseconds -1001 (- 3600000000 2)) 3600)
  (check-equal? (utc-offset 'milliseconds -1 (- 20700000 1)) 20700)
  ;; a nanosecond wall clock past either end of i64, read from its microseconds
  (define east (+ (* (->posix (datetime 2262 4 11 23)) ns/second) 1))
  (define west (+ (- (sub1 (expt 2 63))) 3600000000000))
  (for ([value (list east west)]
        [offset '(32400 -17762)]
        [zone '("Asia/Tokyo" "America/New_York")]
        [wall (list (datetime 2262 4 12 8 0 0 1) (datetime 1677 9 20 20 16 41 145224193))])
    (check-false (int64? (+ value (* offset ns/second))))
    (define m (epoch->moment 'nanoseconds value
                             (+ (floor (/ value 1000)) (* offset 1000000)) zone))
    (check-equal? (->datetime/local m) wall)
    (check-equal? (->utc-offset m) offset)
    (check-equal? (->tzid m) zone)
    (check-equal? ((temporal-encoder 'test (list 'datetime 'nanoseconds zone)) m) value))
  (check-equal? (moment->iso8601/tzid (epoch->moment 'microseconds instant
                                                     (+ instant 3600000000) "Europe/Brussels"))
                "2021-03-27T00:00:00+01:00[Europe/Brussels]")
  (define elsewhere (epoch->moment 'milliseconds 0 -20476000 "Nowhere/Known"))
  (check-equal? (moment->iso8601/tzid elsewhere) "1969-12-31T18:18:44-05:41[Nowhere/Known]")
  (check-equal? (->posix elsewhere) 0)
  (check-false (temporal-value-dtype "2024-01-02"))
  (check-equal? (temporal-values-dtype (list (date 2024 1 2) (date 2024 1 3))) 'date)
  (check-equal? (temporal-values-dtype (list (datetime 2024) (datetime 2024 1 1 0 0 0 1)))
                '(datetime nanoseconds #f))
  (check-equal? (temporal-values-dtype (list (hours 1) (nanoseconds 1)))
                '(duration nanoseconds))
  (define ns-min (epoch->datetime 'nanoseconds (- (expt 2 63))))
  (define ns-max (epoch->datetime 'nanoseconds (sub1 (expt 2 63))))
  (check-equal? ns-min (datetime 1677 9 21 0 12 43 145224192))
  (check-equal? ns-max (datetime 2262 4 11 23 47 16 854775807))
  (for ([edge (list ns-min ns-max)])
    (check-equal? (temporal-value-dtype edge) '(datetime nanoseconds #f)))
  (for ([past (list (epoch->datetime 'nanoseconds (sub1 (- (expt 2 63))))
                    (epoch->datetime 'nanoseconds (expt 2 63))
                    (datetime 1600 1 1 0 0 0 1))])
    (check-equal? (temporal-value-dtype past) '(datetime microseconds #f)))
  (check-equal? (temporal-values-dtype (list (datetime 2024 1 1 0 0 0 1) ns-max))
                '(datetime nanoseconds #f))
  (check-equal? (temporal-values-dtype (list (datetime 2024 1 1 0 0 0 1) (datetime 1600 1 1)))
                '(datetime microseconds #f))
  (check-equal? (temporal-value-dtype (nanoseconds (sub1 (expt 2 63)))) '(duration nanoseconds))
  (check-equal? (temporal-value-dtype (nanoseconds (expt 2 63))) '(duration microseconds))
  (check-equal? (temporal-value-dtype (period (weeks 20000) (nanoseconds 1)))
                '(duration microseconds))
  (check-equal? (temporal-values-dtype (list (nanoseconds 1) (weeks 20000)))
                '(duration microseconds))
  (check-equal? ((temporal-encoder 'test '(datetime microseconds #f)) (datetime 1600 1 1 0 0 0 999))
                ((temporal-encoder 'test '(datetime microseconds #f)) (datetime 1600 1 1)))
  (check-false (temporal-values-dtype (list (date 2024 1 2) (datetime 2024))))
  (check-false (temporal-values-dtype (list (date 2024 1 2) 5)))
  (check-false (temporal-values-dtype '()))

  (check-exn #rx"^test: expected a gregor date for this dtype\n  dtype: 'date\n  value: 5$"
             (lambda () ((temporal-encoder 'test 'date) 5)))
  (check-exn #rx"^test: expected a gregor date for this dtype\n  dtype: 'date\n  value: #<moment"
             (lambda () ((temporal-encoder 'test 'date) (moment 2024 1 2 #:tz "UTC"))))
  (check-exn #rx"^test: expected a gregor datetime or moment for this dtype"
             (lambda () ((temporal-encoder 'test '(datetime microseconds "UTC")) (date 2024 1 2))))
  (check-exn #rx"^test: value out of range for this dtype\n  dtype: '\\(datetime nanoseconds \"UTC\"\\)"
             (lambda () ((temporal-encoder 'test '(datetime nanoseconds "UTC"))
                         (moment 1500 #:tz "UTC"))))
  (check-exn #rx"^test: expected a gregor period without years or months"
             (lambda () ((temporal-encoder 'test '(duration microseconds)) (months 1))))
  (check-exn #rx"^test: value out of range for this dtype\n  dtype: 'date"
             (lambda () ((temporal-encoder 'test 'date) (date 6000000 1 1))))
  (for ([edge (list (date 262142 12 31) (date -262143 1 1))])
    (check-equal? (days->date ((temporal-encoder 'test 'date) edge)) edge))
  (check-exn #rx"^test: value out of range for this dtype\n  dtype: 'date"
             (lambda () ((temporal-encoder 'test 'date) (date 262143 1 1))))
  (check-exn #rx"^test: value out of range for this dtype\n  dtype: 'date"
             (lambda () ((temporal-encoder 'test 'date) (date -262144 12 31))))
  (check-exn #rx"^test: value out of range for this dtype\n  dtype: '\\(datetime milliseconds #f\\)"
             (lambda () ((temporal-encoder 'test '(datetime milliseconds #f)) (datetime 270000))))
  (check-exn #rx"^test: value out of range for this dtype\n  dtype: '\\(datetime nanoseconds #f\\)"
             (lambda () ((temporal-encoder 'test '(datetime nanoseconds #f)) (datetime 1500)))))
