#lang racket/base

;; Enum columns.
;;
;; (define-enum name cat ...) declares the categories, in order, up front. The
;; values read back as symbols, sorting and comparing follow the declared
;; order, and a value outside the categories is an error: building the series,
;; casting to it, or comparing with it.
;;
;; Inside `nix develop`:
;;   racket examples/59-dtypes-enum.rkt

(require polars)

(define (report thunk)
  (with-handlers ([exn:fail? (lambda (e) (displayln (exn-message e)))])
    (thunk)))

(define-enum log-levels debug info warning error)

(define logs
  (dataframe
   (list (series '(debug info debug error) #:name "level" #:dtype log-levels)
         (series '("process id: 525" "Service started correctly"
                   "startup time: 67ms" "Cannot connect to DB!")
                 #:name "message"))))

(printf "dtype: ~s\n" (dtype (ref logs "level")))
(printf "levels: ~s\n" (series->list (ref logs "level")))
(displayln (sort logs "level"))
(displayln (filter logs (> (col "level") 'debug)))

(printf "cast from strings: ~s\n"
        (series->list (cast (series '("warning" "info")) log-levels)))
(printf "select by the Enum: ~s\n" (column-names (select logs (col log-levels))))

(report (lambda () (series '(info fatal) #:dtype log-levels)))
(report (lambda () (cast (series '("info" "fatal")) log-levels)))
(report (lambda () (select logs (> (col "level") 'fatal))))
