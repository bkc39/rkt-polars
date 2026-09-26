#lang racket/base

;; A dataframe to Racket data: dataframe->hash and dataframe->columns (Polars'
;; to_dict(as_series=False)), in-dataframe-columns (Polars' iter_columns) and
;; dataframe->f64vector (Polars' to_numpy).
;;
;; dataframe->f64vector copies the selected numeric columns into one
;; f64vector, column-major ('fortran, the default) or row-major ('c), and
;; returns it with its row and column counts. #:null is a fill value or
;; 'error.
;;
;; Inside `nix develop`:
;;   racket examples/51-dataframe-to-racket.rkt

(require ffi/vector
         polars)

(define df
  (dataframe (list (series '("x" "y" "z") #:name "id")
                   (series (list 1 2 polars-null) #:name "a")
                   (series '(0.5 1.5 2.5) #:name "b"))))

;; --- columns as a hash or an association list ----------------------------
(writeln (dataframe->hash df))
(writeln (hash-ref (dataframe->hash df #:null 0) "a"))
(writeln (dataframe->columns df))
(writeln (dataframe->columns df #:columns '("b" "id") #:null 0))

;; --- columns as series, one at a time ------------------------------------
(for ([column (in-dataframe-columns df #:columns '("id" "b"))])
  (printf "~a: ~s\n" (series-name column) (series->list column)))

;; --- numeric columns as one buffer ---------------------------------------
(define (show label m nrows ncols)
  (printf "~a (~a x ~a): ~a\n" label nrows ncols (f64vector->list m)))

(define-values (m nrows ncols) (dataframe->f64vector df #:columns '("a" "b")))
(show "fortran" m nrows ncols)

(define-values (m/c rows/c cols/c)
  (dataframe->f64vector df #:columns '("a" "b") #:order 'c))
(show "c      " m/c rows/c cols/c)

;; element (i, j): (+ (* j nrows) i) in 'fortran, (+ (* i ncols) j) in 'c
(writeln (list (f64vector-ref m (+ (* 1 nrows) 2))
               (f64vector-ref m/c (+ (* 2 cols/c) 1))))

;; null modes: a fill value, or 'error naming the column and row
(define-values (zeros z-rows z-cols)
  (dataframe->f64vector df #:columns '("a" "b") #:order 'fortran #:null 0))
(show "#:null 0" zeros z-rows z-cols)
(displayln
 (with-handlers ([exn:fail:contract? exn-message])
   (dataframe->f64vector df #:columns '("a" "b") #:null 'error)))
(define-values (b b-rows b-cols) (dataframe->f64vector df #:columns '("b") #:null 'error))
(show "b only " b b-rows b-cols)

;; a non-numeric column is refused before anything is copied
(displayln
 (with-handlers ([exn:fail:contract? exn-message])
   (dataframe->f64vector df)))
