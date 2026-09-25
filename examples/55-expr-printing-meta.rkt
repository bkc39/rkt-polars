#lang racket/base

;; Printing expressions and the meta namespace.
;;
;; An expression prints as its plan, in Polars' own notation, and
;; expr->string returns the same text.  The meta-* functions read facts off
;; the plan without running it:
;;   expr.meta.output_name()   ->  (meta-output-name e)
;;   expr.meta.root_names()    ->  (meta-root-names e)
;;   expr.meta.eq(other)       ->  (meta-eq? e other)
;;
;; Inside `nix develop`:
;;   racket examples/55-expr-printing-meta.rkt

(require polars)

(define bmi (~> (col "weight") (/ (pow (col "height") 2)) (alias "bmi")))

(displayln "an expression prints as its plan:")
(displayln bmi)
(printf "as a string: ~s\n" (expr->string bmi))
(println (list (col "a") (~> (col "v") sum (over "g"))))
(newline)

(displayln "output name and the columns it reads:")
(printf "output name: ~a\n" (meta-output-name bmi))
(printf "root names:  ~a\n" (meta-root-names bmi))
(printf "unaliased (first column wins): ~a\n"
        (meta-output-name (+ (col "a") (col "b"))))
(printf "a literal: ~a\n" (meta-output-name (lit 25)))
(printf "a bare name is lifted with col: ~a\n" (meta-root-names "weight"))
(newline)

(displayln "structural equality vs identity:")
(define rebuilt (~> (col "weight") (/ (pow (col "height") 2)) (alias "bmi")))
(printf "meta-eq? ~a, equal? ~a\n" (meta-eq? bmi rebuilt) (equal? bmi rebuilt))
(printf "'float64 and 'f64 build the same selector: ~a\n"
        (meta-eq? (col 'float64) (col 'f64)))
(newline)

(displayln "multi-column expressions:")
(displayln (exclude (all) "id"))
(displayln (col #rx"^sepal_"))
(printf "root names of a regexp col: ~a\n" (meta-root-names (col #rx"^sepal_")))
(printf "root names of a dtype col: ~a\n" (meta-root-names (col 'float64)))
(with-handlers ([exn:fail? (lambda (e) (printf "output name: ~a\n" (exn-message e)))])
  (meta-output-name (col 'float64)))
(newline)

(displayln "checking a generated pipeline before running it:")
(define amplitudes
  (for/list ([period (in-list '("day" "year"))])
    (alias (- (col (string-append period "_high")) (col (string-append period "_low")))
           (string-append period "_amplitude"))))
(for ([e (in-list amplitudes)])
  (printf "~a <- ~a\n" (meta-output-name e) (meta-root-names e)))
