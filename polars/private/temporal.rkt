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
         period->nanoseconds
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

(module+ internal
  (provide int64? ns/second))
