#lang racket/base

;; Requires no polars module: the test submodules of foreign.rkt, expr.rkt and
;; generic/core.rkt require this one, which would otherwise be a module cycle.

(require (for-syntax racket/base)
         (only-in file/gzip gzip-through-ports)
         (only-in racket/contract contract-name exn:fail:contract:blame?)
         (only-in racket/file display-to-file file->bytes)
         (only-in racket/match match-define)
         (only-in racket/path path-has-extension?)
         (only-in racket/runtime-path define-runtime-path)
         (only-in racket/string string-contains? string-prefix?)
         syntax/parse/define)

(provide apply-keywords contains-all? contract-violation-of drops-during drops-once gzip-file
         keyword-rejected? message-of not-utf-8-expected not-utf-8-names polars-sources refusal
         refusal-misses refused scratch-file settle! staging-files)

(define-runtime-path polars-dir "..")

(define (polars-sources [root polars-dir])
  (for*/list ([dir (in-list '("private" "tests"))]
              [file (in-directory (build-path root dir))]
              #:when (path-has-extension? file #".rkt"))
    (simplify-path file)))

(define (scratch-file dir name text)
  (define path (build-path dir name))
  (display-to-file text path #:exists 'replace)
  path)

(define ((contract-violation-of who) e)
  (and (exn:fail:contract:blame? e)
       (regexp-match? (regexp (format "^~a: contract violation" (regexp-quote (symbol->string who))))
                      (exn-message e))))

(define (refused who given #:expected [expected "[^\n]*"])
  (regexp (string-append "^" (regexp-quote (format "~a: contract violation\n  expected: " who))
                         expected "\n  given: " (regexp-quote (format "~e" given)) "\n")))

(define not-utf-8-names (list (bytes 255) (bytes->path (bytes 255))))

(define not-utf-8-expected "[^\n]*utf-8\\?[^\n]*")

(define ((keyword-rejected? kw) e)
  (regexp-match? (regexp (string-append "does not expect an argument with given keyword\n"
                                        ".*given keyword: #:" (regexp-quote (keyword->string kw))
                                        "(?m:$)"))
                 (exn-message e)))

(define (message-of thunk)
  (with-handlers ([exn:fail? exn-message]) (thunk) #f))

(define (contains-all? text parts)
  (for/and ([part (in-list parts)])
    (string-contains? text part)))

(define (apply-keywords proc kvs . args)
  (define sorted (sort kvs keyword<? #:key car))
  (keyword-apply proc (map car sorted) (map cdr sorted) args))

(define (staging-files dir)
  (filter (lambda (name) (path-has-extension? name #".partial")) (directory-list dir)))

(define (gzip-file from to)
  (call-with-output-file to #:exists 'replace
    (lambda (out) (gzip-through-ports (open-input-bytes (file->bytes from)) out #f 0))))

(define (settle!)
  (for ([_ (in-range 4)])
    (collect-garbage)
    (sleep 0.1)))

(define (drops-once count drop make)
  (settle!)
  (define before (count))
  (drop (make))
  (settle!)
  (- (count) before))

(define (drops-during count thunk)
  (settle!)
  (define before (count))
  (thunk)
  (- (count) before))

(define-syntax-parse-rule (refusal who:expr contract:expr given:expr call:expr
                            (~optional (~and #:unblamed (~bind [blamed? #'#f]))
                                       #:defaults ([blamed? #'#t])))
  (list who contract given (lambda () call) blamed?))

(define (refusal-miss row)
  (match-define (list who contract given thunk blamed?) row)
  (define-values (refused? matches? end)
    (if blamed?
        (values exn:fail:contract:blame? string-prefix? "\n")
        (values exn:fail:contract? string=? "")))
  (define expected
    (format "~a: contract violation\n  expected: ~s\n  given: ~e~a"
            who (contract-name contract) given end))
  (define message (with-handlers ([refused? exn-message]) (thunk) #f))
  (and (not (and message (matches? message expected)))
       (list who given message)))

(define (refusal-misses rows)
  (filter values (map refusal-miss rows)))
