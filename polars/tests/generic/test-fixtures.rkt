#lang racket/base

(require racket/runtime-path
         (only-in polars/private/generic/core
                  column-names dataframe dtype len ref series wrap-series)
         (only-in polars/tests/test-helpers
                  apply-keywords contains-all? contract-violation-of drops-during drops-once
                  gzip-file keyword-rejected? message-of not-utf-8-expected not-utf-8-names
                  refusal refusal-misses refused scratch-file settle! staging-files)
         (only-in polars/private/expr col Expr-ptr? expr-add)
         (only-in polars/private/foreign
                  dataframe-column polars-null polars-null? series-cast series-new-i32
                  series-new-i64)
         (only-in polars/private/parquet dataframe-read-parquet)
         (only-in polars/private/generic/reshape pivot)
         (only-in gregor datetime))

(provide (all-defined-out)
         (all-from-out polars/tests/test-helpers)
         col Expr-ptr? expr-add polars-null polars-null? datetime)

(define nul-names
  '("\u0000" "a\u0000b" "a\u0000" "\u0000a" "\u0000\u0000" "東京\u0000😀" "a\u0000\u0000b"))

(define (nul-frame n)
  (pivot (dataframe (list (series '(1 2) #:name "id") (series (list n n) #:name "k")
                          (series '(3 4) #:name "v")))
         #:on '("k") #:index '("id") #:values '("v")))

(define ints   (series '(1 2 3 4) #:name "ints" #:dtype 'i32))
(define floats (series '(1.5 2.0 4.25 8.0) #:name "floats"))
(define withnull (series (list 10 polars-null 30) #:dtype 'i32))

(define past-chrono-date (wrap-series (series-cast (series-new-i32 "d" '(2000000000)) 'date)))
(define past-chrono-datetime
  (wrap-series (series-cast (series-new-i64 "t" '(9223372036854775807))
                            '(datetime milliseconds #f))))
(define past-chrono-zoned
  (wrap-series (series-cast (series-new-i64 "k" '(9000000000000000000))
                            '(datetime microseconds "Europe/Brussels"))))

(define frame
  (dataframe (list (series '("alice" "bob" "carol") #:name "user")
                   (series '(10 25 18) #:name "score" #:dtype 'i32)
                   (series '(1.2 3.5 2.0) #:name "cost"))))

(define ops-df
  (dataframe (list (series '("a" "a" "b" "b" "c") #:name "group")
                   (series '(10 25 7 30 18) #:name "value" #:dtype 'i32)
                   (series '(1.2 2.4 0.5 3.1 1.8) #:name "cost"))))

(define v64 (series '(10 25 7 30 18) #:name "value"))   ; int64 (default)

(define-runtime-path produce-parquet "../../scribblings/data/produce.parquet")

(define prices
  (wrap-series (dataframe-column (dataframe-read-parquet produce-parquet) "price")))

(define (series-cells s)
  (for/list ([i (in-range (len s))]) (ref s i)))

(define (series-shape s)
  (list (dtype s) (series-cells s)))

(define (column d name)
  (series-cells (ref d #:columns name)))

(define (frame=? a b)
  (and (equal? (column-names a) (column-names b))
       (for/and ([name (in-list (column-names a))])
         (and (equal? (dtype (ref a #:columns name)) (dtype (ref b #:columns name)))
              (equal? (column a name) (column b name))))))

(define (cause-of message)
  (caddr (regexp-match #rx"^[^:]*: (failed to [^:]*: )?([^\n]*)" message)))

(define (one-file-pattern path)
  (define-values (dir name _) (split-path path))
  (build-path dir (regexp-replace #rx"^." (path->string name) "[&]")))

(define (dtypes-of df)
  (for/list ([name (in-list (column-names df))])
    (list name (dtype (ref df name)))))

(module+ test
  (require rackunit
           syntax/parse/define
           (for-syntax racket/base)
           (only-in compiler/find-exe find-exe)
           (only-in racket/dict dict-set)
           (only-in racket/file delete-directory/files file->string make-temporary-directory)
           (only-in racket/list filter-map)
           (only-in racket/match match match* match-define)
           (only-in racket/port copy-port)
           (only-in racket/string string-join)
           (only-in polars/private/generic/core shape)
           (only-in polars/private/io-contracts size-max))

  (provide call-in-child check-readers-agree check-reads-like-every check-staged-write
           eager-reader glob-reader outcome-difference read-outcome scan-reader)

  (define (read-outcome thunk)
    (with-handlers ([exn:fail? (lambda (e) (cause-of (exn-message e)))]) (thunk)))

  (define ((eager-reader read) path kvs)
    (apply-keywords read kvs path))
  (define ((glob-reader read) path kvs)
    (apply-keywords read (dict-set kvs '#:glob #t) (one-file-pattern path)))
  (define ((scan-reader scan collect) path kvs)
    (collect (apply-keywords scan kvs path)))

  (define (column-difference a b name)
    (define da (dtype (ref a name)))
    (define db (dtype (ref b name)))
    (cond
      [(equal? da db) (column-value-difference name (column a name) (column b name))]
      [else (format "column ~s: dtype ~s against ~s" name da db)]))

  (define (column-value-difference name as bs)
    (define row (for/first ([x (in-list as)] [y (in-list bs)] [i (in-naturals)]
                            #:unless (equal? x y))
                  i))
    (and row (format "column ~s, row ~a: ~e against ~e"
                     name row (list-ref as row) (list-ref bs row))))

  (define (frame-difference a b)
    (cond
      [(not (equal? (column-names a) (column-names b)))
       (format "columns ~s against ~s" (column-names a) (column-names b))]
      [(not (equal? (shape a) (shape b)))
       (format "shape ~s against ~s" (shape a) (shape b))]
      [else (for/or ([name (in-list (column-names a))]) (column-difference a b name))]))

  (define (outcome-difference a b)
    (match* (a b)
      [((? string?) (? string?)) (and (not (equal? a b)) "the errors differ")]
      [((? string?) _) "only the first raised"]
      [(_ (? string?)) "only the second raised"]
      [(_ _) (frame-difference a b)]))

  (define (describe-outcome outcome)
    (match outcome
      [(? string?) (format "raised: ~a" outcome)]
      [_ (format "shape ~s, dtypes ~s\n~a" (shape outcome) (dtypes-of outcome) outcome)]))

  (define-check (check-readers-agree* readers path kvs)
    (define outcomes
      (for/list ([reader (in-list readers)])
        (cons (car reader) (read-outcome (lambda () ((cdr reader) path kvs))))))
    (match-define (cons (cons first-label first) others) outcomes)
    (define differences
      (filter-map (lambda (other)
                    (define difference (outcome-difference first (cdr other)))
                    (and difference (format "~a against ~a: ~a" first-label (car other) difference)))
                  others))
    (unless (null? differences)
      (with-check-info* (cons (make-check-info 'disagreement
                                               (string-info (string-join differences "; ")))
                              (for/list ([outcome (in-list outcomes)])
                                (make-check-info (car outcome)
                                                 (string-info (describe-outcome (cdr outcome))))))
        fail-check)))

  (define-syntax-parser check-readers-agree
    [(_ readers:expr path:expr kvs:expr (~optional message:expr))
     (syntax/loc this-syntax (check-readers-agree* readers path kvs (~? message)))])

  (define (call-in-child form #:timeout [seconds 120])
    (define-values (child out in err)
      (subprocess #f #f #f (find-exe) "-l" "racket/base" "-l" "polars" "-e" (format "~s" form)))
    (close-output-port in)
    (define texts (list (open-output-string) (open-output-string)))
    (define copiers
      (for/list ([from (list out err)] [to (in-list texts)])
        (thread (lambda () (copy-port from to) (close-input-port from)))))
    (define status
      (cond
        [(sync/timeout seconds child) (subprocess-status child)]
        [else (subprocess-kill child #t) 'timeout]))
    (for-each thread-wait copiers)
    (apply values status (map get-output-string texts)))

  (define huge-counts (list (expt 2 62) size-max))

  (define (check-reads-like-every label every read-with)
    (for ([n (in-list huge-counts)])
      (check-true (frame=? (read-with n) every) (format "~a at ~a" label n))))

  (define char-device #o020000)

  (define (check-staged-write write! read ext df)
    (define dir (make-temporary-directory "rkt-polars-staged-~a"))
    (define (named stem) (format "~a.~a" stem ext))
    (define (failure cause)
      (pregexp (format "^~a: failed to write [^ ]+ to [^:]*: cannot create file: ~a"
                       (object-name write!) cause)))
    (define (check-replaced path)
      (write! df path)
      (check-true (frame=? (read path) df) (format "~a" path)))
    (define real (scratch-file dir (named "real") "OLD"))
    (define link (build-path dir (named "link")))
    (make-file-or-directory-link (named "real") link)
    (check-replaced link)
    (check-true (link-exists? link))
    (check-true (frame=? (read real) df))
    (define locked (scratch-file dir (named "locked") "OLD"))
    (file-or-directory-permissions locked #o444)
    (unless (memq 'write (file-or-directory-permissions locked))
      (define listing (directory-list dir))
      (check-exn (failure "Permission denied") (lambda () (write! df locked)))
      (check-equal? (file->string locked) "OLD")
      (check-equal? (directory-list dir) listing))
    (define private (scratch-file dir (named "private") "OLD"))
    (file-or-directory-permissions private #o600)
    (check-replaced private)
    (check-equal? (file-or-directory-permissions private 'bits) #o600)
    (write! df "/dev/null")
    (check-equal? (bitwise-and (hash-ref (file-or-directory-stat "/dev/null") 'mode) #o170000)
                  char-device)
    (check-replaced (build-path dir (named (make-string (- 249 (string-length ext)) #\x))))
    (define sub (build-path dir "sub"))
    (make-directory sub)
    (check-exn (failure "it is a directory$") (lambda () (write! df sub)))
    (check-equal? (staging-files dir) '())
    (check-equal? (directory-list sub) '())
    (delete-directory/files dir)))
