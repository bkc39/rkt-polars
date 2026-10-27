#lang racket/base

(require racket/contract/base
         racket/match
         (prefix-in base: racket/base)
         syntax/parse/define
         (except-in polars/private/foreign series-std series-var)
         (only-in (submod polars/private/foreign internal) series-std series-var)
         (except-in polars/private/expr expr-std expr-var)
         (only-in (submod polars/private/expr internal) expr-std expr-var)
         (only-in polars/private/c-integer uint8/c)
         polars/private/generic/core
         polars/private/generic/dtype
         (only-in polars/private/generic/expr-util ->col-expr col-expr/c)
         (only-in polars/private/resource with-release))

(provide (contract-out
          [std (->* ((or/c series? col-expr/c)) (#:ddof uint8/c) any/c)]
          [var (->* ((or/c series? col-expr/c)) (#:ddof uint8/c) any/c)]
          [n-unique (-> (or/c series? col-expr/c) any/c)]
          [alias (-> col-expr/c string? Expr-ptr?)])
         sum mean min max count median first last)

(define (typed-table i8 i16 i32 i64 u8 u16 u32 u64 f32 f64)
  (hash 'int8 i8 'int16 i16 'int32 i32 'int64 i64
        'uint8 u8 'uint16 u16 'uint32 u32 'uint64 u64
        'float32 f32 'float64 f64))

(define native-reducers
  (hash 'sum (typed-table series-sum-i8 series-sum-i16 series-sum-i32 series-sum-i64
                          series-sum-u8 series-sum-u16 series-sum-u32 series-sum-u64
                          series-sum-f32 series-sum-f64)
        'mean (typed-table series-mean-i8 series-mean-i16 series-mean-i32 series-mean-i64
                           series-mean-u8 series-mean-u16 series-mean-u32 series-mean-u64
                           series-mean-f32 series-mean-f64)
        'min (typed-table series-min-i8 series-min-i16 series-min-i32 series-min-i64
                          series-min-u8 series-min-u16 series-min-u32 series-min-u64
                          series-min-f32 series-min-f64)
        'max (typed-table series-max-i8 series-max-i16 series-max-i32 series-max-i64
                          series-max-u8 series-max-u16 series-max-u32 series-max-u64
                          series-max-f32 series-max-f64)))

(define (reduction-route op dt)
  (match* (op dt)
    [('mean (or 'string 'categorical 'binary (cons 'enum _))) 'null]
    [('sum (or 'int8 'int16 'uint8 'uint16)) 'expr]
    [((or 'std 'var) 'float32) 'expr]
    [((or 'sum 'mean 'min 'max) (? numeric-dtype?)) 'native]
    [((or 'std 'var) (? numeric-dtype?)) 'dispersion]
    [((or 'std 'var) 'boolean) 'float64]
    [(_ (or 'null (? decimal-dtype?))) 'expr]
    [('sum (or 'boolean (list 'duration _))) 'expr]
    [('std (list 'duration _)) 'expr]
    [((or 'mean 'min 'max) _) 'expr]
    [(_ _) #f]))

(define (series-agg-via-expr who expr-op s)
  (with-release ([frame (dataframe-new (list s)) dataframe-drop]
                 [all (expr-all) expr-drop]
                 [reduced (expr-op all) expr-drop]
                 [named (expr-alias reduced "v") expr-drop]
                 [out (dataframe-select-exprs frame (list named)) dataframe-drop]
                 [column (dataframe-column out "v") series-drop])
    (series-value who column 0)))

(define (reduce-series op s #:ddof [ddof 1])
  (define dt (series-dtype s))
  (define series-dispersion (if (eq? op 'std) series-std series-var))
  (match (reduction-route op dt)
    ['native (or ((hash-ref (hash-ref native-reducers op) dt) s) polars-null)]
    ['dispersion (or (series-dispersion s #:ddof ddof) polars-null)]
    ['float64 (with-release ([floats (series-cast s 'float64) series-drop])
                (or (series-dispersion floats #:ddof ddof) polars-null))]
    ['expr (series-agg-via-expr op (lambda (e) (aggregation op e ddof)) s)]
    ['null polars-null]
    [#f (error op "unsupported dtype for reduction: ~v" dt)]))

(define (aggregation op e ddof)
  (match op
    ['sum (expr-sum e)]
    ['mean (expr-mean e)]
    ['min (expr-min e)]
    ['max (expr-max e)]
    ['std (expr-std e #:ddof ddof)]
    ['var (expr-var e #:ddof ddof)]))

(define-syntax-parse-rule (define-reducer (name:id formal:id ... . rest:id) plain:expr)
  (define (name formal ... . rest)
    (match (list* formal ... rest)
      [(list (? Expr-ptr? e)) (aggregation 'name e 1)]
      [(list (? string? column)) (aggregation 'name (col column) 1)]
      [(list (? series? s)) (reduce-series 'name s)]
      [args (apply plain args)])))

(define-reducer (sum . vs) base:+)
(define-reducer (mean v . vs) (lambda args (/ (apply base:+ args) (length args))))
(define-reducer (min . vs) base:min)
(define-reducer (max . vs) base:max)

(define (dispersion op x ddof)
  (match x
    [(? series?) (reduce-series op x #:ddof ddof)]
    [_ (aggregation op (->col-expr op x) ddof)]))

(define (std x #:ddof [ddof 1]) (dispersion 'std x ddof))
(define (var x #:ddof [ddof 1]) (dispersion 'var x ddof))

(define (count x) (expr-count (->col-expr 'count x)))

(define (n-unique x)
  (match x
    [(? series?) (series-n-unique x)]
    [_ (expr-n-unique (->col-expr 'n-unique x))]))

(define (median x) (expr-median (->col-expr 'median x)))

(define (first x)
  (cond
    [(Expr-ptr? x) (expr-first x)]
    [(string? x) (expr-first (col x))]
    [(pair? x) (car x)]
    [else (error 'first "expected an Expr, column name, or non-empty list, got ~v" x)]))

(define (last x)
  (cond
    [(Expr-ptr? x) (expr-last x)]
    [(string? x) (expr-last (col x))]
    [(pair? x) (let loop ([l x]) (if (null? (cdr l)) (car l) (loop (cdr l))))]
    [else (error 'last "expected an Expr, column name, or non-empty list, got ~v" x)]))

(define (alias e name) (expr-alias (->col-expr 'alias e) name))

(module+ test
  (require rackunit
           racket/runtime-path
           (only-in racket/file file->value)
           (only-in racket/list make-list)
           (only-in gregor date datetime)
           (only-in gregor/time time)
           (only-in gregor/period microseconds)
           (only-in polars/private/expr-core expr-drop-count)
           polars/private/generic/test-fixtures
           (prefix-in contracted: (submod "..")))
  (define small (series '(1 2 3) #:dtype 'i8))
  (define flags (series '(#t #f #t)))
  (settle!)
  (let ([exprs (expr-drop-count)] [frames (dataframe-drop-count)] [columns (series-drop-count)])
    (check-equal? (sum small) 6)
    (check >= (- (expr-drop-count) exprs) 3)
    (check >= (- (dataframe-drop-count) frames) 2)
    (check >= (- (series-drop-count) columns) 1))
  (settle!)
  (let ([columns (series-drop-count)])
    (check-= (std flags) (sqrt 1/3) 1e-12)
    (check >= (- (series-drop-count) columns) 1))
  (check-exn #rx"^max: cannot read a datetime in \"Europe/Brussels\": polars panicked: "
             (lambda () (max past-chrono-zoned)))
  (check-exn #rx"^min: cannot read a datetime in \"Europe/Brussels\": polars panicked: "
             (lambda () (min past-chrono-zoned)))
  ;; reductions dispatch on dtype (numeric series)
  (check-equal? (sum ints) 10)
  (check-equal? (max floats) 8.0)
  (check-equal? (min ints) 1)
  (check-equal? (mean ints) 2.5)
  (check-pred flonum? (mean ints))
  ;; numeric fallback preserves racket/base behaviour
  (check-equal? (max 1 2 3) 3)
  (check-equal? (min 4 2 9) 2)
  (check-equal? (sum 1 2 3) 6)
  (check-equal? (sum) 0)
  (check-equal? (mean 2 4) 3)
  ;; non-numeric min/max via the expr engine (matches Polars)
  (check-equal? (min (series '("banana" "apple" "cherry"))) "apple")
  (check-equal? (max (series '("banana" "apple" "cherry"))) "cherry")
  ;; Expr aggregators accept an Expr or a bare column name
  (check-pred Expr-ptr? (sum "value"))
  (check-pred Expr-ptr? (mean (col "value")))
  (check-pred Expr-ptr? (n-unique "group"))
  ;; first / last keep their list-accessor behaviour
  (check-equal? (first '(1 2 3)) 1)
  (check-equal? (last '(1 2 3)) 3)
  (check-pred Expr-ptr? (first (col "value")))
  ;; std / var eager on a series (with #:ddof)
  (let ([s (series '(1.0 2.0 3.0 4.0))])     ; deviations from mean 2.5 sum-sq = 5.0
    (check-= (var s) (/ 5.0 3.0) 1e-9)        ; sample (ddof=1)
    (check-= (var s #:ddof 0) 1.25 1e-9)      ; population (ddof=0)
    (check-= (std s #:ddof 0) (sqrt 1.25) 1e-9))

  (define nothing (series (list polars-null polars-null) #:name "n"))
  (define no-rows (series '() #:dtype 'int64))
  (check-equal? (list (sum nothing) (mean nothing) (min nothing) (max nothing))
                (make-list 4 polars-null))
  (check-equal? (list (sum no-rows) (mean no-rows) (min no-rows) (max no-rows))
                (list 0 polars-null polars-null polars-null))
  (check-equal? (sum (series '(#t #f #t))) 2)
  (check-equal? (sum (series '(100 100 100) #:dtype 'int8)) 300)
  (check-equal? (mean (series '("a" "b"))) polars-null)
  (check-exn #rx"^sum: unsupported dtype for reduction: 'string$"
             (lambda () (sum (series '("a" "b")))))
  (check-equal? (list (std nothing) (var nothing) (n-unique nothing)) (list polars-null polars-null 1))
  (check-equal? (list (std (series '(5))) (std (series '(#t #f)))
                      (n-unique (series (list 1 polars-null))))
                (list polars-null 0.7071067811865476 2))
  (check-exn #rx"^var: unsupported dtype for reduction: 'string$"
             (lambda () (var (series '("a" "b")))))
  (define gaps (series (list polars-null polars-null) #:dtype 'float64))
  (check-equal? (list (series-min-f64 gaps) (series-sum-f64 gaps) (min gaps))
                (list #f 0.0 polars-null))
  (check-exn #rx"^mean: arity mismatch" (lambda () (contracted:mean)))
  (check-exn #rx"^std: contract violation" (lambda () (contracted:std (series '(1 2)) #:ddof -1)))
  (for* ([reduce (list contracted:std contracted:var)]
         [x (list (series '(1 2 3)) (col "v") (series '(1.0 2.0) #:dtype 'float32))])
    (check-exn (regexp (format "^~a: contract violation\n  expected: ~a\n"
                               (object-name reduce)
                               (regexp-quote (format "~s" (contract-name uint8/c)))))
               (lambda () (reduce x #:ddof 256))))
  (check-equal? (mean (series (list (date 2020 1 2) (date 2020 1 1))))
                (datetime 2020 1 1 12 0 0 0))
  (check-exn #rx"^n-unique: contract violation" (lambda () (contracted:n-unique 3)))
  (check-equal? (contracted:sum 1 2 3) 6)
  (define release-counters (list series-drop-count dataframe-drop-count expr-drop-count))
  (define (releases-across reduce s)
    (settle!)
    (define before (map (lambda (counter) (counter)) release-counters))
    (reduce s)
    (map (lambda (counter was) (- (counter) was)) release-counters before))
  (check-equal? (releases-across std (series '(#t #f #t))) '(1 0 0))
  (check-equal? (releases-across var (series '(#t #f #t))) '(1 0 0))
  (check-equal? (releases-across sum (series '(1 2) #:dtype 'int8)) '(1 2 3))
  (check-equal? (releases-across mean (series '("a" "b"))) '(0 0 0))
  (check-equal? (releases-across min (series '("b" "a"))) '(1 2 3))
  (define-runtime-path expected-file "../../scribblings/data/reductions-expected.rktd")
  (define double-epsilon (expt 2.0 -52))
  (define reducers (hash 'sum sum 'mean mean 'min min 'max max 'std std 'var var
                         'n-unique n-unique))
  (define (decode v)
    (match v
      ['null polars-null]
      [(list 'date y m d) (date y m d)]
      [(list 'datetime y mo d h mi s ns) (datetime y mo d h mi s ns)]
      [(list 'time h m s ns) (time h m s ns)]
      [(list 'duration-us n) (microseconds n)]
      [(list 'category name) (string->symbol name)]
      [(list 'decimal digits) (string->number digits 10 'number-or-false 'decimal-as-exact)]
      [_ v]))
  (define (check-reduction op s expected #:ddof [ddof #f])
    (define reduce (hash-ref reducers op))
    (define label (format "~a of ~a ~v ddof ~a" op (dtype s) (series-cells s) ddof))
    (define (run) (if ddof (reduce s #:ddof ddof) (reduce s)))
    (match expected
      ['error (check-exn (regexp (format "^~a: " op)) run label)]
      [(? flonum?) (check-= (run) expected (* 4 double-epsilon (abs expected)) label)]
      [_ (check-equal? (run) (decode expected) label)]))
  (define (check-reduction-table inputs expectations)
    (for* ([expectation (in-list expectations)]
           [cell (in-list (map cons inputs (cdr expectation)))])
      (check-reduction (car expectation) (car cell) (cdr cell))))
  (match-define `((cases ,cases ...) (decimal ,decimal-table ...) (singles ,singles ...))
    (file->value expected-file))
  (for ([row (in-list cases)])
    (match-define (list dt partial expectations ...) row)
    (define (rows->series rows) (series (map decode rows) #:dtype dt))
    (check-reduction-table (map rows->series (list '() '(null null) partial)) expectations))
  (check-reduction-table (list (wrap-series (series-head prices 0))
                               (wrap-series (series-slice prices 2 1))
                               prices)
                         decimal-table)
  (for ([single (in-list singles)])
    (match-define (list op dt rows ddof expected) single)
    (check-reduction op (series (map decode rows) #:dtype dt) expected #:ddof ddof)))
