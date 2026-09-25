#lang racket/base

;; CSV types: #:schema-overrides and #:infer-schema-length.
;;
;; #:schema-overrides fixes named columns' types, as an association list of
;; name -> dtype in any spelling `series #:dtype` accepts ('i32 or 'int32,
;; 'f64 or 'float64, 'datetime or '(datetime milliseconds)); the other
;; columns are still inferred. #:infer-schema-length sets how many rows
;; inference reads: the default 100, #f for every row, 0 for strings
;; throughout. An override naming a column the file lacks is an error rather
;; than a silent rename.
;;
;; Inside `nix develop`:
;;   racket examples/41-csv-schema.rkt

(require racket/file
         racket/runtime-path
         polars)

(define-runtime-path flights-tsv "../polars/scribblings/data/flights.tsv")

(define (report thunk)
  (with-handlers ([exn:fail? (lambda (e) (displayln (exn-message e)))])
    (thunk)))

(define (dtypes df)
  (for/list ([name (column-names df)])
    (list name (dtype (ref df #:columns name)))))

(define short
  (read-csv flights-tsv #:separator #\tab #:null-values "NA"
            #:schema-overrides '(("dep_delay" . f64) ("flight" . i32)
                                 ("time_hour" . datetime))))
(define canonical
  (read-csv flights-tsv #:separator #\tab #:null-values "NA"
            #:schema-overrides '(("dep_delay" . float64) ("flight" . int32)
                                 ("time_hour" . (datetime microseconds)))))
(displayln "short spellings:")
(displayln (~> short (select "dep_delay" "flight" "time_hour") (head 3)))
(printf "same dtypes with canonical spellings: ~a\n"
        (equal? (dtypes short) (dtypes canonical)))
(displayln (~> (read-csv flights-tsv #:separator #\tab #:null-values "NA"
                         #:schema-overrides '(("time_hour" . (datetime milliseconds))))
               (ref #:columns "time_hour")
               dtype))
(newline)

(displayln "an override for a column the file lacks:")
(report (lambda ()
          (read-csv flights-tsv #:separator #\tab
                    #:schema-overrides '(("dep_dealy" . f64)))))
(newline)

(define late (make-temporary-file "rkt-polars-schema-~a.csv"))
(display-lines-to-file (append '("x")
                               (for/list ([i (in-range 150)]) (number->string i))
                               '("150.5"))
                       late #:exists 'replace)

(displayln "a float after row 100, default #:infer-schema-length 100:")
(report (lambda () (read-csv late)))
(printf "#:infer-schema-length #f reads every row: ~a\n"
        (dtype (ref (read-csv late #:infer-schema-length #f) #:columns "x")))
(printf "#:infer-schema-length 0 reads strings:   ~a\n"
        (dtype (ref (read-csv late #:infer-schema-length 0) #:columns "x")))
(printf "or override the one column:              ~a\n"
        (dtype (ref (read-csv late #:schema-overrides '(("x" . f64))) #:columns "x")))
(delete-file late)
