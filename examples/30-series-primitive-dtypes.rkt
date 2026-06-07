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
  (dataframe
   (list (series (list -8 polars-null 12)     #:name "i8s"  #:dtype 'i8)
         (series (list -300 polars-null 1200) #:name "i16s" #:dtype 'i16)
         (series (list 0 polars-null 255)     #:name "u8s"  #:dtype 'u8)
         (series (list 0 polars-null 65535)   #:name "u16s" #:dtype 'u16)
         (series (list 1.5 polars-null 2.25)  #:name "f32s" #:dtype 'f32))))

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
