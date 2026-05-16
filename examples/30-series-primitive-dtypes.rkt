#lang racket/base

;; Primitive scalar dtype coverage: int8/int16/uint8/uint16/float32.
;;
;; Inside `nix develop`:
;;   racket examples/30-series-primitive-dtypes.rkt

(require polars)

(define df
  (dataframe-new
   (list (series-new-i8 "i8s" (list -8 polars-null 12))
         (series-new-i16 "i16s" (list -300 polars-null 1200))
         (series-new-u8 "u8s" (list 0 polars-null 255))
         (series-new-u16 "u16s" (list 0 polars-null 65535))
         (series-new-f32 "f32s" (list 1.5 polars-null 2.25)))))

(display-dataframe df)

(displayln
 (list 'i8
       (series-dtype (dataframe-column df "i8s"))
       (series-ref (dataframe-column df "i8s") 0)
       (series-sum-i8 (dataframe-column df "i8s"))
       (series-mean-i8 (dataframe-column df "i8s"))))

(displayln
 (list 'f32
       (series-dtype (dataframe-column df "f32s"))
       (series-ref (dataframe-column df "f32s") 0)
       (series-sum-f32 (dataframe-column df "f32s"))))
