#lang racket/base

(require (only-in ffi/unsafe free malloc)
         (only-in ffi/unsafe/alloc allocator deallocator)
         syntax/parse/define
         (for-syntax racket/base))

(provide with-raw-buffer
         with-release)

;; The finalizer allocator registers backs up a thread killed inside the
;; extent, whose dynamic-wind post thunks never run; free-buffer unregisters it.
(define free-buffer ((deallocator) free))
(define alloc-buffer
  ((allocator free-buffer) (lambda (count ctype) (malloc (max count 1) ctype 'raw))))

(define-syntax-parser with-release
  [(_ () body:expr ...+)
   #'(let () body ...)]
  [(_ ([name:id acquire:expr release:expr] more ...) body:expr ...+)
   #'(let ([name #f])
       (dynamic-wind
        (lambda () (set! name acquire))
        (lambda () (with-release (more ...) body ...))
        (lambda ()
          (when name
            (release name)
            (set! name #f)))))])

(define-syntax-parse-rule (with-raw-buffer ([name:id count:expr ctype:expr] ...+) body:expr ...+)
  (with-release ([name (alloc-buffer count ctype) free-buffer] ...) body ...))

(module+ test
  (require rackunit
           racket/runtime-path
           (only-in racket/file file->string)
           (only-in racket/list last)
           (only-in ffi/unsafe _int64 ptr-ref ptr-set!))

  (define released '())
  (define (release! tag) (set! released (cons tag released)))

  (set! released '())
  (check-equal? (with-release ([a 'a release!] [b 'b release!]) (list a b)) '(a b))
  (check-equal? released '(a b))

  (set! released '())
  (check-exn #rx"boom"
             (lambda () (with-release ([a 'a release!]) (error 'test "boom"))))
  (check-equal? released '(a))

  (set! released '())
  (check-equal? (let/ec k (with-release ([a 'a release!]) (k 'escaped) 'not-reached))
                'escaped)
  (check-equal? released '(a))

  (set! released '())
  (check-equal? (with-release ([a #f release!] [b 'b release!]) (list a b)) '(#f b))
  (check-equal? released '(b))

  (check-equal? (with-raw-buffer ([words 3 _int64])
                  (for ([i (in-range 3)]) (ptr-set! words _int64 i (* 10 i)))
                  (for/list ([i (in-range 3)]) (ptr-ref words _int64 i)))
                '(0 10 20))
  (check-equal? (with-raw-buffer ([empty 0 _int64]) 'zero-length-ok) 'zero-length-ok)

  (define-runtime-path private-dir ".")
  (define raw-pair #px"\\((?:malloc|free)\\s")
  (define offenders
    (for/list ([f (in-directory private-dir)]
               #:when (regexp-match? #rx"[.]rkt$" (path->string f))
               #:unless (equal? (last (explode-path f)) (string->path "resource.rkt"))
               #:when (regexp-match? raw-pair (file->string f)))
      f))
  (check-equal? offenders '()
                "raw malloc/free outside polars/private/resource.rkt: use with-raw-buffer"))
