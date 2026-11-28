#lang racket/base

;; Primitive scalar dtype coverage: int8/int16/uint8/uint16/float32.
;;
;; series #:dtype builds each narrow numeric width; dtype / ref / sum / mean
;; then dispatch on it.
;;
;; Inside `nix develop`:
;;   racket examples/30-series-primitive-dtypes.rkt

(require polars)

(define df
  (dataframe [i8s (list -8 polars-null 12) #:dtype 'i8]
             [i16s (list -300 polars-null 1200) #:dtype 'i16]
             [u8s (list 0 polars-null 255) #:dtype 'u8]
             [u16s (list 0 polars-null 65535) #:dtype 'u16]
             [f32s (list 1.5 polars-null 2.25) #:dtype 'f32]))

(displayln df)

(displayln
 (list 'i8
       (dtype (ref df "i8s"))
       (ref (ref df "i8s") 0)
       (sum (ref df "i8s"))
       (mean (ref df "i8s"))))

(displayln
 (list 'f32
       (dtype (ref df "f32s"))
       (ref (ref df "f32s") 0)
       (sum (ref df "f32s"))))
