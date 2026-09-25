#lang racket/base

;; rkt-polars user guide — Interoperability: Numeric buffers.
;; Mirrors Series.to_numpy / DataFrame.to_numpy, the NumPy side of
;; https://docs.pola.rs/user-guide/misc/arrow/, and numeric_buffers.py.
;;
;; Inside `nix develop`:
;;   racket user-guide/interop/numeric-buffers.rkt

(require ffi/vector
         polars)

(define df
  (dataframe (list (series '(1 2 3) #:name "foo")
                   (series '("ham" "spam" "jam") #:name "bar"))))
(define gappy (series (list 1 polars-null 3) #:name "value"))

;; --- a series as an f64vector (to_numpy) ---------------------------------
(writeln (~> df (ref "foo") series->f64vector f64vector->list))
(writeln (f64vector->list (series->f64vector gappy)))
(writeln (f64vector->list (series->f64vector gappy #:null -1)))
(writeln (with-handlers ([exn:fail:contract? exn-message])
           (series->f64vector gappy #:null 'error)))

;; --- a dataframe as one buffer (DataFrame.to_numpy) ----------------------
(define xy
  (dataframe (list (series (list 1 2 polars-null) #:name "a")
                   (series '(0.5 1.5 2.5) #:name "b"))))

(define-values (m nrows ncols) (dataframe->f64vector xy))
(writeln (list nrows ncols (f64vector->list m)))

(define-values (m/c _nrows _ncols) (dataframe->f64vector xy #:order 'c))
(writeln (f64vector->list m/c))

(define-values (b _rows _cols) (dataframe->f64vector xy #:columns '("b") #:null 'error))
(writeln (f64vector->list b))

(writeln (with-handlers ([exn:fail:contract? exn-message])
           (dataframe->f64vector xy #:null 'error)))
;; API gap: string and temporal columns are refused, where to_numpy builds an
;; object or datetime64 array; no Arrow export (to_arrow).
(writeln (with-handlers ([exn:fail:contract? exn-message])
           (dataframe->f64vector df)))
