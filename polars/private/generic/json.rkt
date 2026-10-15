#lang racket/base

(require (only-in racket/contract/base -> contract-out)
         (only-in polars/private/json
                  json-reader json-reader/c json-writer ndjson-reader ndjson-reader/c
                  ndjson-scanner ndjson-writer ndjson-writer/c)
         (only-in polars/private/generic/core
                  dataframe? define-wrapped lazyframe? wrap-dataframe wrap-lazyframe))

(provide (contract-out
          [read-json (json-reader/c dataframe?)]
          [write-json (-> dataframe? path-string? void?)]
          [read-ndjson (ndjson-reader/c dataframe?)]
          [scan-ndjson (ndjson-reader/c lazyframe?)]
          [write-ndjson (ndjson-writer/c dataframe?)]))

(define-wrapped read-json wrap-dataframe (json-reader 'read-json))
(define-wrapped read-ndjson wrap-dataframe (ndjson-reader 'read-ndjson))
(define-wrapped scan-ndjson wrap-lazyframe (ndjson-scanner 'scan-ndjson))
(define write-json (json-writer 'write-json))
(define write-ndjson (ndjson-writer 'write-ndjson))

(module+ test
  (require rackunit
           racket/file
           racket/runtime-path
           (only-in racket/list make-list)
           (only-in gregor date moment)
           (prefix-in contracted: (submod ".."))
           (only-in threading ~>)
           (only-in polars/private/generic/core
                    column-names dataframe dtype height lazyframe? ref series shape)
           (only-in polars/private/generic/operators >)
           (only-in polars/private/generic/reshape cast collect filter select)
           (only-in polars/private/io-contracts size-max)
           polars/private/generic/test-fixtures
           (submod polars/private/generic/test-fixtures test))

  (define-runtime-path data-dir "../../scribblings/data")
  (define stations (build-path data-dir "stations.json"))
  (define scratch (make-temporary-directory "rkt-polars-json-~a"))

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
  (check-true (frame=? (read-json stations #:infer-schema-length size-max)
                       (read-json stations #:infer-schema-length #f)))

  (define mixed (scratch-file scratch "mixed.json" "[{\"a\":1},{\"a\":2},{\"a\":\"x\"}]"))
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
             (lambda () (read-json (scratch-file scratch "numbers.json" "[1,2,3]"))))
  (check-exn #rx"^read-json: failed to read json from [^:]*lines.json: "
             (lambda () (read-json (scratch-file scratch "lines.json" "{\"a\":1}\n{\"a\":2}\n"))))
  (check-exn #rx"^read-json: failed to read json from [^:]*/[*][.]json: cannot open file: [Nn]o such file"
             (lambda () (read-json (build-path scratch "*.json"))))
  (check-exn #rx"^write-json: failed to write json to [^:]*out.json: cannot create file: [Nn]o such file"
             (lambda () (write-json frame (build-path scratch "no" "out.json"))))

  (define keep (scratch-file scratch "keep.json" "PRECIOUS"))
  (define binary-frame
    (dataframe (list (series '(1 2) #:name "a") (cast (series '("p" "q") #:name "b") 'binary))))
  (check-exn #rx"^write-json: failed to write json to [^:]*keep.json: cannot write the binary column \"b\" as JSON$"
             (lambda () (write-json binary-frame keep)))
  (check-equal? (file->string keep) "PRECIOUS")
  (check-equal? (staging-files scratch) '())
  (write-json guide-df keep)
  (check-true (frame=? (read-json keep) guide-df))
  (define dangling (build-path scratch "dangling.json"))
  (make-file-or-directory-link "made.json" dangling)
  (check-exn #rx"cannot write the binary column \"b\" as JSON$"
             (lambda () (write-json binary-frame dangling)))
  (check-false (file-exists? (build-path scratch "made.json")))
  (delete-file dangling)
  (check-staged-write write-json read-json "json" guide-df)

  (define promoted (scratch-file scratch "promoted.json" "[{\"a\":1},{\"a\":2.5},{\"a\":true}]"))
  (check-equal? (column (read-json promoted #:infer-schema-length 1) "a") '(1 2 1))
  (check-equal? (column (read-json stations #:schema-overrides '(("reading" . i64))) "reading")
                '(3 4 2 5))
  (check-equal? (column (read-json promoted) "a") '(1.0 2.5 1.0))
  (check-equal? (column (read-json (scratch-file scratch "wide.json" "[{\"a\":300},{\"a\":-1}]")
                                   #:schema '(("a" . i8)))
                        "a")
                (list polars-null -1))

  (check-equal? (shape (read-json (scratch-file scratch "empty.json" "[]"))) '(0 0))
  (check-equal? (dtypes-of (read-json (build-path scratch "empty.json") #:schema '(("a" . i64))))
                '(("a" int64)))
  (check-equal? (column (read-json (scratch-file scratch "object.json" "{\"a\":[1,2],\"b\":\"x\"}")) "b")
                '("x"))

  (parameterize ([current-directory scratch])
    (check-true (frame=? (read-json "path.json") guide-df))
    (write-json guide-df "relative.json")
    (check-true (file-exists? (build-path scratch "relative.json"))))

  (define (clash-result name requires json-call)
    (parameterize ([current-namespace (make-base-namespace)])
      (eval `(module ,name racket/base
               (require polars ,@requires)
               (provide result)
               (define result (list (shape (read-json ,(path->string stations))) ,json-call))))
      (dynamic-require `(quote ,name) 'result)))
  (check-equal? (clash-result 'prefixed '((prefix-in js: json))
                              '(js:read-json (open-input-string "[1, 2]")))
                '((4 5) (1 2)))
  (check-equal? (clash-result 'excepted '((except-in json read-json write-json))
                              '(string->jsexpr "[1, 2]"))
                '((4 5) (1 2)))
  (check-exn #rx"identifier already required"
             (lambda () (clash-result 'clashing '(json) '(string->jsexpr "[1, 2]"))))

  (define bad-keywords
    `((#:schema . (("a" . (enum x y)))) (#:schema . (("a" . bogus))) (#:schema . ((a . i32)))
      (#:schema . (("a" . i32) ("a" . f64))) (#:schema . ,(hash "a" 'i32))
      (#:schema-overrides . #f) (#:schema-overrides . (("a" . (enum x))))
      (#:schema . (("a\u0000b" . i64))) (#:schema-overrides . (("day\u0000x" . date)))
      (#:infer-schema-length . 0) (#:infer-schema-length . -1) (#:infer-schema-length . 1.5)
      (#:infer-schema-length . ,(expt 2 64))))
  (for ([kv (in-list bad-keywords)])
    (check-exn (contract-violation-of 'read-json)
               (lambda () (apply-keywords contracted:read-json (list kv) stations))
               (format "~s" kv)))
  (check-exn (contract-violation-of 'read-json) (lambda () (contracted:read-json 'sym)))
  (check-exn (contract-violation-of 'write-json) (lambda () (contracted:write-json 5 "x")))
  (check-exn (contract-violation-of 'write-json) (lambda () (contracted:write-json frame 5)))

  (define-values (nd-required nd-accepted) (procedure-keywords contracted:read-ndjson))
  (check-equal? nd-required '())
  (check-equal? (remove* nd-accepted accepted) '())
  (check-equal? (remove* accepted nd-accepted)
                '(#:batch-size #:ignore-errors #:include-file-paths #:low-memory #:n-rows
                  #:rechunk #:row-index-name #:row-index-offset))
  (check-equal? (call-with-values (lambda () (procedure-keywords contracted:scan-ndjson)) list)
                (list nd-required nd-accepted))
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
  (for ([n (list (expt 2 62) size-max)])
    (check-true (frame=? (read-ndjson stations-nd #:infer-schema-length n)
                         (read-ndjson stations-nd #:infer-schema-length #f)))
    (check-true (frame=? (collect (scan-ndjson stations-nd #:infer-schema-length n))
                         stations-frame)))
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
  (gzip-file guide-path json-gz)
  (check-true (frame=? (read-json json-gz) guide-df))
  (define magic-message
    (message-of (lambda () (read-ndjson (scratch-file scratch "magic.ndjson" "x^junk\n{\"a\":1}\n")))))
  (check-regexp-match #rx"^read-ndjson: failed to read ndjson from [^:]*magic.ndjson: " magic-message)
  (check-false (regexp-match? #rx"TapeError|decompress' feature" magic-message))
  (check-regexp-match #rx"TapeError"
                      (message-of (lambda () (read-ndjson (scratch-file scratch "late.ndjson"
                                                                        "{\"a\":1}\nx^junk\n")))))
  (define long-nd (build-path scratch "long.ndjson"))
  (write-ndjson (dataframe (list (series (for/list ([i 5000]) i) #:name "n"))) long-nd)
  (define long-gz (build-path scratch "long.ndjson.gz"))
  (gzip-file long-nd long-gz)
  (check-equal? (height (read-ndjson long-gz)) 5000)
  (check-exn #rx"^write-ndjson: failed to write ndjson to [^:]*out.ndjson: "
             (lambda () (write-ndjson guide-df (build-path scratch "no" "out.ndjson"))))

  (define keep-nd (scratch-file scratch "keep.ndjson" "PRECIOUS"))
  (check-exn #rx"^write-ndjson: failed to write ndjson to [^:]*keep.ndjson: cannot write the binary column \"b\" as JSON$"
             (lambda () (write-ndjson binary-frame keep-nd)))
  (check-equal? (file->string keep-nd) "PRECIOUS")
  (define keep-gz (scratch-file scratch "keep.ndjson.gz" "PRECIOUS"))
  (check-exn #rx"^write-ndjson: failed to write ndjson to [^:]*keep.ndjson.gz: pass #:check-extension #f"
             (lambda () (write-ndjson guide-df keep-gz)))
  (check-equal? (file->string keep-gz) "PRECIOUS")
  (check-equal? (staging-files scratch) '())
  (write-ndjson guide-df keep-nd)
  (check-true (frame=? (read-ndjson keep-nd) guide-df))
  (define dangling-nd (build-path scratch "dangling.ndjson"))
  (make-file-or-directory-link "made.ndjson" dangling-nd)
  (check-exn #rx"cannot write the binary column \"b\" as JSON$"
             (lambda () (write-ndjson binary-frame dangling-nd)))
  (check-false (file-exists? (build-path scratch "made.ndjson")))
  (delete-file dangling-nd)
  (check-staged-write write-ndjson read-ndjson "ndjson" guide-df)

  (define leftover (build-path scratch "leftover"))
  (make-directory leftover)
  (write-ndjson guide-df (build-path leftover "a.ndjson"))
  (void (scratch-file leftover ".rkt-polars-1-0.partial" "{\"foo\":99}\n"))
  (check-true (frame=? (read-ndjson (build-path leftover "*.ndjson")) guide-df))
  (check-exn #rx"directory contained paths with different file extensions: .*/[.]rkt-polars-1-0[.]partial"
             (lambda () (read-ndjson leftover)))

  (define strays (build-path scratch "strays"))
  (make-directory strays)
  (write-ndjson guide-df (build-path strays "a.ndjson"))
  (display-to-file "notes" (build-path strays "README"))
  (check-exn #rx"^read-ndjson: failed to read ndjson from [^:]*strays: directory contained paths with different file extensions"
             (lambda () (read-ndjson strays)))
  (delete-file (build-path strays "README"))
  (display-to-file "x" (build-path strays ".DS_Store"))
  (check-exn #rx"directory contained paths with different file extensions"
             (lambda () (read-ndjson strays)))
  (delete-file (build-path strays ".DS_Store"))
  (check-true (frame=? (read-ndjson strays) guide-df))
  (check-equal? (height (read-ndjson stations-nd #:n-rows (sub1 (expt 2 64)))) 4)

  (define nd-bad
    `((#:schema . (("a" . i8))) (#:schema . (("a" . time))) (#:schema . (("a" . (enum x))))
      (#:schema-overrides . (("a" . (duration microseconds)))) (#:schema-overrides . (("a" . u16)))
      (#:infer-schema-length . 0) (#:batch-size . 0) (#:n-rows . -1) (#:n-rows . 1.5)
      (#:low-memory . 1) (#:rechunk . "yes") (#:ignore-errors . 1)
      (#:row-index-name . row) (#:row-index-offset . -1) (#:row-index-offset . 4294967296)
      (#:include-file-paths . file) (#:n-rows . ,(expt 2 64)) (#:n-rows . ,(+ 2 (expt 2 64)))
      (#:infer-schema-length . ,(expt 2 64)) (#:batch-size . ,(expt 2 64))
      (#:schema . (("a\u0000zzz" . i64))) (#:row-index-name . "i\u0000x")
      (#:include-file-paths . "p\u0000x")))
  (for* ([reader (in-list (list contracted:read-ndjson contracted:scan-ndjson))]
         [kv (in-list nd-bad)])
    (check-exn (contract-violation-of (object-name reader))
               (lambda () (apply-keywords reader (list kv) stations-nd))
               (format "~a ~s" (object-name reader) kv)))
  (check-exn #rx"#:row-index-name and #:include-file-paths must name different columns"
             (lambda () (contracted:read-ndjson stations-nd #:row-index-name "x"
                                                #:include-file-paths "x")))
  (check-exn (contract-violation-of 'read-ndjson)
             (lambda () (contracted:read-ndjson stations-nd #:row-index-name "p\u0000x"
                                                #:include-file-paths "p\u0000y")))
  (check-exn (contract-violation-of 'write-ndjson)
             (lambda () (contracted:write-ndjson guide-df guide-nd #:check-extension 1)))
  (for ([kvs (in-list '(((#:compression . brotli)) ((#:compression-level . 3))
                        ((#:compression . uncompressed) (#:compression-level . 3))
                        ((#:compression . gzip) (#:compression-level . 10))
                        ((#:compression . zstd) (#:compression-level . 0))
                        ((#:compression . zstd) (#:compression-level . 23))
                        ((#:compression . gzip) (#:compression-level . -1))))])
    (check-exn (contract-violation-of 'write-ndjson)
               (lambda () (apply-keywords contracted:write-ndjson kvs
                                          guide-df (build-path scratch "never.ndjson.gz")))
               (format "~s" kvs)))
  (check-false (file-exists? (build-path scratch "never.ndjson.gz")))
  (check-exn #rx"#:compression-level needs #:compression 'gzip"
             (lambda () (contracted:write-ndjson guide-df guide-nd #:compression-level 3)))
  (check-exn (contract-violation-of 'read-ndjson) (lambda () (contracted:read-ndjson 'sym)))

  (define brussels
    (dataframe (list (series (list (moment 2021 3 27 12 0 0 500000000 #:tz "Europe/Brussels")
                                   polars-null (moment 2021 7 1 #:tz "Europe/Brussels"))
                             #:name "t"))))
  (define brussels-ndjson (build-path scratch "brussels.ndjson"))
  (write-ndjson brussels brussels-ndjson)
  (check-equal? (file->string brussels-ndjson)
                (string-append "{\"t\":\"2021-03-27T12:00:00.500+01:00\"}\n{\"t\":null}\n"
                               "{\"t\":\"2021-07-01T00:00:00+02:00\"}\n"))

  (delete-directory/files scratch))
