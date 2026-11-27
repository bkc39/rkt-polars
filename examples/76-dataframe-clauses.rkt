#lang racket/base

;; dataframe: a frame from column clauses, as Python's dict of lists.
;;
;; [name values option ...] names a column by an identifier with no binding or
;; a string; [values #:name name option ...] by an expression. Any other
;; argument is a series or a list of series, spliced in. #:dtype casts a series
;; value, and the bare identifier is the procedure over series.
;;
;; Inside `nix develop`:
;;   racket examples/76-dataframe-clauses.rkt

(require gregor
         polars)

(define flights
  (dataframe [carrier '("UA" "AA" "UA")]
             [dep (in-range 3) #:dtype 'i32]))
(displayln flights)

(displayln
 (dataframe [(list (date 2026 1 1) (date 2026 6 1)) #:name 'date]
            ["height" '(1.56 1.77)]
            [|dep time| (vector 5 7)]))

(define carriers (series '("UA" "AA") #:name "c"))
(displayln (dataframe [carrier carriers #:dtype 'categorical] carriers))

(define columns (list carriers (series '(1 2) #:name "n")))
(displayln (dataframe columns))

(displayln (apply dataframe (for/list ([c (in-dataframe-columns flights)]) c)))

(printf "~a\n" (with-handlers ([exn:fail? exn-message])
                 (dataframe [a '(1 2)] [b '(3)])))
