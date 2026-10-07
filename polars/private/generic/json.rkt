#lang racket/base

(require (only-in racket/contract/base -> contract-out)
         (only-in polars/private/json
                  json-reader json-reader/c json-writer ndjson-reader ndjson-reader/c
                  ndjson-scanner ndjson-writer ndjson-writer/c)
         (only-in polars/private/generic/core
                  dataframe? lazyframe? wrap-dataframe wrap-lazyframe)
         syntax/parse/define)

(provide (contract-out
          [read-json (json-reader/c dataframe?)]
          [write-json (-> dataframe? path-string? void?)]
          [read-ndjson (ndjson-reader/c dataframe?)]
          [scan-ndjson (ndjson-reader/c lazyframe?)]
          [write-ndjson (ndjson-writer/c dataframe?)]))

(define-syntax-parse-rule (define-wrapped name:id wrap:expr make-reader:expr)
  (define name (procedure-rename (compose1 wrap (make-reader 'name)) 'name)))

(define-wrapped read-json wrap-dataframe json-reader)
(define-wrapped read-ndjson wrap-dataframe ndjson-reader)
(define-wrapped scan-ndjson wrap-lazyframe ndjson-scanner)
(define write-json (json-writer 'write-json))
(define write-ndjson (ndjson-writer 'write-ndjson))

(module+ test
  (require rackunit
           racket/file
           racket/runtime-path
           (only-in racket/contract exn:fail:contract:blame?)
           (only-in racket/list make-list)
           (only-in file/gzip gzip-through-ports)
           (only-in gregor date)
           (prefix-in contracted: (submod ".."))
           (only-in threading ~>)
           (only-in polars/private/generic/core
                    column-names dataframe dtype height lazyframe? ref series shape)
           (only-in polars/private/generic/operators >)
           (only-in polars/private/generic/reshape collect filter select)
           polars/private/generic/test-fixtures)

  (define-runtime-path data-dir "../../scribblings/data")
  (define stations (build-path data-dir "stations.json"))
  (define scratch (make-temporary-directory "rkt-polars-json-~a"))
  (define (scratch-file name text)
    (define path (build-path scratch name))
    (call-with-output-file path #:exists 'replace (lambda (out) (write-string text out)))
    path)
  (define (dtypes-of df)
    (for/list ([name (column-names df)]) (list name (dtype (ref df name)))))
  (define (message-of thunk)
    (with-handlers ([exn:fail? exn-message]) (thunk) #f))

  (define-values (required accepted) (procedure-keywords contracted:read-json))
  (check-equal? required '())
  (check-equal? accepted '(#:infer-schema-length #:schema #:schema-overrides))
  (check-equal? (object-name read-json) 'read-json)
  (check-equal? (object-name write-json) 'write-json)

  (define guide-path (build-path scratch "path.json"))
  (define guide-df
    (dataframe (list (series '(1 2 3) #:name "foo")
                     (series (list polars-null "bak" "baz") #:name "bar"))))
  (write-json guide-df guide-path)
  (check-equal? (file->string guide-path)
                "[{\"foo\":1,\"bar\":null},{\"foo\":2,\"bar\":\"bak\"},{\"foo\":3,\"bar\":\"baz\"}]")
  (check-true (frame=? (read-json guide-path) guide-df))

  (define example-frame
    (dataframe (list (series '("north" "south" "north") #:name "station")
                     (series (list 3.5 polars-null 2.25) #:name "reading"))))
  (define example-json (build-path scratch "readings.json"))
  (write-json example-frame example-json)
  (check-equal?
   (file->string example-json)
   "[{\"station\":\"north\",\"reading\":3.5},{\"station\":\"south\",\"reading\":null},{\"station\":\"north\",\"reading\":2.25}]")
  (check-true (frame=? (read-json example-json) example-frame))

  (define frame-json (build-path scratch "frame.json"))
  (write-json frame frame-json)
  (check-true (frame=? (read-json frame-json)
                       (dataframe (list (series '("alice" "bob" "carol") #:name "user")
                                        (series '(10 25 18) #:name "score")
                                        (series '(1.2 3.5 2.0) #:name "cost")))))

  (define readings (read-json stations))
  (check-equal? (shape readings) '(4 5))
  (check-equal? (dtypes-of readings)
                '(("station" string) ("day" string) ("reading" float64) ("flag" string)
                  ("note" string)))
  (check-equal? (column readings "reading") '(3.0 4.5 2.0 5.25))
  (check-equal? (column readings "note") (list polars-null polars-null polars-null "late"))

  (define typed
    (read-json stations
               #:schema '(("day" . date) ("station" . categorical) ("reading" . f32))))
  (check-equal? (dtypes-of typed) '(("day" date) ("station" categorical) ("reading" float32)))
  (check-equal? (column typed "day")
                (list (date 2024 1 1) (date 2024 1 1) (date 2024 1 2) (date 2024 1 2)))
  (check-equal? (column typed "station") '(north south north south))

  (check-equal? (column (read-json stations #:schema '(("day" . datetime))) "day")
                (list polars-null polars-null polars-null polars-null))
  (check-equal? (column (read-json stations #:schema '(("station" . date))) "station")
                (list polars-null polars-null polars-null polars-null))
  (define overridden (read-json stations #:schema-overrides '(("day" . date))))
  (check-equal? (dtypes-of overridden)
                '(("station" string) ("day" date) ("reading" float64) ("flag" string)
                  ("note" string)))
  (check-equal? (dtypes-of (read-json stations
                                      #:schema '(("station" . str) ("reading" . f64))
                                      #:schema-overrides '(("reading" . i64))))
                '(("station" string) ("reading" int64)))
  (check-equal? (column (read-json stations #:schema '(("station" . str) ("missing" . i32)))
                        "missing")
                (list polars-null polars-null polars-null polars-null))

  (define ragged-message
    (message-of (lambda () (read-json stations #:infer-schema-length 1))))
  (check-regexp-match
   #rx"^read-json: failed to read json from [^:]*stations.json: extra field in struct data: note"
   ragged-message)
  (check-regexp-match #rx"#:infer-schema-length" ragged-message)
  (check-false (regexp-match? #rx"infer_schema_length" ragged-message))
  (check-equal? (shape (read-json stations #:infer-schema-length #f)) '(4 5))
  (check-equal? (shape (read-json stations #:infer-schema-length 4)) '(4 5))

  (define mixed (scratch-file "mixed.json" "[{\"a\":1},{\"a\":2},{\"a\":\"x\"}]"))
  (check-equal? (column (read-json mixed) "a") '("1" "2" "x"))
  (define mixed-message (message-of (lambda () (read-json mixed #:infer-schema-length 1))))
  (check-regexp-match #rx"^read-json: failed to read json from [^:]*mixed.json: " mixed-message)
  (check-regexp-match #rx"#:infer-schema-length or passing #:schema" mixed-message)
  (check-false (regexp-match? #rx"infer_schema_length" mixed-message))

  (check-exn #rx"^read-json: failed to read json from [^:]*stations.json: schema overrides name a column not in the file: \"dya\"$"
             (lambda () (read-json stations #:schema-overrides '(("dya" . date)))))
  (check-exn #rx"^read-json: failed to read json from [^:]*stations.json: schema overrides name a column not in the schema: \"day\"$"
             (lambda () (read-json stations #:schema '(("station" . str))
                                   #:schema-overrides '(("day" . date)))))
  (check-exn #rx"^read-json: failed to read json from [^:]*nope.json: cannot open file: [Nn]o such file"
             (lambda () (read-json (build-path scratch "nope.json"))))
  (check-exn #rx"^read-json: failed to read json from [^:]*: cannot open file: it is a directory$"
             (lambda () (read-json scratch)))
  (check-exn #rx"^read-json: failed to read json from [^:]*numbers.json: can only deserialize json objects$"
             (lambda () (read-json (scratch-file "numbers.json" "[1,2,3]"))))
  (check-exn #rx"^read-json: failed to read json from [^:]*lines.json: "
             (lambda () (read-json (scratch-file "lines.json" "{\"a\":1}\n{\"a\":2}\n"))))
  (check-exn #rx"^read-json: failed to read json from [^:]*/[*][.]json: cannot open file: [Nn]o such file"
             (lambda () (read-json (build-path scratch "*.json"))))
  (check-exn #rx"^write-json: failed to write json to [^:]*out.json: cannot create file: [Nn]o such file"
             (lambda () (write-json frame (build-path scratch "no" "out.json"))))

  (check-equal? (shape (read-json (scratch-file "empty.json" "[]"))) '(0 0))
  (check-equal? (dtypes-of (read-json (build-path scratch "empty.json") #:schema '(("a" . i64))))
                '(("a" int64)))
  (check-equal? (column (read-json (scratch-file "object.json" "{\"a\":[1,2],\"b\":\"x\"}")) "b")
                '("x"))

  (parameterize ([current-directory scratch])
    (check-true (frame=? (read-json "path.json") guide-df))
    (write-json guide-df "relative.json")
    (check-true (file-exists? (build-path scratch "relative.json"))))

  (define bad-keywords
    `((#:schema . (("a" . (enum x y)))) (#:schema . (("a" . bogus))) (#:schema . ((a . i32)))
      (#:schema . (("a" . i32) ("a" . f64))) (#:schema . ,(hash "a" 'i32))
      (#:schema-overrides . #f) (#:schema-overrides . (("a" . (enum x))))
      (#:infer-schema-length . 0) (#:infer-schema-length . -1) (#:infer-schema-length . 1.5)))
  (for ([kv (in-list bad-keywords)])
    (check-exn (lambda (e) (and (exn:fail:contract:blame? e)
                                (regexp-match? #rx"^read-json: contract violation" (exn-message e))))
               (lambda () (keyword-apply contracted:read-json (list (car kv)) (list (cdr kv))
                                         (list stations)))
               (format "~s" kv)))
  (check-exn #rx"^read-json: contract violation" (lambda () (contracted:read-json 'sym)))
  (check-exn #rx"^write-json: contract violation" (lambda () (contracted:write-json 5 "x")))
  (check-exn #rx"^write-json: contract violation" (lambda () (contracted:write-json frame 5)))

  (define ndjson-keywords
    '(#:batch-size #:ignore-errors #:include-file-paths #:infer-schema-length #:low-memory
      #:n-rows #:rechunk #:row-index-name #:row-index-offset #:schema #:schema-overrides))
  (for ([reader (list contracted:read-ndjson contracted:scan-ndjson)])
    (define-values (required accepted) (procedure-keywords reader))
    (check-equal? required '())
    (check-equal? accepted ndjson-keywords))
  (check-equal? (map object-name (list read-ndjson scan-ndjson write-ndjson))
                '(read-ndjson scan-ndjson write-ndjson))

  (define stations-nd (build-path data-dir "stations.ndjson"))
  (define guide-nd (build-path scratch "path.ndjson"))
  (write-ndjson guide-df guide-nd)
  (check-equal? (file->string guide-nd)
                "{\"foo\":1,\"bar\":null}\n{\"foo\":2,\"bar\":\"bak\"}\n{\"foo\":3,\"bar\":\"baz\"}\n")
  (check-true (frame=? (read-ndjson guide-nd) guide-df))
  (define frame-nd (build-path scratch "frame.ndjson"))
  (write-ndjson frame frame-nd)
  (check-equal? (shape (read-ndjson frame-nd)) '(3 3))

  (define stations-frame (read-ndjson stations-nd))
  (check-true (frame=? stations-frame readings))
  (check-pred lazyframe? (scan-ndjson stations-nd))
  (check-true (frame=? (collect (scan-ndjson stations-nd)) stations-frame))
  (check-equal? (~> (scan-ndjson stations-nd) (filter (> (col "reading") 3)) collect
                    (column "station"))
                '("south" "south"))
  (check-equal? (dtypes-of (read-ndjson stations-nd
                                        #:schema '(("day" . date) ("station" . categorical)
                                                   ("reading" . f32))))
                '(("day" date) ("station" categorical) ("reading" float32)))
  (define nd-ms (read-ndjson stations-nd #:schema '(("day" . (datetime milliseconds)))))
  (check-equal? (dtypes-of nd-ms) '(("day" (datetime milliseconds #f))))
  (check-equal? (car (column nd-ms "day")) (datetime 2024 1 1))
  (check-equal? (dtypes-of (read-ndjson stations-nd #:schema '(("day" . datetime))))
                '(("day" (datetime microseconds #f))))
  (check-equal? (dtypes-of (~> (read-ndjson stations-nd #:schema-overrides '(("day" . date)))
                               (select "day" "reading")))
                '(("day" date) ("reading" float64)))
  (check-exn #rx"^scan-ndjson: failed to scan [^:]*stations.ndjson: schema overrides name a column not in the file: \"dya\"$"
             (lambda () (scan-ndjson stations-nd #:schema-overrides '(("dya" . date)))))
  (check-equal? (dtypes-of (read-ndjson stations-nd
                                        #:schema '(("station" . str) ("reading" . f64))
                                        #:schema-overrides '(("reading" . f32))))
                '(("station" string) ("reading" float32)))
  (check-exn #rx"^read-ndjson: failed to read ndjson from [^:]*stations.ndjson: schema overrides name a column not in the schema: \"day\"$"
             (lambda () (read-ndjson stations-nd #:schema '(("station" . str))
                                     #:schema-overrides '(("day" . date)))))

  (check-exn #rx"^read-ndjson: failed to read ndjson from [^:]*stations.ndjson: cannot parse '4.5' \\(f64\\) as Int64$"
             (lambda () (read-ndjson stations-nd #:infer-schema-length 1)))
  (define ignored (read-ndjson stations-nd #:infer-schema-length 1 #:ignore-errors #t))
  (check-equal? (column ignored "reading") (list 3 polars-null 2 polars-null))
  (check-equal? (column-names (read-ndjson stations-nd #:infer-schema-length 2))
                '("station" "day" "reading" "flag"))
  (check-equal? (shape (read-ndjson stations-nd #:infer-schema-length #f)) '(4 5))

  (define indexed (read-ndjson stations-nd #:n-rows 2 #:row-index-name "row"
                               #:row-index-offset 10 #:include-file-paths "file"))
  (check-equal? (column-names indexed) '("row" "station" "day" "reading" "flag" "note" "file"))
  (check-equal? (dtype (ref indexed "row")) 'uint32)
  (check-equal? (column indexed "row") '(10 11))
  (check-equal? (column indexed "file")
                (make-list 2 (path->string stations-nd)))
  (check-true (frame=? (read-ndjson stations-nd #:batch-size 1 #:low-memory #t #:rechunk #t)
                       stations-frame))
  (check-true (frame=? (read-ndjson stations-nd #:batch-size #f) stations-frame))

  (define parts (build-path scratch "parts"))
  (make-directory parts)
  (for ([name '("p2" "p1" "p3")] [x '(20 10 30)])
    (write-ndjson (dataframe (list (series (list x) #:name "x")))
                  (build-path parts (format "~a.ndjson" name))))
  (define pattern (build-path parts "p*.ndjson"))
  (check-equal? (column (read-ndjson pattern) "x") '(10 20 30))
  (check-equal? (~> pattern scan-ndjson collect (column "x")) '(10 20 30))
  (check-equal? (column (read-ndjson parts) "x") '(10 20 30))
  (check-equal? (column (read-ndjson pattern #:n-rows 2 #:row-index-name "i") "i") '(0 1))
  (define nothing (build-path parts "*.none"))
  (check-exn #rx"^read-ndjson: failed to read ndjson from [^:]*: no files match the pattern$"
             (lambda () (read-ndjson nothing)))
  (check-pred lazyframe? (scan-ndjson nothing))
  (check-exn #rx": no files match the pattern$" (lambda () (collect (scan-ndjson nothing))))
  (define gone (build-path parts "gone.ndjson"))
  (check-exn #rx"^read-ndjson: failed to read ndjson from [^:]*gone.ndjson: cannot open file: [Nn]o such file"
             (lambda () (read-ndjson gone)))
  (check-pred lazyframe? (scan-ndjson gone))
  (check-exn #rx"^lazyframe-collect: " (lambda () (collect (scan-ndjson gone))))

  (define bracketed (build-path scratch "nd[1]"))
  (make-directory bracketed)
  (write-ndjson guide-df (build-path bracketed "data.ndjson"))
  (parameterize ([current-directory bracketed])
    (check-true (frame=? (read-ndjson "data.ndjson") guide-df))
    (check-true (frame=? (read-ndjson "*.ndjson") guide-df))
    (check-true (frame=? (collect (scan-ndjson "data.ndjson")) guide-df))
    (write-ndjson guide-df "copy.ndjson")
    (check-true (file-exists? (build-path bracketed "copy.ndjson"))))

  (define gz-message
    (message-of (lambda () (write-ndjson guide-df (build-path scratch "plain.ndjson.gz")))))
  (check-regexp-match #rx"^write-ndjson: failed to write ndjson to [^:]*plain.ndjson.gz: " gz-message)
  (check-regexp-match #rx"#:check-extension #f" gz-message)
  (check-false (regexp-match? #rx"check_extension|Resolved plan" gz-message))
  (check-false (file-exists? (build-path scratch "plain.ndjson.gz")))
  (write-ndjson guide-df (build-path scratch "plain.ndjson.gz") #:check-extension #f)
  (check-true (frame=? (read-ndjson (build-path scratch "plain.ndjson.gz")) guide-df))

  (for ([compression '(gzip zstd)] [suffix '("gz" "zst")] [top '(9 22)])
    (define packed (build-path scratch (format "packed.ndjson.~a" suffix)))
    (write-ndjson guide-df packed #:compression compression)
    (check-not-equal? (call-with-input-file packed read-char) #\{)
    (check-true (frame=? (read-ndjson packed) guide-df) (format "~a" compression))
    (check-equal? (height (collect (scan-ndjson packed #:n-rows 2))) 2)
    (write-ndjson guide-df packed #:compression compression #:compression-level top)
    (check-true (frame=? (read-ndjson packed) guide-df) (format "~a ~a" compression top)))
  (check-equal? (column (read-ndjson (build-path scratch "packed.ndjson.*")) "foo") '(1 2 3 1 2 3))
  (define misnamed (build-path scratch "misnamed.ndjson"))
  (define misnamed-message
    (message-of (lambda () (write-ndjson guide-df misnamed #:compression 'gzip))))
  (check-regexp-match #rx"expected suffix: \\(\\.gz\\), pass #:check-extension #f" misnamed-message)
  (check-false (regexp-match? #rx"check_extension|Resolved plan" misnamed-message))
  (write-ndjson guide-df misnamed #:compression 'zstd #:check-extension #f)
  (check-true (frame=? (read-ndjson misnamed) guide-df))

  (define json-gz (build-path scratch "path.json.gz"))
  (call-with-output-file json-gz
    (lambda (out) (call-with-input-file guide-path (lambda (in) (gzip-through-ports in out #f 0)))))
  (check-true (frame=? (read-json json-gz) guide-df))
  (define magic-message
    (message-of (lambda () (read-ndjson (scratch-file "magic.ndjson" "x^junk\n{\"a\":1}\n")))))
  (check-regexp-match #rx"^read-ndjson: failed to read ndjson from [^:]*magic.ndjson: " magic-message)
  (check-false (regexp-match? #rx"TapeError|decompress' feature" magic-message))
  (check-regexp-match #rx"TapeError"
                      (message-of (lambda () (read-ndjson (scratch-file "late.ndjson"
                                                                        "{\"a\":1}\nx^junk\n")))))
  (define long-nd (build-path scratch "long.ndjson"))
  (write-ndjson (dataframe (list (series (for/list ([i 5000]) i) #:name "n"))) long-nd)
  (define long-gz (build-path scratch "long.ndjson.gz"))
  (call-with-output-file long-gz
    (lambda (out) (call-with-input-file long-nd (lambda (in) (gzip-through-ports in out #f 0)))))
  (check-equal? (height (read-ndjson long-gz)) 5000)
  (check-exn #rx"^write-ndjson: failed to write ndjson to [^:]*out.ndjson: "
             (lambda () (write-ndjson guide-df (build-path scratch "no" "out.ndjson"))))

  (define nd-bad
    `((#:schema . (("a" . i8))) (#:schema . (("a" . time))) (#:schema . (("a" . (enum x))))
      (#:schema-overrides . (("a" . (duration microseconds)))) (#:schema-overrides . (("a" . u16)))
      (#:infer-schema-length . 0) (#:batch-size . 0) (#:n-rows . -1) (#:n-rows . 1.5)
      (#:low-memory . 1) (#:rechunk . "yes") (#:ignore-errors . 1)
      (#:row-index-name . row) (#:row-index-offset . -1) (#:row-index-offset . 4294967296)
      (#:include-file-paths . file)))
  (for* ([reader (in-list (list contracted:read-ndjson contracted:scan-ndjson))]
         [kv (in-list nd-bad)])
    (define blamed (regexp (format "^~a: contract violation" (object-name reader))))
    (check-exn (lambda (e) (and (exn:fail:contract:blame? e) (regexp-match? blamed (exn-message e))))
               (lambda () (keyword-apply reader (list (car kv)) (list (cdr kv)) (list stations-nd)))
               (format "~a ~s" (object-name reader) kv)))
  (check-exn #rx"#:row-index-name and #:include-file-paths must name different columns"
             (lambda () (contracted:read-ndjson stations-nd #:row-index-name "x"
                                                #:include-file-paths "x")))
  (check-exn #rx"^write-ndjson: contract violation"
             (lambda () (contracted:write-ndjson guide-df guide-nd #:check-extension 1)))
  (for ([kvs (in-list '(((#:compression . brotli)) ((#:compression-level . 3))
                        ((#:compression . uncompressed) (#:compression-level . 3))
                        ((#:compression . gzip) (#:compression-level . 10))
                        ((#:compression . zstd) (#:compression-level . 0))
                        ((#:compression . zstd) (#:compression-level . 23))
                        ((#:compression . gzip) (#:compression-level . -1))))])
    (check-exn #rx"^write-ndjson: contract violation"
               (lambda () (keyword-apply contracted:write-ndjson (map car kvs) (map cdr kvs)
                                         (list guide-df (build-path scratch "never.ndjson.gz"))))
               (format "~s" kvs)))
  (check-false (file-exists? (build-path scratch "never.ndjson.gz")))
  (check-exn #rx"#:compression-level needs #:compression 'gzip"
             (lambda () (contracted:write-ndjson guide-df guide-nd #:compression-level 3)))
  (check-exn #rx"^read-ndjson: contract violation" (lambda () (contracted:read-ndjson 'sym)))

  (delete-directory/files scratch))
