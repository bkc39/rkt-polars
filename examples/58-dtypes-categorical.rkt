#lang racket/base

;; Categorical columns.
;;
;; (cast name 'categorical) stores each distinct string once and a code per
;; row. The values read back as symbols, by `ref` and by every conversion, and
;; a list of symbols builds a categorical series. Sorting and comparing go by
;; the strings; a symbol in an expression is the string of its name.
;;
;; Inside `nix develop`:
;;   racket examples/58-dtypes-categorical.rkt

(require polars)

(define flights
  (dataframe (list (series '("UA" "AA" "UA" "B6" "AA") #:name "carrier")
                   (series '("IAH" "MIA" "IAH" "JFK" "MIA") #:name "dest")
                   (series '(2 -4 11 0 7) #:name "dep_delay"))))

(define coded (with-columns flights (cast "carrier" 'categorical) (cast "dest" 'categorical)))

(for ([name '("carrier" "dest")])
  (printf "~a: ~s\n" name (dtype (ref coded name))))
(printf "row 0 of carrier: ~s\n" (ref (ref coded "carrier") 0))
(printf "dest as a list: ~s\n" (series->list (ref coded "dest")))
(printf "carriers, one at a time: ~s\n" (for/list ([c (ref coded "carrier")]) c))

(displayln (~> coded
               (group-by "carrier")
               (agg (alias (mean "dep_delay") "mean_delay"))
               (sort "carrier")))
(displayln (filter coded (= (col "carrier") 'UA)))
(displayln (filter coded (is-in "dest" '(JFK MIA))))

(printf "a list of symbols: ~s\n" (dtype (series '(EWR JFK EWR))))
(printf "select by dtype: ~s\n" (column-names (select coded (col 'categorical))))
