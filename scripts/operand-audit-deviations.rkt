#lang racket/base

(require racket/match
         (only-in racket/list count)
         (only-in polars/private/foreign series-dtype)
         (only-in polars/private/generic/operands operand-action)
         polars/private/generic/operand-audit-table)

(define classes
  '((expression-form
     "ours runs the expression form, (op (col name) (lit v)), and gives its outcome, as AGENTS.md documents for a plain operand beside a Null, Enum or Decimal series, an integer past the dtype's range, a string on the left of + and polars-null")
    (integer-division
     "/ of integer operands (integer, Boolean or Null) is floor division, Python's // (#65)")
    (error-kind
     "both raise, but ours raises a polars error where Python raises a TypeError, ValueError, OverflowError or AttributeError, or the reverse")
    (python-string-format
     "Python's str % x is printf-style formatting, so the series' __rmod__ never runs")
    (racket-short-circuit
     "and / or with a plain value on the left evaluate as Racket's and / or")
    (bitwise
     "Python's & | ^ ~ are bitwise on a non-Boolean series; ours refuse one")
    (past-int64
     "an integer past Int64 is a contract error, since lit cannot carry it")
    (negative-beside-unsigned
     "a negative integer beside an unsigned series is a contract error")
    (temporal-physical
     "Python's eager operator reads a temporal operand beside a number or a string by its physical integer; polars' own kernels, which ours call, refuse it or give another dtype")
    (boolean-operand
     "Python compares or divides a Boolean with a String or Decimal series; ours refuse the Boolean")
    (duration-division
     "/ of a Duration by a number needs polars' true division, which no entry point exposes; ours refuses it")))

(define temporal-labels '(date time duration datetime zoned))

(define (temporal-operand? side operand)
  (match* (side operand)
    [('series (? symbol?)) (and (memq operand temporal-labels) #t)]
    [(_ (list (or 'date 'time 'datetime 'moment 'duration-us) _ ...)) #t]
    [(_ _) #f]))

(define (takes-expression-form? row)
  (match row
    [(list (and op (not (or 'and 'or 'xor 'not))) _ (and side (or 'left 'right)) _ _ ...)
     (eq? (operand-action op (series-dtype (row-series row)) (row-operand row) side) 'expression)]
    [_ #f]))

(define (raised? outcome)
  (match outcome
    [(list 'raises _) #t]
    [_ #f]))

(define (classify row got)
  (match-define (list op label side operand _ ...) row)
  (define python (python-outcome (eager-outcome row)))
  (define alternatives (python-alternatives row))
  (define (alternative? names)
    (for/or ([a (in-list alternatives)])
      (match-define (list name outcome) a)
      (and (memq name names) (equal? outcome got))))
  (cond
    [(and (takes-expression-form? row) (alternative? '(expression))) 'expression-form]
    [(alternative? '(floor floor-expression)) 'integer-division]
    [(and (raised? python) (raised? got)) 'error-kind]
    [(and (eq? op 'mod) (eq? side 'left) (or (string? operand) (symbol? operand)))
     'python-string-format]
    [(and (memq op '(and or)) (eq? side 'left) (not (eq? operand 'null))) 'racket-short-circuit]
    [(memq op '(and or xor not)) 'bitwise]
    [(eqv? operand (expt 2 63)) 'past-int64]
    [(and (memq label '(uint8 uint64)) (memq side '(left right)) (exact-integer? operand)
          (negative? operand))
     'negative-beside-unsigned]
    [(and (eq? op '/) (eq? label 'duration) (eq? side 'right) (real? operand)) 'duration-division]
    [(or (memq label temporal-labels) (temporal-operand? side operand)) 'temporal-physical]
    [(or (eq? operand #t) (and (eq? side 'series) (eq? operand 'boolean))) 'boolean-operand]
    [else #f]))

(define deviating
  (for*/list ([row (in-list audit-rows)]
              [got (in-value (let-values ([(outcome _) (run-row row)]) outcome))]
              #:unless (equal? got (python-outcome (eager-outcome row))))
    (list row (classify row got) got)))

(match deviating
  [(list _ ... (list row #f got) _ ...)
   (eprintf "unclassified: ~s\n  ours: ~s\n" row got)
   (exit 1)]
  [_
   (write-deviations classes
                     (for/list ([d (in-list deviating)])
                       (match-define (list row class got) d)
                       (append (audit-row-key row) (list class got))))
   (for ([c (in-list classes)])
     (match-define (list class _) c)
     (printf "~a ~a\n" class (count (match-lambda [(list _ found _) (eq? found class)])
                                     deviating)))])
