#lang racket/base

(require racket/match
         (only-in racket/list count)
         polars/private/generic/operand-audit-classes
         polars/private/generic/operand-audit-table)

(define deviating
  (for*/list ([row (in-list audit-rows)]
              [got (in-value (let-values ([(outcome _) (run-row row)]) outcome))]
              #:unless (equal? got (python-outcome (eager-outcome row))))
    (list row (classify-deviation row got) got)))

(match (filter (match-lambda [(list _ class _) (not class)]) deviating)
  [(list (list rows _ gots) ..1)
   (for ([row (in-list rows)] [got (in-list gots)])
     (eprintf "unclassified: ~s\n  ours: ~s\n" row got))
   (exit 1)]
  ['()
   (write-deviations operand-deviation-classes
                     (for/list ([d (in-list deviating)])
                       (match-define (list row class got) d)
                       (append (audit-row-key row) (list class got))))
   (for ([c (in-list operand-deviation-classes)])
     (match-define (list class _) c)
     (printf "~a ~a\n" class (count (match-lambda [(list _ found _) (eq? found class)])
                                     deviating)))])
