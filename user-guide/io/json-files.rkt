#lang racket/base

;; rkt-polars user guide — IO: JSON files
;; Mirrors https://docs.pola.rs/user-guide/io/json/ and json_files.py; the reading
;; options below extend the upstream page.
;;
;; Inside `nix develop`:
;;   racket user-guide/io/json-files.rkt

(require racket/file
         racket/runtime-path
         polars)

(define-runtime-path data-dir "../../polars/scribblings/data")
(define stations (build-path data-dir "stations.json"))

;; --- read ------------------------------------------------------------------
(displayln (read-json stations))

;; --- write -----------------------------------------------------------------
(define path (build-path (find-system-path 'temp-dir) "polars-guide-path.json"))
(define df
  (dataframe (list (series '(1 2 3) #:name "foo")
                   (series (list polars-null "bak" "baz") #:name "bar"))))
(write-json df path)
(displayln (file->string path))
(displayln (read-json path))
(delete-file path)

;; --- reading options ---------------------------------------------------------
(displayln (read-json stations
                      #:schema '(("day" . date) ("station" . categorical) ("reading" . f32))))
(displayln (~> (read-json stations #:schema-overrides '(("day" . date)))
               (select "day" "reading")))

(displayln (with-handlers ([exn:fail? exn-message])
             (read-json stations #:infer-schema-length 1)))
(displayln (shape (read-json stations #:infer-schema-length #f)))

;; API gaps: a path only, no file object or in-memory string in or out; an
;; Enum in #:schema, read as 'categorical and cast instead.
