#lang racket/base

;; rkt-polars user guide — Series & DataFrames
;; Mirrors https://docs.pola.rs/user-guide/getting-started/ (the "Series" and
;; "DataFrames" sections) and series_and_dataframes.py in this directory.
;;
;; Inside `nix develop`:
;;   racket user-guide/getting-started/series-and-dataframes.rkt

(require gregor
         polars)

;; --- Series -------------------------------------------------------------
;; The generic `series` constructor infers a dtype from the values, or takes
;; an explicit #:dtype.  Use polars-null for missing entries.
;; (#:dtype 'i64 to match Polars' default integer width in the .py version)
(define s (series '(1 2 3 4 5) #:name "a" #:dtype 'i64))

(displayln "a series:")
(displayln s)                           ; prints in Polars' format
(describe s)                            ; name, length, dtype, null count
(printf "sum=~a  min=~a  max=~a  mean=~a\n"
        (sum s) (min s) (max s) (mean s))
(newline)

;; --- DataFrames ---------------------------------------------------------
;; A DataFrame is a collection of named series of equal length.  gregor
;; datetimes map to Polars datetime columns.
(define df
  (dataframe-new
   (list (series (list (datetime 2025 1 1) (datetime 2025 1 2)
                       (datetime 2025 1 3) (datetime 2025 1 4))
                 #:name "date")
         (series '(1.0 2.0 3.0 4.0) #:name "float")
         (series '("a" "b" "c" "d") #:name "string"))))

(displayln "a dataframe:")
(display-dataframe df)
(newline)

;; --- Viewing data -------------------------------------------------------
(printf "shape = ~a\n"
        (call-with-values (lambda () (dataframe-shape df)) cons))

(displayln "head(3):")
(display-dataframe (dataframe-head df 3))
(newline)

(displayln "tail(2):")
(display-dataframe (dataframe-tail df 2))
(newline)

(displayln "describe (per-column dtypes):")
(describe df)                           ; dispatches on dataframe
(newline)

;; `ref` is the generic accessor: a column out of a dataframe, an element out
;; of a series.
(displayln "ref df \"float\" then element 0:")
(printf "df[\"float\"][0] = ~a\n" (ref (ref df "float") 0))
