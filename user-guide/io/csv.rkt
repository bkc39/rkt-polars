#lang racket/base

;; rkt-polars user guide — IO: CSV
;; Mirrors https://docs.pola.rs/user-guide/io/csv/ and csv.py; the reading
;; options below extend the upstream page.
;;
;; Inside `nix develop`:
;;   racket user-guide/io/csv.rkt

(require racket/runtime-path
         (only-in racket/file file->string)
         polars)

(define-runtime-path data-dir "../../polars/scribblings/data")
(define (data name) (build-path data-dir name))

;; --- read & write ----------------------------------------------------------
(define path (build-path (find-system-path 'temp-dir) "polars-guide-path.csv"))
(define df
  (dataframe (list (series '(1 2 3) #:name "foo")
                   (series (list polars-null "bak" "baz") #:name "bar"))))
(write-csv df path)
(displayln (read-csv path))

;; --- scan --------------------------------------------------------------------
(displayln (collect (scan-csv path)))
(delete-file path)

;; --- reading options ---------------------------------------------------------
(define flights-tsv (data "flights.tsv"))

;; Stricter than Python, whose read_csv returns the header line as one column:
;; without #:separator, read-csv raises and names the separator to pass.
(displayln (with-handlers ([exn:fail? exn-message]) (read-csv flights-tsv)))
(displayln (shape (read-csv flights-tsv #:separator #\,)))

(displayln (with-handlers ([exn:fail? exn-message])
             (read-csv flights-tsv #:separator #\tab)))
(define flights (read-csv flights-tsv #:separator #\tab #:null-values "NA"))
(displayln (~> flights (select "dep_delay" "arr_delay") (tail 3)))
(displayln (~> (read-csv flights-tsv #:separator #\tab #:null-values '("NA" "-"))
               (ref #:columns "air_time")
               null-count))

(displayln (~> (read-csv flights-tsv #:separator #\tab #:null-values "NA"
                         #:schema-overrides '(("dep_delay" . f64) ("flight" . int32)))
               (select "dep_delay" "flight")
               (tail 2)))
(displayln (~> (read-csv flights-tsv #:separator #\tab #:infer-schema-length #f)
               (ref #:columns "dep_delay")
               dtype))
(displayln (~> (read-csv flights-tsv #:separator #\tab #:ignore-errors #t)
               (ref #:columns "dep_delay")
               null-count))
(displayln (~> (read-csv flights-tsv #:separator #\tab #:null-values "NA"
                         #:try-parse-dates #t)
               (select "time_hour")
               (head 2)))

(displayln (read-csv (data "notes.csv")
                     #:separator #\; #:comment-prefix "#" #:quote-char #\'))
(displayln (read-csv (data "latin1.csv") #:encoding 'utf8-lossy))
(displayln (read-csv (data "parts/part-1.csv") #:has-header #f #:skip-rows 1 #:n-rows 1))

(displayln (read-csv flights-tsv #:separator #\tab #:null-values "NA"
                     #:columns '("carrier" "flight" "dep_delay")
                     #:row-index-name "row" #:n-rows 3))
(displayln (read-csv (data "parts/part-1.csv") #:has-header #f #:skip-rows 1
                     #:new-columns '("from" "to" "delay")))

(define stations
  (read-csv (data "stations.csv") #:skip-lines 1 #:separator #\; #:decimal-comma #t
            #:null-values '(("temp" . "-") ("rain" . "n/a"))
            #:truncate-ragged-lines #t #:try-parse-dates #t))
(displayln stations)

;; API gaps: no compressed input yet (gzip, zlib, zstd; #176); no schema,
;; with_column_names, include_file_paths or missing_columns (#193); no
;; spelling for the tuning knobs (n_threads, low_memory, rechunk, batch_size)
;; or for use_pyarrow and the encodings Python decodes itself. Polars decides
;; from a file's first four bytes whether it is compressed, as in Python: a
;; plain file that starts like a zlib stream (a header beginning x^) is taken
;; for compressed data; a UTF-8 byte order mark at the start avoids it.

;; --- writing options ---------------------------------------------------------
(write-csv stations path #:separator #\; #:decimal-comma #t #:null-value "-"
           #:date-format "%d.%m.%Y" #:time-format "%H:%M")
(display (file->string path))
(write-csv (select stations "station" "temp") path
           #:quote-style 'non-numeric #:float-precision 2)
(display (file->string path))
(delete-file path)

;; API gap: no compressed output (compression), which Python writes through
;; sink_csv (#184).
