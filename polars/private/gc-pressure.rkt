#lang racket/base

(provide call-with-collections)

;; For tests: the thunk's result and how many collections ran while another
;; thread requested them.
(define (call-with-collections thunk)
  (define before (collection-count))
  (define collector
    (thread (lambda ()
              (let loop ()
                (collect-garbage 'minor)
                (sleep 0)
                (loop)))))
  (define result (dynamic-wind void thunk (lambda () (kill-thread collector))))
  (values result (- (collection-count) before)))

(define (collection-count)
  (define stats (make-vector 12 0))
  (vector-set-performance-stats! stats)
  (vector-ref stats 3))
