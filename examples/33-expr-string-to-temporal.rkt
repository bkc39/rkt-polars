#lang racket/base

;; Expr string-to-temporal parsing: Date, Datetime, and Time.
;;
;; str-to-date / str-to-datetime / str-to-time parse strings to temporal
;; columns; #:strict #f turns unparseable values into null instead of raising.
;;
;; Inside `nix develop`:
;;   racket examples/33-expr-string-to-temporal.rkt

(require polars)

(define df
  (dataframe
   (list (series '("2024-01-02" "not-a-date" "2024-05-09 extra") #:name "date_s")
         (series '("2024-01-02 03:04:05" "bad" "2024-05-09 12:30:45") #:name "dt_s")
         (series '("03:04:05.123456789" "bad" "12:30:45") #:name "time_s"))))

(define out
  (~> df
      (with-columns
        (alias (str-to-date "date_s" #:strict #f) "date_infer")
        (alias (str-to-date "date_s" #:format "%Y-%m-%d" #:strict #f #:exact #f)
               "date_embedded")
        (alias (str-to-datetime "dt_s" #:format "%Y-%m-%d %H:%M:%S"
                                #:unit 'milliseconds #:strict #f)
               "parsed_dt")
        (alias (str-to-time "time_s" #:format "%H:%M:%S%.f" #:strict #f)
               "parsed_time"))))

(displayln out)
