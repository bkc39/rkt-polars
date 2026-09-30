#lang racket/base

;; `--strict` (#90): the nycflights arc's exit gate.  A run passes when every
;; scoreboard check PASSes and every op's rkt/py ratio, as printed, is within
;; its allowance (allowances.rkt).  An op over its allowance is timed once more
;; before it fails.

(require (only-in racket/format ~r)
         (only-in racket/string string-join)
         "allowances.rkt")

(provide (struct-out check-outcome)
         (struct-out op-outcome)
         allowance-for
         allowance-line
         check-violations
         op-violations
         print-verdict
         ratio->string
         ratio-within?
         retime-over-allowance)

(struct check-outcome (id label issue pass? text))

;; ratios: one entry per timing, #f where either side has no time.
(struct op-outcome (key label ratios reason))

(define (allowance-for key [table allowances])
  (or (findf (lambda (a) (equal? (allowance-op a) key)) table)
      default-allowance))

(define (hundredths ratio)
  (~r ratio #:precision '(= 2)))

(define (ratio->string ratio)
  (if ratio (string-append (hundredths ratio) "×") "n/a"))

(define (ratio-within? ratio bound)
  (and ratio (<= (string->number (hundredths ratio)) bound)))

(define (within-allowance? o table)
  (define bound (allowance-ratio (allowance-for (op-outcome-key o) table)))
  (for/or ([ratio (in-list (op-outcome-ratios o))])
    (ratio-within? ratio bound)))

(define (allowance-line label-of [table allowances])
  (string-join
   (for/list ([a (in-list (cons default-allowance table))])
     (format "~a ~a (#~a)"
             (if (allowance-op a) (label-of (allowance-op a)) "rkt/py at most")
             (ratio->string (allowance-ratio a))
             (allowance-issue a)))
   "; "))

(define (check-violations outcomes)
  (for/list ([o (in-list outcomes)]
             #:unless (check-outcome-pass? o))
    (format "~a ~a: FAIL, ~a (#~a)"
            (check-outcome-id o)
            (check-outcome-label o)
            (check-outcome-text o)
            (check-outcome-issue o))))

(define (retime-over-allowance outcomes remeasure [table allowances])
  (define over
    (for/list ([o (in-list outcomes)]
               #:when (car (op-outcome-ratios o))
               #:unless (within-allowance? o table))
      (op-outcome-key o)))
  (define again (if (null? over) (hash) (remeasure over)))
  (for/list ([o (in-list outcomes)])
    (define key (op-outcome-key o))
    (if (member key over)
        (struct-copy op-outcome o
                     [ratios (append (op-outcome-ratios o) (list (hash-ref again key #f)))])
        o)))

(define (op-violations outcomes [table allowances])
  (define keys (map op-outcome-key outcomes))
  (append
   (for/list ([o (in-list outcomes)]
              #:unless (within-allowance? o table))
     (define a (allowance-for (op-outcome-key o) table))
     (define ratios (op-outcome-ratios o))
     (format "~a: ~a; allowed ~a (#~a)"
             (op-outcome-label o)
             (if (ormap values ratios)
                 (string-join (map ratio->string ratios) ", re-run ")
                 (format "no ratio, ~a" (op-outcome-reason o)))
             (ratio->string (allowance-ratio a))
             (allowance-issue a)))
   (for/list ([a (in-list table)]
              #:unless (member (allowance-op a) keys))
     (format "allowance ~s: no timed op has that key (#~a)" (allowance-op a) (allowance-issue a)))))

(define (print-verdict violations all-clear [note #f])
  (define total (length violations))
  (define suffix (if note (format "; ~a" note) ""))
  (if (zero? total)
      (printf "strict: ~a~a\n" all-clear suffix)
      (printf "strict: ~a violation~a~a\n" total (if (= total 1) "" "s") suffix))
  (for ([v (in-list violations)])
    (printf "  ~a\n" v))
  (zero? total))

(module+ test
  (require racket/runtime-path
           rackunit
           (only-in racket/file file->string)
           (only-in racket/port with-output-to-string))

  (define-runtime-path perf.rkt "perf.rkt")
  (define-runtime-path perf.py "perf.py")

  (define table
    (list (allowance "f64-matrix" 1.75 115 "measured")))

  (define (outcome key . ratios)
    (op-outcome key (string-append key " label") ratios "py: perf.py printed nothing"))

  (define (no-retime keys)
    (error 'remeasure "called with ~s" keys))

  (test-case "an op the table does not name gets the default"
    (check-equal? (allowance-for "filter" table) default-allowance)
    (check-equal? (allowance-ratio (allowance-for "f64-matrix" table)) 1.75)
    (check-equal? (allowance-issue (allowance-for "f64-matrix" table)) 115))

  (test-case "every allowance names an op that perf.rkt and perf.py both time"
    (for* ([a (in-list allowances)]
           [source (in-list (list perf.rkt perf.py))])
      (check-true (regexp-match? (regexp-quote (format "~s" (allowance-op a))) (file->string source))
                  (format "~a has no op ~s" source (allowance-op a)))))

  (test-case "a ratio is judged as printed, to two decimals"
    (define (judge filter-ratio)
      (op-violations (list (outcome "filter" filter-ratio) (outcome "f64-matrix" 1.75)) table))
    (check-equal? (judge 1.2) '())
    (check-equal? (judge 1.2049) '())
    (check-equal? (judge 1.2051) '("filter label: 1.21×; allowed 1.20× (#88)")))

  (test-case "a violation names the op, its ratios, its allowance and its issue"
    (check-equal? (op-violations (list (outcome "filter" 1.31 1.24)
                                       (outcome "f64-matrix" 1.82 1.79)
                                       (outcome "select" 0.08))
                                 table)
                  '("filter label: 1.31×, re-run 1.24×; allowed 1.20× (#88)"
                    "f64-matrix label: 1.82×, re-run 1.79×; allowed 1.75× (#115)")))

  (test-case "one timing within the allowance is enough"
    (check-equal? (op-violations (list (outcome "filter" 1.31 1.12)
                                       (outcome "f64-matrix" 1.62))
                                 table)
                  '()))

  (test-case "an op with no ratio fails with its reason"
    (check-equal? (op-violations (list (outcome "sort-top5" #f) (outcome "f64-matrix" 1.6)) table)
                  '("sort-top5 label: no ratio, py: perf.py printed nothing; allowed 1.20× (#88)"))
    (check-equal? (op-violations (list (outcome "filter" 1.4 #f) (outcome "f64-matrix" 1.6)) table)
                  '("filter label: 1.40×, re-run n/a; allowed 1.20× (#88)")))

  (test-case "an allowance naming no timed op is a violation"
    (check-equal? (op-violations (list (outcome "filter" 1.0)) table)
                  '("allowance \"f64-matrix\": no timed op has that key (#115)")))

  (test-case "only the ops over their allowance are timed again, all at once"
    (define asked '())
    (define (remeasure keys)
      (set! asked (cons keys asked))
      (hash "filter" 1.1 "describe" 1.5))
    (define settled
      (retime-over-allowance (list (outcome "filter" 1.3)
                                   (outcome "describe" 1.25)
                                   (outcome "f64-matrix" 1.7)
                                   (outcome "sort-top5" #f)
                                   (outcome "select" 0.1))
                             remeasure
                             table))
    (check-equal? asked '(("filter" "describe")))
    (check-equal? (map op-outcome-ratios settled) '((1.3 1.1) (1.25 1.5) (1.7) (#f) (0.1)))
    (check-equal? (op-violations settled table)
                  '("describe label: 1.25×, re-run 1.50×; allowed 1.20× (#88)"
                    "sort-top5 label: no ratio, py: perf.py printed nothing; allowed 1.20× (#88)")))

  (test-case "nothing is timed again when every op is within its allowance"
    (define outcomes (list (outcome "filter" 1.19) (outcome "f64-matrix" 1.74)))
    (check-equal? (retime-over-allowance outcomes no-retime table) outcomes))

  (test-case "an op the re-run does not report keeps no second ratio"
    (check-equal? (map op-outcome-ratios
                       (retime-over-allowance (list (outcome "filter" 1.3)) (lambda (keys) (hash)) table))
                  '((1.3 #f))))

  (test-case "every FAIL is a violation, with its issue"
    (check-equal? (check-violations
                   (list (check-outcome 'T1 "load" 79 #t "336776 × 19")
                         (check-outcome 'C3 "dates" 63 #f "series: cannot infer a dtype")))
                  '("C3 dates: FAIL, series: cannot infer a dtype (#63)")))

  (test-case "the allowance line names the default and each entry"
    (check-equal? (allowance-line (lambda (key) (string-append key " label")) table)
                  "rkt/py at most 1.20× (#88); f64-matrix label 1.75× (#115)"))

  (test-case "the verdict counts the violations and returns whether there are none"
    (define (verdict violations)
      (define ok? #f)
      (define out
        (with-output-to-string
          (lambda () (set! ok? (print-verdict violations "every op within its allowance" "load 1.6")))))
      (list ok? out))
    (check-equal? (verdict '())
                  '(#t "strict: every op within its allowance; load 1.6\n"))
    (check-equal? (verdict '("a: 1.30×; allowed 1.20× (#88)"))
                  '(#f "strict: 1 violation; load 1.6\n  a: 1.30×; allowed 1.20× (#88)\n"))
    (check-equal? (cadr (verdict '("a" "b")))
                  "strict: 2 violations; load 1.6\n  a\n  b\n")))
