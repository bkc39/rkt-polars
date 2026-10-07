#lang racket/base

;; JSON arrays: read-json and write-json.
;;
;; write-json writes a frame as one JSON array of objects, a row an object;
;; read-json reads one back. #:schema gives the columns and their types,
;; #:schema-overrides retypes some of the inferred ones, and
;; #:infer-schema-length sets how many objects inference reads.
;;
;; Inside `nix develop`:
;;   racket examples/72-io-json.rkt

(require racket/file
         racket/runtime-path
         polars)

(define-runtime-path stations "../polars/scribblings/data/stations.json")

(define readings
  (dataframe (list (series '("north" "south" "north") #:name "station")
                   (series (list 3.5 polars-null 2.25) #:name "reading"))))
(define path (make-temporary-file "rkt-polars-readings-~a.json"))
(write-json readings path)
(printf "written: ~a\n" (file->string path))
(displayln (read-json path))
(delete-file path)

(define typed
  (read-json stations
             #:schema '(("day" . date) ("station" . categorical) ("reading" . f32))))
(displayln typed)
(printf "schema dtypes: ~s\n" (for/list ([name (column-names typed)]) (dtype (ref typed name))))

(define overridden (read-json stations #:schema-overrides '(("day" . date))))
(printf "override dtypes: ~s\n"
        (for/list ([name (column-names overridden)]) (dtype (ref overridden name))))

(printf "one object: ~a\n"
        (with-handlers ([exn:fail? exn-message])
          (read-json stations #:infer-schema-length 1)))
(printf "every object: ~s\n" (shape (read-json stations #:infer-schema-length #f)))
