#lang racket/base

;; Datetimes read back with their full precision.
;;
;; `ref` and every conversion (series->list, series->vector, in-series,
;; dataframe->columns, dataframe->hash) return a millisecond, microsecond or
;; nanosecond datetime as the gregor datetime of exactly that instant, before
;; the epoch too. Python's to_list stops at the microsecond; gregor keeps the
;; nanoseconds.
;;
;; Inside `nix develop`:
;;   racket examples/64-temporal-subsecond-precision.rkt

(require polars)

(define ticks (series '(1500 -1) #:name "ticks" #:dtype 'i64))

(define frame
  (dataframe (for/list ([unit '(milliseconds microseconds nanoseconds)])
               (rename (cast ticks (list 'datetime unit)) (symbol->string unit)))))
(displayln frame)

(for ([name (column-names frame)])
  (define s (ref frame name))
  (printf "~a: ref ~s, list ~s\n" name (ref s 0) (series->list s)))

(printf "vector: ~s\n" (series->vector (ref frame "milliseconds")))
(printf "in-series: ~s\n" (for/list ([dt (in-series (ref frame "microseconds"))]) dt))
(printf "columns: ~s\n" (dataframe->columns frame #:columns '("nanoseconds")))
(printf "round trip: ~s\n"
        (let ([s (ref frame "nanoseconds")])
          (equal? (series->list (series (series->list s) #:dtype (dtype s)))
                  (series->list s))))
