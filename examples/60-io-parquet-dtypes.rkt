#lang racket/base

;; Categorical, Enum and Decimal columns through Parquet.
;;
;; produce.parquet was written by Python Polars with a Categorical, an Enum
;; and a Decimal column; read-parquet keeps all three dtypes. A frame with
;; categorical and Enum columns written from Racket reads back the same.
;;
;; Inside `nix develop`:
;;   racket examples/60-io-parquet-dtypes.rkt

(require racket/file
         racket/runtime-path
         polars)

(define-runtime-path produce-parquet "../polars/scribblings/data/produce.parquet")

(define produce (read-parquet produce-parquet))
(displayln produce)
(for ([name (column-names produce)])
  (printf "~a: ~s ~s\n" name (dtype (ref produce name)) (series->list (ref produce name))))

(define-enum grade-levels low mid high)
(define grades
  (dataframe (list (series '(apple fig apple) #:name "item")
                   (series '(low high mid) #:name "grade" #:dtype grade-levels))))
(define path (make-temporary-file "rkt-polars-grades-~a.parquet"))
(write-parquet grades path)
(define back (read-parquet path))
(delete-file path)
(printf "round trip: ~s\n"
        (for/list ([name (column-names back)])
          (list name (dtype (ref back name)) (series->list (ref back name)))))
