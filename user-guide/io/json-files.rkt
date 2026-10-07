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
(define stations-nd (build-path data-dir "stations.ndjson"))

;; --- read ------------------------------------------------------------------
(displayln (read-json stations))
(displayln (read-ndjson stations-nd))

;; --- write -----------------------------------------------------------------
(define dir (make-temporary-directory "polars-guide-~a"))
(define path (build-path dir "path.json"))
(define nd-path (build-path dir "path.ndjson"))
(define df
  (dataframe (list (series '(1 2 3) #:name "foo")
                   (series (list polars-null "bak" "baz") #:name "bar"))))
(write-json df path)
(displayln (file->string path))
(displayln (read-json path))
(write-ndjson df nd-path)
(displayln (file->string nd-path))
(displayln (read-ndjson nd-path))

;; --- scan --------------------------------------------------------------------
(displayln (scan-ndjson stations-nd))
(displayln (~> (scan-ndjson stations-nd)
               (filter (> (col "reading") 3))
               collect))

;; --- reading options ---------------------------------------------------------
(displayln (read-json stations
                      #:schema '(("day" . date) ("station" . categorical) ("reading" . f32))))
(displayln (~> (read-json stations #:schema-overrides '(("day" . date)))
               (select "day" "reading")))

(displayln (with-handlers ([exn:fail? exn-message])
             (read-json stations #:infer-schema-length 1)))
(displayln (shape (read-json stations #:infer-schema-length #f)))

(displayln (column-names (read-ndjson stations-nd #:infer-schema-length 2)))
(displayln (with-handlers ([exn:fail? exn-message])
             (read-ndjson stations-nd #:infer-schema-length 1)))
(displayln (~> (read-ndjson stations-nd #:infer-schema-length 1 #:ignore-errors #t)
               (select "station" "reading")))

(for ([i '(1 2 3)])
  (write-ndjson (read-csv (build-path data-dir "parts" (format "part-~a.csv" i)))
                (build-path dir (format "part-~a.ndjson" i))))
(displayln (read-ndjson (build-path dir "part-*.ndjson") #:n-rows 4 #:row-index-name "row"))
(delete-directory/files dir)

;; API gaps: a path only, no file object or in-memory string in or out; an
;; Enum in #:schema, read as 'categorical and cast instead. Compressed input
;; is recognised by its first bytes, not its name, as in Python.
