#lang racket/base

(require (only-in gregor
                  ->hours ->jdn ->minutes ->nanoseconds ->posix ->seconds date date?
                  datetime? jdn->date moment? posix->datetime)
         (only-in gregor/period period? period-ref)
         (only-in gregor/time time time?)
         racket/match)

(provide days->date
         epoch->datetime
         nanoseconds->time
         reject-moment
         temporal-encoder
         temporal-value-dtype
         temporal-values-dtype)

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

(define (temporal-kind v)
  (cond
    [(date? v) 'date]
    [(time? v) 'time]
    [(datetime? v) 'datetime]
    [(fixed-length-period? v) 'duration]
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
          (list 'datetime (inferred-unit datetime-sub-microsecond? datetime->nanoseconds vals) #f)]
         [(duration)
          (list 'duration (inferred-unit period-sub-microsecond? period->nanoseconds vals))]
         [else kind])))

(define (temporal-value-dtype v)
  (temporal-values-dtype (list v)))

(define (reject-moment who v)
  (raise-arguments-error
   who
   (string-append "a moment carries a time zone, and time-zone-aware datetimes are not"
                  " supported; convert it with ->datetime/utc or ->datetime/local")
   "value" v))

(define (int64? n)
  (<= (- (expt 2 63)) n (sub1 (expt 2 63))))

;; chrono's NaiveDate::MIN and MAX: polars formats every date and datetime
;; through chrono, which panics outside them.
(define chrono-jdn-range (cons (->jdn (date -262143 1 1)) (->jdn (date 262142 12 31))))

(define (printable? v)
  (<= (car chrono-jdn-range) (->jdn v) (cdr chrono-jdn-range)))

(define (temporal-encoder who dtype)
  (define ((encoder accepts? what ->physical in-range?) v)
    (unless (accepts? v)
      (when (moment? v)
        (reject-moment who v))
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
     (encoder datetime? "a gregor datetime"
              (lambda (dt) (floor-nanoseconds->unit (datetime->nanoseconds dt) unit))
              (lambda (dt ticks) (and (printable? dt) (int64? ticks))))]
    [(list* 'duration unit _)
     (encoder fixed-length-period? "a gregor period without years or months"
              (lambda (p) (truncate-nanoseconds->unit (period->nanoseconds p) unit))
              (lambda (_p ticks) (int64? ticks)))]))

(module+ test
  (require rackunit
           (only-in gregor date datetime moment)
           (only-in gregor/period days hours milliseconds months nanoseconds period weeks))

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
  (check-false (temporal-value-dtype (moment 2024 1 2 #:tz "UTC")))
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
  (check-exn #rx"^test: a moment carries a time zone.*->datetime/utc"
             (lambda () ((temporal-encoder 'test 'datetime) (moment 2024 1 2 #:tz "UTC"))))
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
