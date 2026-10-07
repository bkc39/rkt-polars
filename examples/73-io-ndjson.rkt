#lang racket/base

;; Newline-delimited JSON: read-ndjson, scan-ndjson and write-ndjson.
;;
;; write-ndjson writes one object a line; read-ndjson reads a file, a glob
;; pattern or a directory, and scan-ndjson starts a lazy plan from one.
;; #:n-rows, #:row-index-name and #:include-file-paths frame the rows read,
;; and #:ignore-errors reads a value that does not parse as null.
;; #:compression gzips or zstd-compresses the file written.
;;
;; Inside `nix develop`:
;;   racket examples/73-io-ndjson.rkt

(require racket/file
         polars)

(define dir (make-temporary-directory "rkt-polars-ndjson-~a"))
(define (part i) (build-path dir (format "part-~a.ndjson" i)))

(for ([i '(1 2 3)] [readings '((3.5 2.25) (4.0) (1.75 5.0))])
  (write-ndjson (dataframe (list (series (for/list ([_ (in-list readings)]) (format "s~a" i))
                                         #:name "station")
                                 (series readings #:name "reading")))
                (part i)))
(printf "part-1.ndjson:\n~a" (file->string (part 1)))

(displayln (read-ndjson (build-path dir "part-*.ndjson") #:row-index-name "row"))
(printf "first three: ~s\n"
        (shape (read-ndjson (build-path dir "part-*.ndjson") #:n-rows 3)))
(printf "file column: ~s\n"
        (column-names (read-ndjson (part 2) #:include-file-paths "file")))

(displayln (~> (scan-ndjson dir)
               (filter (> (col "reading") 3))
               (sort "reading")
               collect))

(define mixed (build-path dir "mixed.jsonl"))
(call-with-output-file mixed
  (lambda (out) (void (write-string "{\"n\":1}\n{\"n\":\"two\"}\n{\"n\":3}\n" out))))
(printf "strict: ~a\n"
        (with-handlers ([exn:fail? exn-message])
          (read-ndjson mixed #:infer-schema-length 1)))
(displayln (read-ndjson mixed #:infer-schema-length 1 #:ignore-errors #t))

(printf "refused: ~a\n"
        (with-handlers ([exn:fail? exn-message])
          (write-ndjson (read-ndjson (part 1)) (build-path dir "copy.ndjson.gz"))))
(define packed (build-path dir "all.ndjson.gz"))
(write-ndjson (read-ndjson (build-path dir "part-*.ndjson")) packed
              #:compression 'gzip #:compression-level 9)
(printf "gzip read back: ~s\n" (shape (read-ndjson packed)))

(delete-directory/files dir)
