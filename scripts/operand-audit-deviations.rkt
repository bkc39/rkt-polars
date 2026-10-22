#lang racket/base

(require racket/cmdline
         racket/match
         (only-in racket/list count)
         polars/private/generic/operand-audit-classes
         polars/private/generic/operand-audit-table)

(define accept? (box #f))
(command-line
 #:once-each
 [("--accept") "Record new deviations and changed outcomes or classes" (set-box! accept? #t)])

(define deviating
  (for*/list ([row (in-list audit-rows)]
              [got (in-value (let-values ([(outcome _) (run-row row)]) outcome))]
              #:unless (equal? got (python-outcome (eager-outcome row))))
    (list (audit-row-key row) (classify-deviation row got) got)))

(match (recorder-verdict deviating deviations (unbox accept?))
  [(list 'unclassified rows)
   (for ([r (in-list rows)])
     (match-define (list key _ got) r)
     (eprintf "unclassified: ~s\n  ours: ~s\n" key got))
   (exit 1)]
  [(list 'unaccepted rows)
   (for ([r (in-list rows)])
     (match-define (list key class got was) r)
     (eprintf "not recorded: ~s\n  now: ~s ~s\n  was: ~s\n" key class got was))
   (eprintf "~a rows differ from the record; rerun with --accept to record them\n" (length rows))
   (exit 1)]
  [(list 'record rows)
   (write-deviations operand-deviation-classes
                     (for/list ([r (in-list rows)])
                       (match-define (list key class got) r)
                       (append key (list class got))))
   (for ([c (in-list operand-deviation-classes)])
     (match-define (list class _) c)
     (printf "~a ~a\n" class (count (match-lambda [(list _ found _) (eq? found class)]) rows)))])
