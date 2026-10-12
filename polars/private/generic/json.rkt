#lang racket/base

(require (only-in racket/contract/base -> contract-out)
         (only-in polars/private/json json-reader json-reader/c json-writer)
         (only-in polars/private/generic/core dataframe? wrap-dataframe)
         (only-in polars/private/generic/io define-wrapped))

(provide (contract-out
          [read-json (json-reader/c dataframe?)]
          [write-json (-> dataframe? path-string? void?)]))

(define-wrapped read-json wrap-dataframe (json-reader 'read-json))
(define write-json (json-writer 'write-json))

(module+ test
  (require rackunit
           racket/file
           racket/runtime-path
           (only-in gregor date)
           (prefix-in contracted: (submod ".."))
           (only-in polars/private/generic/core
                    column-names dataframe dtype height ref series shape)
           (only-in polars/private/generic/reshape cast)
           polars/private/generic/test-fixtures)

  (define-runtime-path data-dir "../../scribblings/data")
  (define stations (build-path data-dir "stations.json"))
  (define scratch (make-temporary-directory "rkt-polars-json-~a"))
  (define (dtypes-of df)
    (for/list ([name (column-names df)]) (list name (dtype (ref df name)))))
  (define (message-of thunk)
    (with-handlers ([exn:fail? exn-message]) (thunk) #f))
  (define (staging-files dir)
    (filter (lambda (name) (regexp-match? #rx"[.]partial$" (path->string name)))
            (directory-list dir)))
  (define (check-staged-write write! ext)
    (define dir (make-temporary-directory "rkt-polars-staged-~a"))
    (define (named stem) (format "~a.~a" stem ext))
    (define (failure cause)
      (pregexp (format "^~a: failed to write [^ ]+ to [^:]*: cannot create file: ~a"
                       (object-name write!) cause)))
    (define real (scratch-file dir (named "real") "OLD"))
    (define link (build-path dir (named "link")))
    (make-file-or-directory-link (named "real") link)
    (write! guide-df link)
    (check-true (link-exists? link))
    (check-not-equal? (file->string real) "OLD")
    (define locked (scratch-file dir (named "locked") "OLD"))
    (file-or-directory-permissions locked #o444)
    (unless (memq 'write (file-or-directory-permissions locked))
      (check-exn (failure "Permission denied") (lambda () (write! guide-df locked)))
      (check-equal? (file->string locked) "OLD"))
    (define private (scratch-file dir (named "private") "OLD"))
    (file-or-directory-permissions private #o600)
    (write! guide-df private)
    (check-equal? (file-or-directory-permissions private 'bits) #o600)
    (write! guide-df "/dev/null")
    (define long (build-path dir (named (make-string (- 249 (string-length ext)) #\x))))
    (write! guide-df long)
    (check-true (file-exists? long))
    (define sub (build-path dir "sub"))
    (make-directory sub)
    (check-exn (failure "") (lambda () (write! guide-df sub)))
    (check-equal? (staging-files dir) '())
    (check-equal? (directory-list sub) '())
    (delete-directory/files dir))

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
  (check-staged-write write-json "json")

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
  (check-exn #rx"^read-json: contract violation" (lambda () (contracted:read-json 'sym)))
  (check-exn #rx"^write-json: contract violation" (lambda () (contracted:write-json 5 "x")))
  (check-exn #rx"^write-json: contract violation" (lambda () (contracted:write-json frame 5)))

  (delete-directory/files scratch))
