#lang racket/base

(require racket/cmdline
         racket/match
         (only-in racket/list count)
         polars/tests/generic/operand-audit-classes
         polars/tests/generic/operand-audit-table)

(define accept? (box #f))
(command-line
 #:once-each
 [("--accept") "Record new deviations and changed outcomes or classes" (set-box! accept? #t)])

(define python-by-key
  (for/hash ([row (in-list audit-rows)])
    (values (audit-row-key row) (python-outcome (eager-outcome row)))))

(define deviating
  (for*/list ([row (in-list audit-rows)]
              [got (in-value (let-values ([(outcome _) (run-row row)]) outcome))]
              #:unless (equal? got (hash-ref python-by-key (audit-row-key row))))
    (list (audit-row-key row) (classify-deviation row got) got)))

(match (recorder-verdict deviating deviations (unbox accept?))
  [(list 'unclassified rows)
   (for ([r (in-list rows)])
     (match-define (list key _ got) r)
     (eprintf "unclassified: ~s\n  ours: ~s\n" key got))
   (exit 1)]
  [(list 'unaccepted rows)
   (write-string (unaccepted-report rows python-by-key) (current-error-port))
   (exit 1)]
  [(list 'record rows)
   (write-deviations operand-deviation-classes
                     (for/list ([r (in-list rows)])
                       (match-define (list key class got) r)
                       (append key (list class got))))
   (for ([c (in-list operand-deviation-classes)])
     (match-define (list class _) c)
     (printf "~a ~a\n" class (count (match-lambda [(list _ found _) (eq? found class)]) rows)))])
